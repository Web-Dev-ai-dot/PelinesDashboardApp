import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/time/pelines_time.dart';
import '../../auth/providers/auth_providers.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../data/orders_repository.dart';
import '../models/order_models.dart';
import '../models/order_status_action.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>((Ref ref) {
  return ApiOrdersRepository(ref.watch(apiClientProvider));
});

final todayOrdersProvider =
    AsyncNotifierProvider<TodayOrdersController, TodayOrdersState>(
      TodayOrdersController.new,
    );

final completedOrdersProvider =
    AsyncNotifierProvider<CompletedOrdersController, HistoricalOrdersState>(
      CompletedOrdersController.new,
    );

final cancelledOrdersProvider =
    AsyncNotifierProvider<CancelledOrdersController, HistoricalOrdersState>(
      CancelledOrdersController.new,
    );

final calendarOrdersProvider =
    AsyncNotifierProvider<CalendarOrdersController, HistoricalOrdersState>(
      CalendarOrdersController.new,
    );

final orderDetailProvider = FutureProvider.family<OrderDetail, String>((
  Ref ref,
  String id,
) async {
  try {
    return await ref.watch(ordersRepositoryProvider).getOrderById(id);
  } on ApiException catch (error) {
    if (error.statusCode == 401) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
    rethrow;
  }
});

final orderMutationProvider = NotifierProvider.autoDispose
    .family<OrderMutationController, OrderMutationState, String>(
      OrderMutationController.new,
    );

final orderNotesProvider = NotifierProvider.autoDispose
    .family<OrderNotesController, OrderNotesState, String>(
      OrderNotesController.new,
    );

enum OrderNotesPhase { clean, dirty, saving, reconciling, saved, error }

class OrderNotesState {
  const OrderNotesState({
    this.phase = OrderNotesPhase.clean,
    this.serverNotes = '',
    this.draft = '',
    this.initialized = false,
    this.hasRemoteConflict = false,
    this.errorMessage,
    this.orderMissing = false,
  });

  final OrderNotesPhase phase;
  final String serverNotes;
  final String draft;
  final bool initialized;
  final bool hasRemoteConflict;
  final String? errorMessage;
  final bool orderMissing;

  bool get isDirty => draft != serverNotes;
  bool get isBusy =>
      phase == OrderNotesPhase.saving || phase == OrderNotesPhase.reconciling;
  bool get isValid => draft.length <= OrderNotesController.maxLength;
  bool get canSave => isDirty && isValid && !isBusy && !orderMissing;
}

class OrderNotesController extends Notifier<OrderNotesState> {
  OrderNotesController(this.orderId);

  static const int maxLength = 5000;
  final String orderId;

  @override
  OrderNotesState build() => const OrderNotesState();

  void syncFromCanonical(String? notes) {
    final String remote = notes ?? '';
    if (!state.initialized) {
      state = OrderNotesState(
        serverNotes: remote,
        draft: remote,
        initialized: true,
      );
      return;
    }
    if (state.isBusy || remote == state.serverNotes) return;
    if (!state.isDirty) {
      state = OrderNotesState(
        serverNotes: remote,
        draft: remote,
        initialized: true,
      );
      return;
    }
    final bool remainsDirty = state.draft != remote;
    state = OrderNotesState(
      phase: remainsDirty ? OrderNotesPhase.dirty : OrderNotesPhase.clean,
      serverNotes: remote,
      draft: state.draft,
      initialized: true,
      hasRemoteConflict: remainsDirty,
    );
  }

  void edit(String draft) {
    if (state.isBusy || state.orderMissing) return;
    final bool dirty = draft != state.serverNotes;
    state = OrderNotesState(
      phase: dirty ? OrderNotesPhase.dirty : OrderNotesPhase.clean,
      serverNotes: state.serverNotes,
      draft: draft,
      initialized: true,
      hasRemoteConflict: dirty && state.hasRemoteConflict,
    );
  }

  Future<void> save({bool overwriteConflict = false}) async {
    if (!state.canSave ||
        state.hasRemoteConflict && !overwriteConflict ||
        ref.read(orderMutationProvider(orderId)).isBusy) {
      return;
    }
    final String attempted = state.draft;
    final String previousServer = state.serverNotes;
    state = OrderNotesState(
      phase: OrderNotesPhase.saving,
      serverNotes: previousServer,
      draft: attempted,
      initialized: true,
      hasRemoteConflict: state.hasRemoteConflict,
    );
    try {
      await ref
          .read(ordersRepositoryProvider)
          .updateInternalNotes(orderId: orderId, internalNotes: attempted);
      state = OrderNotesState(
        phase: OrderNotesPhase.reconciling,
        serverNotes: previousServer,
        draft: attempted,
        initialized: true,
      );
      await _reconcile(attempted, previousServer);
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await ref.read(authControllerProvider.notifier).signOut();
      }
      if (_isAmbiguousNetworkError(error)) {
        state = OrderNotesState(
          phase: OrderNotesPhase.reconciling,
          serverNotes: previousServer,
          draft: attempted,
          initialized: true,
        );
        await _reconcile(attempted, previousServer, patchError: error);
      } else {
        state = OrderNotesState(
          phase: OrderNotesPhase.error,
          serverNotes: previousServer,
          draft: attempted,
          initialized: true,
          errorMessage: error.message,
          orderMissing: error.statusCode == 404,
        );
      }
    } on Object {
      state = OrderNotesState(
        phase: OrderNotesPhase.error,
        serverNotes: previousServer,
        draft: attempted,
        initialized: true,
        errorMessage: 'Internal notes could not be saved.',
      );
    }
  }

  Future<void> _reconcile(
    String attempted,
    String previousServer, {
    ApiException? patchError,
  }) async {
    try {
      final OrderDetail canonical = await ref
          .read(ordersRepositoryProvider)
          .getOrderById(orderId);
      final String remote = canonical.internalNotes ?? '';
      if (remote == attempted) {
        state = OrderNotesState(
          phase: OrderNotesPhase.saved,
          serverNotes: remote,
          draft: attempted,
          initialized: true,
        );
      } else {
        final bool unchanged = remote == previousServer;
        state = OrderNotesState(
          phase: OrderNotesPhase.error,
          serverNotes: remote,
          draft: attempted,
          initialized: true,
          hasRemoteConflict: !unchanged,
          errorMessage: unchanged
              ? '${patchError?.message ?? 'The note was not saved.'} You can try again.'
              : 'This note was updated elsewhere.',
        );
      }
      ref.invalidate(orderDetailProvider(orderId));
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await ref.read(authControllerProvider.notifier).signOut();
      }
      state = OrderNotesState(
        phase: OrderNotesPhase.error,
        serverNotes: previousServer,
        draft: attempted,
        initialized: true,
        errorMessage:
            '${patchError?.message ?? 'The note may have been saved.'} The current note could not be verified.',
        orderMissing: error.statusCode == 404,
      );
    }
  }

  void discardDraft() {
    state = OrderNotesState(
      serverNotes: state.serverNotes,
      draft: state.serverNotes,
      initialized: true,
    );
  }

  bool _isAmbiguousNetworkError(ApiException error) {
    final Object? cause = error.cause;
    if (cause is! DioException) return false;
    return cause.type == DioExceptionType.connectionTimeout ||
        cause.type == DioExceptionType.sendTimeout ||
        cause.type == DioExceptionType.receiveTimeout ||
        cause.type == DioExceptionType.connectionError;
  }
}

enum OrderMutationPhase { idle, submitting, reconciling, success, error }

class OrderMutationState {
  const OrderMutationState({
    this.phase = OrderMutationPhase.idle,
    this.canonicalOrder,
    this.action,
    this.message,
    this.terminalRetryAllowed = false,
  });

  final OrderMutationPhase phase;
  final OrderDetail? canonicalOrder;
  final OrderStatusAction? action;
  final String? message;
  final bool terminalRetryAllowed;

  bool get isBusy =>
      phase == OrderMutationPhase.submitting ||
      phase == OrderMutationPhase.reconciling;
}

class OrderMutationController extends Notifier<OrderMutationState> {
  OrderMutationController(this.orderId);

  final String orderId;

  @override
  OrderMutationState build() => const OrderMutationState();

  Future<void> acceptOrder(OrderDetail order) =>
      _run(order, OrderStatusAction.acceptOrder);

  Future<void> startPreparing(OrderDetail order) =>
      _run(order, OrderStatusAction.startPreparing);

  Future<void> markReady(OrderDetail order) =>
      _run(order, OrderStatusAction.markReady);

  Future<void> markOrderCompleted(OrderDetail order) =>
      _run(order, OrderStatusAction.completeOrder);

  void adoptChangedOrder(OrderDetail order) {
    if (state.isBusy) return;
    state = OrderMutationState(
      phase: OrderMutationPhase.error,
      canonicalOrder: order,
      message: 'Order status changed on the server.',
    );
  }

  Future<void> performCurrentAction(OrderDetail order) async {
    final OrderStatusAction? action = OrderStatusAction.forOrder(
      order.status,
      order.fulfillmentType,
    );
    if (action != null) await _run(order, action);
  }

  Future<void> _run(OrderDetail order, OrderStatusAction action) async {
    if (state.isBusy ||
        ref.read(orderNotesProvider(orderId)).isBusy ||
        order.id != orderId ||
        !OrderStatusAction.allows(
          order.status,
          action.target,
          fulfillment: order.fulfillmentType,
        )) {
      return;
    }
    if (!order.paymentStatus.isOperationallyPaid) {
      state = OrderMutationState(
        phase: OrderMutationPhase.error,
        canonicalOrder: order,
        action: action,
        message: 'This order cannot be processed because its payment is not marked as paid.',
      );
      return;
    }

    state = OrderMutationState(
      phase: OrderMutationPhase.submitting,
      canonicalOrder: order,
      action: action,
    );
    try {
      final OrderDetail provisional = await ref
          .read(ordersRepositoryProvider)
          .updateOrderStatus(orderId: orderId, status: action.target);
      state = OrderMutationState(
        phase: OrderMutationPhase.reconciling,
        canonicalOrder: provisional,
        action: action,
      );
      await _reconcileAfterSuccess(action);
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await ref.read(authControllerProvider.notifier).signOut();
      }
      if (_isAmbiguousNetworkError(error) ||
          action == OrderStatusAction.completeOrder &&
              error.statusCode != 401) {
        await _reconcileAmbiguous(order, action, error);
      } else {
        state = OrderMutationState(
          phase: OrderMutationPhase.error,
          canonicalOrder: order,
          action: action,
          message: error.message,
        );
      }
    } on Object {
      state = OrderMutationState(
        phase: OrderMutationPhase.error,
        canonicalOrder: order,
        action: action,
        message: 'The order could not be updated.',
      );
    }
  }

  Future<void> _reconcileAfterSuccess(OrderStatusAction action) async {
    try {
      final OrderDetail canonical = await ref
          .read(ordersRepositoryProvider)
          .getOrderById(orderId);
      state = OrderMutationState(
        phase: OrderMutationPhase.success,
        canonicalOrder: canonical,
        action: action,
        message: canonical.status == action.target
            ? action.successMessageFor(canonical.fulfillmentType)
            : 'Order status changed on the server.',
      );
      ref.invalidate(orderDetailProvider(orderId));
      ref.invalidate(todayOrdersProvider);
      await ref.read(todayOrdersProvider.future);
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await ref.read(authControllerProvider.notifier).signOut();
      }
      state = OrderMutationState(
        phase: OrderMutationPhase.error,
        canonicalOrder: state.canonicalOrder,
        action: action,
        message: 'Status updated, but refresh failed. ${error.message}',
      );
    }
  }

  Future<void> _reconcileAmbiguous(
    OrderDetail original,
    OrderStatusAction action,
    ApiException patchError,
  ) async {
    state = OrderMutationState(
      phase: OrderMutationPhase.reconciling,
      canonicalOrder: original,
      action: action,
    );
    try {
      final OrderDetail canonical = await ref
          .read(ordersRepositoryProvider)
          .getOrderById(orderId);
      final bool applied = canonical.status == action.target;
      final bool unchanged = canonical.status == original.status;
      final bool terminalRetryAllowed =
          action == OrderStatusAction.completeOrder &&
          canonical.status == OrderStatus.ready &&
          (canonical.fulfillmentType == FulfillmentType.pickup ||
              canonical.fulfillmentType == FulfillmentType.delivery);
      state = OrderMutationState(
        phase: applied ? OrderMutationPhase.success : OrderMutationPhase.error,
        canonicalOrder: canonical,
        action: action,
        message: applied
            ? action.successMessageFor(canonical.fulfillmentType)
            : unchanged
            ? '${patchError.message} You can try again.'
            : 'Order status changed on the server.',
        terminalRetryAllowed: terminalRetryAllowed,
      );
      ref.invalidate(orderDetailProvider(orderId));
      ref.invalidate(todayOrdersProvider);
      await ref.read(todayOrdersProvider.future);
    } on ApiException catch (reconcileError) {
      if (reconcileError.statusCode == 401) {
        await ref.read(authControllerProvider.notifier).signOut();
      }
      state = OrderMutationState(
        phase: OrderMutationPhase.error,
        canonicalOrder: original,
        action: action,
        message:
            '${patchError.message} The current order status could not be verified.',
      );
    }
  }

  bool _isAmbiguousNetworkError(ApiException error) {
    final Object? cause = error.cause;
    if (cause is! DioException) return false;
    return cause.type == DioExceptionType.connectionTimeout ||
        cause.type == DioExceptionType.sendTimeout ||
        cause.type == DioExceptionType.receiveTimeout ||
        cause.type == DioExceptionType.connectionError;
  }
}

class TodayOrdersState {
  const TodayOrdersState({
    required this.orders,
    this.isRefreshing = false,
    this.refreshError,
  });
  final List<OrderSummary> orders;
  final bool isRefreshing;
  final String? refreshError;

  TodayOrdersState copyWith({
    List<OrderSummary>? orders,
    bool? isRefreshing,
    String? refreshError,
    bool clearError = false,
  }) {
    return TodayOrdersState(
      orders: orders ?? this.orders,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      refreshError: clearError ? null : refreshError ?? this.refreshError,
    );
  }
}

class TodayOrdersController extends AsyncNotifier<TodayOrdersState> {
  bool _requestInFlight = false;

  @override
  Future<TodayOrdersState> build() async {
    final Location? location = await ref.watch(currentLocationProvider.future);
    if (location == null) {
      return const TodayOrdersState(orders: <OrderSummary>[]);
    }
    return TodayOrdersState(orders: await _load(location.id));
  }

  Future<void> refresh() async {
    if (_requestInFlight) return;
    final Location? location = await ref.read(currentLocationProvider.future);
    if (location == null) return;
    _requestInFlight = true;
    final TodayOrdersState? previous = state.value;
    if (previous != null) {
      state = AsyncData(
        previous.copyWith(isRefreshing: true, clearError: true),
      );
    }
    try {
      final List<OrderSummary> orders = await _load(location.id);
      if (ref.read(currentLocationProvider).value?.id == location.id) {
        state = AsyncData(TodayOrdersState(orders: orders));
      }
    } on Object catch (error, stackTrace) {
      if (previous == null) {
        state = AsyncError<TodayOrdersState>(error, stackTrace);
      } else {
        state = AsyncData(
          previous.copyWith(isRefreshing: false, refreshError: _message(error)),
        );
      }
    } finally {
      _requestInFlight = false;
    }
  }

  Future<List<OrderSummary>> _load(String locationId) async {
    try {
      final List<OrderSummary> all = await ref
          .read(ordersRepositoryProvider)
          .getOrders(locationId: locationId);
      return filterTodayActiveOrders(all);
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await ref.read(authControllerProvider.notifier).signOut();
      }
      rethrow;
    }
  }
}

class HistoricalOrdersState {
  const HistoricalOrdersState({
    required this.orders,
    this.isRefreshing = false,
    this.refreshError,
  });

  final List<OrderSummary> orders;
  final bool isRefreshing;
  final String? refreshError;

  HistoricalOrdersState refreshing() =>
      HistoricalOrdersState(orders: orders, isRefreshing: true);

  HistoricalOrdersState failed(String message) =>
      HistoricalOrdersState(orders: orders, refreshError: message);
}

abstract class HistoricalOrdersController
    extends AsyncNotifier<HistoricalOrdersState> {
  OrderStatus get status;

  bool _requestInFlight = false;

  @override
  Future<HistoricalOrdersState> build() async {
    final Location? location = await ref.watch(currentLocationProvider.future);
    if (location == null) {
      return const HistoricalOrdersState(orders: <OrderSummary>[]);
    }
    return HistoricalOrdersState(orders: await _load(location.id));
  }

  Future<void> refresh() async {
    if (_requestInFlight) return;
    final Location? location = await ref.read(currentLocationProvider.future);
    if (location == null) return;
    _requestInFlight = true;
    final HistoricalOrdersState? previous = state.value;
    if (previous != null) state = AsyncData(previous.refreshing());
    try {
      final List<OrderSummary> orders = await _load(location.id);
      if (ref.read(currentLocationProvider).value?.id == location.id) {
        state = AsyncData(HistoricalOrdersState(orders: orders));
      }
    } on Object catch (error, stackTrace) {
      if (previous == null) {
        state = AsyncError<HistoricalOrdersState>(error, stackTrace);
      } else {
        state = AsyncData(previous.failed(_message(error)));
      }
    } finally {
      _requestInFlight = false;
    }
  }

  Future<List<OrderSummary>> _load(String locationId) async {
    try {
      final List<OrderSummary> orders = await ref
          .read(ordersRepositoryProvider)
          .getOrders(locationId: locationId, status: status);
      final List<OrderSummary> sorted = List<OrderSummary>.of(orders);
      sorted.sort(
        status == OrderStatus.delivered
            ? compareCompletedOrders
            : compareCancelledOrders,
      );
      return List<OrderSummary>.unmodifiable(sorted);
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await ref.read(authControllerProvider.notifier).signOut();
      }
      rethrow;
    }
  }
}

class CompletedOrdersController extends HistoricalOrdersController {
  @override
  OrderStatus get status => OrderStatus.delivered;
}

class CancelledOrdersController extends HistoricalOrdersController {
  @override
  OrderStatus get status => OrderStatus.cancelled;
}

class CalendarOrdersController extends AsyncNotifier<HistoricalOrdersState> {
  bool _requestInFlight = false;

  @override
  Future<HistoricalOrdersState> build() async {
    final Location? location = await ref.watch(currentLocationProvider.future);
    if (location == null) {
      return const HistoricalOrdersState(orders: <OrderSummary>[]);
    }
    return HistoricalOrdersState(orders: await _load(location.id));
  }

  Future<void> refresh() async {
    if (_requestInFlight) return;
    final Location? location = await ref.read(currentLocationProvider.future);
    if (location == null) return;
    _requestInFlight = true;
    final HistoricalOrdersState? previous = state.value;
    if (previous != null) state = AsyncData(previous.refreshing());
    try {
      final List<OrderSummary> orders = await _load(location.id);
      if (ref.read(currentLocationProvider).value?.id == location.id) {
        state = AsyncData(HistoricalOrdersState(orders: orders));
      }
    } on Object catch (error, stackTrace) {
      state = previous == null
          ? AsyncError<HistoricalOrdersState>(error, stackTrace)
          : AsyncData(previous.failed(_message(error)));
    } finally {
      _requestInFlight = false;
    }
  }

  Future<List<OrderSummary>> _load(String locationId) async {
    try {
      final List<OrderSummary> orders = await ref
          .read(ordersRepositoryProvider)
          .getOrders(locationId: locationId);
      return calendarRelevantOrders(orders);
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await ref.read(authControllerProvider.notifier).signOut();
      }
      rethrow;
    }
  }
}

List<OrderSummary> calendarRelevantOrders(List<OrderSummary> orders) {
  const Set<OrderStatus> operational = <OrderStatus>{
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.ready,
  };
  return List<OrderSummary>.unmodifiable(
    orders.where(
      (OrderSummary order) =>
          operational.contains(order.status) &&
          order.paymentStatus.isOperationallyPaid,
    ),
  );
}

Map<String, List<OrderSummary>> groupScheduledOrdersByPacificDay(
  List<OrderSummary> orders,
) {
  final Map<String, List<OrderSummary>> grouped =
      <String, List<OrderSummary>>{};
  for (final OrderSummary order in orders) {
    final DateTime? scheduled = order.scheduledFor;
    if (scheduled == null) continue;
    grouped
        .putIfAbsent(PelinesTime.dayKey(scheduled), () => <OrderSummary>[])
        .add(order);
  }
  for (final List<OrderSummary> day in grouped.values) {
    day.sort((OrderSummary a, OrderSummary b) {
      final int time = a.scheduledFor!.compareTo(b.scheduledFor!);
      return time != 0 ? time : a.orderNumber.compareTo(b.orderNumber);
    });
  }
  return grouped;
}

List<OrderSummary> unscheduledCalendarOrders(List<OrderSummary> orders) {
  final List<OrderSummary> result = orders
      .where((OrderSummary order) => order.scheduledFor == null)
      .toList();
  result.sort((OrderSummary a, OrderSummary b) {
    final int created = b.createdAt.compareTo(a.createdAt);
    return created != 0 ? created : a.orderNumber.compareTo(b.orderNumber);
  });
  return List<OrderSummary>.unmodifiable(result);
}

int compareCompletedOrders(OrderSummary a, OrderSummary b) {
  final DateTime aTime = a.deliveredAt ?? a.operationalAt;
  final DateTime bTime = b.deliveredAt ?? b.operationalAt;
  return _compareHistoryDescending(a, b, aTime, bTime);
}

int compareCancelledOrders(OrderSummary a, OrderSummary b) =>
    _compareHistoryDescending(a, b, a.operationalAt, b.operationalAt);

int _compareHistoryDescending(
  OrderSummary a,
  OrderSummary b,
  DateTime aTime,
  DateTime bTime,
) {
  final int primary = bTime.compareTo(aTime);
  if (primary != 0) return primary;
  final int created = b.createdAt.compareTo(a.createdAt);
  if (created != 0) return created;
  return a.orderNumber.compareTo(b.orderNumber);
}

List<OrderSummary> filterTodayActiveOrders(
  List<OrderSummary> orders, {
  DateTime? now,
}) {
  const Set<OrderStatus> active = <OrderStatus>{
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.ready,
  };
  final List<OrderSummary> result = orders
      .where(
        (OrderSummary order) =>
            order.paymentStatus.isOperationallyPaid &&
            active.contains(order.status) &&
            PelinesTime.isToday(order.operationalAt, now: now),
      )
      .toList(growable: false);
  result.sort(compareOperationalOrders);
  return result;
}

int compareOperationalOrders(OrderSummary a, OrderSummary b) {
  final bool aScheduled = a.scheduledFor != null;
  final bool bScheduled = b.scheduledFor != null;
  if (aScheduled != bScheduled) return aScheduled ? -1 : 1;
  final int operational = a.operationalAt.compareTo(b.operationalAt);
  if (operational != 0) return operational;
  final int created = a.createdAt.compareTo(b.createdAt);
  if (created != 0) return created;
  return a.orderNumber.compareTo(b.orderNumber);
}

String _message(Object error) =>
    error is ApiException ? error.message : 'Refresh failed.';
