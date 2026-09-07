import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../models/order_models.dart';
import '../models/history_filters.dart';
import '../providers/orders_providers.dart';
import 'order_ui_helpers.dart';

enum HistoricalOrdersKind { completed, cancelled }

class HistoricalOrdersScreen extends ConsumerStatefulWidget {
  const HistoricalOrdersScreen({required this.kind, super.key});

  final HistoricalOrdersKind kind;

  @override
  ConsumerState<HistoricalOrdersScreen> createState() =>
      _HistoricalOrdersScreenState();
}

class _HistoricalOrdersScreenState
    extends ConsumerState<HistoricalOrdersScreen> {
  HistoryFilters _filters = const HistoryFilters();
  String? _locationId;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Location?> location = ref.watch(currentLocationProvider);
    final AsyncValue<HistoricalOrdersState> orders = switch (widget.kind) {
      HistoricalOrdersKind.completed => ref.watch(completedOrdersProvider),
      HistoricalOrdersKind.cancelled => ref.watch(cancelledOrdersProvider),
    };
    final String title = widget.kind == HistoricalOrdersKind.completed
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
          if (_locationId != selected.id) {
            _locationId = selected.id;
            _filters = const HistoryFilters();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PelinesSpacing.md,
                  PelinesSpacing.sm,
                  PelinesSpacing.md,
                  PelinesSpacing.xxs,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PelinesStateBadge(
                    label: selected.name,
                    foreground: PelinesColors.brandPrimary,
                    background: PelinesColors.brandPrimarySoft,
                    icon: Icons.storefront_outlined,
                  ),
                ),
              ),
              _HistoryFilterBar(
                filters: _filters,
                showPayment: widget.kind == HistoricalOrdersKind.cancelled,
                onChanged: (HistoryFilters value) =>
                    setState(() => _filters = value),
                onClear: () =>
                    setState(() => _filters = const HistoryFilters()),
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
    data: (HistoricalOrdersState state) {
      final List<OrderSummary> visible = filterHistoricalOrders(
        state.orders,
        _filters,
        timestamp: widget.kind == HistoricalOrdersKind.completed
            ? (OrderSummary order) => order.deliveredAt ?? order.operationalAt
            : null,
      );
      return RefreshIndicator(
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
            if (visible.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(PelinesSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.receipt_long_outlined,
                          size: 48,
                          color: PelinesColors.textSecondary,
                        ),
                        const SizedBox(height: PelinesSpacing.sm),
                        Text(
                          state.orders.isNotEmpty
                              ? 'No orders match these filters.'
                              : widget.kind == HistoricalOrdersKind.completed
                              ? 'No completed orders for this location.'
                              : 'No cancelled orders for this location.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  PelinesSpacing.md,
                  PelinesSpacing.xs,
                  PelinesSpacing.md,
                  PelinesSpacing.xl,
                ),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _HistoricalOrderCard(
                        order: visible[index],
                        kind: widget.kind,
                      ),
                ),
              ),
          ],
        ),
      );
    },
  );

  Future<void> _refresh(WidgetRef ref) => switch (widget.kind) {
    HistoricalOrdersKind.completed =>
      ref.read(completedOrdersProvider.notifier).refresh(),
    HistoricalOrdersKind.cancelled =>
      ref.read(cancelledOrdersProvider.notifier).refresh(),
  };

  void _invalidate(WidgetRef ref) {
    switch (widget.kind) {
      case HistoricalOrdersKind.completed:
        ref.invalidate(completedOrdersProvider);
      case HistoricalOrdersKind.cancelled:
        ref.invalidate(cancelledOrdersProvider);
    }
  }
}

class _HistoryFilterBar extends StatelessWidget {
  const _HistoryFilterBar({
    required this.filters,
    required this.showPayment,
    required this.onChanged,
    required this.onClear,
  });

  final HistoryFilters filters;
  final bool showPayment;
  final ValueChanged<HistoryFilters> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: <Widget>[
        _MenuFilter<HistoryDateFilter>(
          label: switch (filters.date) {
            HistoryDateFilter.allLoaded => 'All loaded',
            HistoryDateFilter.today => 'Today',
            HistoryDateFilter.last7Days => 'Last 7 days',
            HistoryDateFilter.last30Days => 'Last 30 days',
          },
          values: HistoryDateFilter.values,
          valueLabel: (value) => switch (value) {
            HistoryDateFilter.allLoaded => 'All loaded',
            HistoryDateFilter.today => 'Today',
            HistoryDateFilter.last7Days => 'Last 7 days',
            HistoryDateFilter.last30Days => 'Last 30 days',
          },
          onSelected: (value) => onChanged(filters.copyWith(date: value)),
        ),
        _MenuFilter<OrderType?>(
          label: filters.orderType == null
              ? 'All types'
              : orderTypeLabel(filters.orderType!),
          values: const <OrderType?>[
            null,
            OrderType.online,
            OrderType.catering,
          ],
          valueLabel: (value) =>
              value == null ? 'All types' : orderTypeLabel(value),
          onSelected: (value) => onChanged(
            filters.copyWith(orderType: value, clearOrderType: value == null),
          ),
        ),
        _MenuFilter<FulfillmentType?>(
          label: filters.fulfillment == null
              ? 'All fulfillment'
              : fulfillmentLabel(filters.fulfillment!),
          values: const <FulfillmentType?>[
            null,
            FulfillmentType.pickup,
            FulfillmentType.delivery,
          ],
          valueLabel: (value) =>
              value == null ? 'All fulfillment' : fulfillmentLabel(value),
          onSelected: (value) => onChanged(
            filters.copyWith(
              fulfillment: value,
              clearFulfillment: value == null,
            ),
          ),
        ),
        if (showPayment)
          _MenuFilter<PaymentStatus?>(
            label: filters.payment == null
                ? 'All payments'
                : paymentStatusLabel(filters.payment!),
            values: const <PaymentStatus?>[
              null,
              PaymentStatus.paid,
              PaymentStatus.refunded,
              PaymentStatus.failed,
              PaymentStatus.unpaid,
            ],
            valueLabel: (value) =>
                value == null ? 'All payments' : paymentStatusLabel(value),
            onSelected: (value) => onChanged(
              filters.copyWith(payment: value, clearPayment: value == null),
            ),
          ),
        if (!filters.isClear)
          TextButton(onPressed: onClear, child: const Text('Clear filters')),
      ],
    ),
  );
}

class _MenuFilter<T> extends StatelessWidget {
  const _MenuFilter({
    required this.label,
    required this.values,
    required this.valueLabel,
    required this.onSelected,
  });
  final String label;
  final List<T> values;
  final String Function(T) valueLabel;
  final ValueChanged<T> onSelected;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: PopupMenuButton<T>(
      onSelected: onSelected,
      itemBuilder: (_) => values
          .map(
            (value) =>
                PopupMenuItem<T>(value: value, child: Text(valueLabel(value))),
          )
          .toList(),
      child: Chip(
        label: Text(label),
        avatar: const Icon(Icons.arrow_drop_down),
      ),
    ),
  );
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
              PelinesStateBadge(
                label: paymentStatusLabel(order.paymentStatus),
                foreground: order.paymentStatus == PaymentStatus.refunded
                    ? PelinesColors.destructive
                    : PelinesColors.textSecondary,
                background: order.paymentStatus == PaymentStatus.refunded
                    ? PelinesColors.brandPrimarySoft
                    : PelinesColors.mutedSurface,
                icon: Icons.payments_outlined,
              ),
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
