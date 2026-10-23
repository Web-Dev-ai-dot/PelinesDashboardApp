import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pelines_tokens.dart';

import '../../locations/presentation/pelines_location_selector.dart';
import '../../locations/models/location.dart';
import '../models/order_models.dart';
import '../models/orders_date_filter.dart';

import '../providers/orders_providers.dart';
import 'upcoming_orders_view.dart';
import 'todo_status_board.dart';

class TodayOrdersView extends ConsumerStatefulWidget {
  const TodayOrdersView({
    required this.location,
    required this.onChangeLocation,
    this.showLocationSelector = true,
    this.initialDateFilter = OrdersDateFilter.today,
    this.webOrders = false,
    super.key,
  });
  final Location location;
  final VoidCallback onChangeLocation;
  final bool showLocationSelector;
  final OrdersDateFilter initialDateFilter;
  final bool webOrders;

  @override
  ConsumerState<TodayOrdersView> createState() => TodayOrdersViewState();
}

class TodayOrdersViewState extends ConsumerState<TodayOrdersView> {
  Future<void> refresh() => !widget.webOrders
      ? ref.read(todayOrdersProvider.notifier).refresh()
      : ref.read(calendarOrdersProvider.notifier).refresh();

  void _retry() {
    if (!widget.webOrders) {
      ref.invalidate(todayOrdersProvider);
    } else {
      ref.invalidate(calendarOrdersProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayOrdersProvider);
    final AsyncValue<TodayOrdersState> asyncOrders = !widget.webOrders
        ? today
        : ref.watch(calendarOrdersProvider).whenData((state) {
            final orders = filterOrdersByDate(
              state.orders
                  .where((o) => o.locationId == widget.location.id)
                  .toList(),
              OrdersDateFilter.upcoming,
            )..sort(compareOperationalOrders);
            return TodayOrdersState(
              orders: orders,
              isRefreshing: state.isRefreshing,
              refreshError: state.refreshError,
            );
          });
    // Refresh Upcoming after the shared mutation's canonical reconciliation.
    // Never switch filters or navigate on Accept.
    for (final order in asyncOrders.value?.orders ?? <OrderSummary>[]) {
      if (!widget.webOrders || order.locationId != widget.location.id) {
        continue;
      }
      ref.listen(orderMutationProvider(order.id), (previous, next) {
        if (next.action != null &&
            next.canonicalOrder != null &&
            previous?.phase != next.phase &&
            (next.phase == OrderMutationPhase.success ||
                next.phase == OrderMutationPhase.error)) {
          ref.read(calendarOrdersProvider.notifier).refresh();
        }
      });
    }
    if (widget.webOrders) {
      return UpcomingOrdersView(
        orders: asyncOrders,
        initialDateFilter: widget.initialDateFilter,
        onRefresh: refresh,
        onRetry: _retry,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.showLocationSelector)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: PelinesSpacing.md,
              vertical: PelinesSpacing.sm,
            ),
            child: PelinesLocationSelector(
              locationName: widget.location.name,
              onPressed: widget.onChangeLocation,
            ),
          ),
        Expanded(
          child: asyncOrders.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object error, StackTrace stack) =>
                _ErrorState(message: error.toString(), onRetry: _retry),
            data: (TodayOrdersState state) {
              return RefreshIndicator(
                onRefresh: refresh,
                child: Column(
                  children: [
                    if (state.isRefreshing)
                      const LinearProgressIndicator(minHeight: 2),
                    if (state.refreshError != null)
                      TextButton(
                        onPressed: refresh,
                        child: Text('${state.refreshError}'),
                      ),
                    Expanded(
                      child: TodoStatusBoard(
                        orders: state.orders,
                        pickedUpOrders:
                            state.snapshotLocationId == widget.location.id
                            ? filterTodayPickedUpOrders(
                                state.fullLocationSnapshot ?? const [],
                                locationId: widget.location.id,
                              )
                            : const [],
                        showChannel: true,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: Text(tr(context, 'Try again')),
          ),
        ],
      ),
    ),
  );
}
