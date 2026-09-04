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
        order.id != orderId ||
        !OrderStatusAction.allows(
          order.status,
          action.target,
          fulfillment: order.fulfillmentType,
        )) {
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
