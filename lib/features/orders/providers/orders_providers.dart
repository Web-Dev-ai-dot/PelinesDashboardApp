import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/time/pelines_time.dart';
import '../../auth/providers/auth_providers.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../data/orders_repository.dart';
import '../models/order_models.dart';

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
    final Location? location = ref.read(currentLocationProvider).value;
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
