import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/pelines_time.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../models/order_models.dart';
import '../providers/orders_providers.dart';
import 'order_ui_helpers.dart';

enum HistoricalOrdersKind { completed, cancelled }

class HistoricalOrdersScreen extends ConsumerWidget {
  const HistoricalOrdersScreen({required this.kind, super.key});

  final HistoricalOrdersKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Location?> location = ref.watch(currentLocationProvider);
    final AsyncValue<HistoricalOrdersState> orders = switch (kind) {
      HistoricalOrdersKind.completed => ref.watch(completedOrdersProvider),
      HistoricalOrdersKind.cancelled => ref.watch(cancelledOrdersProvider),
    };
    final String title = kind == HistoricalOrdersKind.completed
        ? 'Completed Orders'
        : 'Cancelled Orders';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: location.value == null ? null : () => _refresh(ref),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: location.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => _HistoryError(
          message: error.toString(),
          onRetry: () => ref.invalidate(currentLocationProvider),
        ),
        data: (Location? selected) {
          if (selected == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Choose a location to view orders.'),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  selected.name,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Expanded(child: _buildOrders(ref, orders)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOrders(
    WidgetRef ref,
    AsyncValue<HistoricalOrdersState> asyncOrders,
  ) => asyncOrders.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (Object error, StackTrace stack) => _HistoryError(
      message: error.toString(),
      onRetry: () => _invalidate(ref),
    ),
    data: (HistoricalOrdersState state) => RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          if (state.isRefreshing)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (state.refreshError != null)
            SliverToBoxAdapter(
              child: MaterialBanner(
                content: Text('${state.refreshError} Showing previous data.'),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => _refresh(ref),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          if (state.orders.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    kind == HistoricalOrdersKind.completed
                        ? 'No completed orders for this location.'
                        : 'No cancelled orders for this location.',
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList.builder(
                itemCount: state.orders.length,
                itemBuilder: (BuildContext context, int index) =>
                    _HistoricalOrderCard(
                      order: state.orders[index],
                      kind: kind,
                    ),
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _refresh(WidgetRef ref) => switch (kind) {
    HistoricalOrdersKind.completed =>
      ref.read(completedOrdersProvider.notifier).refresh(),
    HistoricalOrdersKind.cancelled =>
      ref.read(cancelledOrdersProvider.notifier).refresh(),
  };

  void _invalidate(WidgetRef ref) {
    switch (kind) {
      case HistoricalOrdersKind.completed:
        ref.invalidate(completedOrdersProvider);
      case HistoricalOrdersKind.cancelled:
        ref.invalidate(cancelledOrdersProvider);
    }
  }
}

class _HistoricalOrderCard extends StatelessWidget {
  const _HistoricalOrderCard({required this.order, required this.kind});

  final OrderSummary order;
  final HistoricalOrdersKind kind;

  @override
  Widget build(BuildContext context) {
    final DateTime primaryTime = kind == HistoricalOrdersKind.completed
        ? order.deliveredAt ?? order.operationalAt
        : order.operationalAt;
    final String? terminalLabel = order.deliveredAt == null
        ? null
        : order.fulfillmentType == FulfillmentType.pickup
        ? 'Picked up'
        : 'Delivered';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/app/orders/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      order.orderNumber,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  StatusChip(
                    status: order.status,
                    fulfillment: order.fulfillmentType,
                    rawStatus: order.rawStatus,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                terminalLabel == null
                    ? PelinesTime.formatDateTime(primaryTime)
                    : '$terminalLabel: ${PelinesTime.formatDateTime(primaryTime)}',
              ),
              const SizedBox(height: 10),
              Text(
                order.eventName?.isNotEmpty == true
                    ? order.eventName!
                    : order.contactName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${orderTypeLabel(order.orderType)} · ${fulfillmentLabel(order.fulfillmentType)}',
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${order.itemCount} ${order.itemCount == 1 ? 'item' : 'items'}',
                    ),
                  ),
                  Text(
                    money(order.totalCents),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(paymentStatusLabel(order.paymentStatus)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.message, required this.onRetry});

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
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
