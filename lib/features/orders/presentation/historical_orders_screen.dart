import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'historical_orders_content.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_tokens.dart';

import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../../locations/presentation/pelines_location_context.dart';
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
        ? tr(context, 'Completed Orders')
        : tr(context, 'Cancelled Orders');

    return Scaffold(
      appBar: AdminAppBar(
        title: Text(
          title,
          style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: tr(context, 'Refresh'),
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
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(tr(context, 'Choose a location to view orders.')),
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
                child: const SectionLocationContext(),
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Text(
                  tr(
                    context,
                    widget.kind == HistoricalOrdersKind.completed
                        ? 'Picked up or delivered orders. Filtered by completion date, with operational date as fallback.'
                        : 'Cancelled orders. Filtered by scheduled time or placed date; payment status is shown separately.',
                  ),
                  style: const TextStyle(color: PelinesColors.textSecondary),
                ),
              ),
            ),
            if (state.isRefreshing)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (state.refreshError != null)
              SliverToBoxAdapter(
                child: MaterialBanner(
                  content: Text(
                    '${state.refreshError} ${tr(context, 'Showing previous data.')}',
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => _refresh(ref),
                      child: Text(tr(context, 'Retry')),
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
                              ? tr(context, 'No orders match these filters.')
                              : widget.kind == HistoricalOrdersKind.completed
                              ? tr(
                                  context,
                                  'No completed orders for this location.',
                                )
                              : tr(
                                  context,
                                  'No cancelled orders for this location.',
                                ),
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
                sliver: SliverToBoxAdapter(
                  child: HistoricalOrdersContent(
                    orders: visible,
                    completed: widget.kind == HistoricalOrdersKind.completed,
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
            HistoryDateFilter.allLoaded => tr(context, 'All loaded'),
            HistoryDateFilter.today => tr(context, 'Today'),
            HistoryDateFilter.last7Days => tr(context, 'Last 7 days'),
            HistoryDateFilter.last30Days => tr(context, 'Last 30 days'),
          },
          values: HistoryDateFilter.values,
          valueLabel: (value) => switch (value) {
            HistoryDateFilter.allLoaded => tr(context, 'All loaded'),
            HistoryDateFilter.today => tr(context, 'Today'),
            HistoryDateFilter.last7Days => tr(context, 'Last 7 days'),
            HistoryDateFilter.last30Days => tr(context, 'Last 30 days'),
          },
          onSelected: (value) => onChanged(filters.copyWith(date: value)),
        ),
        _MenuFilter<OrderType?>(
          label: filters.orderType == null
              ? tr(context, 'All types')
              : tr(context, orderTypeLabel(filters.orderType!)),
          values: const <OrderType?>[
            null,
            OrderType.online,
            OrderType.catering,
          ],
          valueLabel: (value) => value == null
              ? tr(context, 'All types')
              : tr(context, orderTypeLabel(value)),
          onSelected: (value) => onChanged(
            filters.copyWith(orderType: value, clearOrderType: value == null),
          ),
        ),
        _MenuFilter<FulfillmentType?>(
          label: filters.fulfillment == null
              ? tr(context, 'All fulfillment')
              : tr(context, fulfillmentLabel(filters.fulfillment!)),
          values: const <FulfillmentType?>[
            null,
            FulfillmentType.pickup,
            FulfillmentType.delivery,
          ],
          valueLabel: (value) => value == null
              ? tr(context, 'All fulfillment')
              : tr(context, fulfillmentLabel(value)),
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
                ? tr(context, 'All payments')
                : tr(context, paymentStatusLabel(filters.payment!)),
            values: const <PaymentStatus?>[
              null,
              PaymentStatus.paid,
              PaymentStatus.refunded,
              PaymentStatus.failed,
              PaymentStatus.unpaid,
            ],
            valueLabel: (value) => value == null
                ? tr(context, 'All payments')
                : tr(context, paymentStatusLabel(value)),
            onSelected: (value) => onChanged(
              filters.copyWith(payment: value, clearPayment: value == null),
            ),
          ),
        if (!filters.isClear)
          TextButton(
            onPressed: onClear,
            child: Text(tr(context, 'Clear filters')),
          ),
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
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: PelinesColors.card,
          border: Border.all(color: PelinesColors.border),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    ),
  );
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
          FilledButton(
            onPressed: onRetry,
            child: Text(tr(context, 'Try again')),
          ),
        ],
      ),
    ),
  );
}
