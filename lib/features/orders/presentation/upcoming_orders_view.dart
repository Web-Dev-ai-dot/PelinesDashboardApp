import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../models/order_models.dart';
import '../providers/orders_providers.dart';
import 'order_preview_card.dart';
import 'order_ui_helpers.dart';

/// Presentation over the already loaded operational dataset. Search/type never
/// fetch data, alter date defaults or participate in mutation reconciliation.
class UpcomingOrdersView extends StatefulWidget {
  const UpcomingOrdersView({
    required this.orders,
    required this.status,
    required this.dateControl,
    required this.statusFilters,
    required this.dateContext,
    required this.onRefresh,
    required this.onRetry,
    super.key,
  });
  final AsyncValue<TodayOrdersState> orders;
  final OrderStatus? status;
  final Widget dateControl, statusFilters;
  final String? dateContext;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  @override
  State<UpcomingOrdersView> createState() => _UpcomingOrdersViewState();
}

class _UpcomingOrdersViewState extends State<UpcomingOrdersView> {
  final _search = TextEditingController();
  OrderType? _type;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = math.max(
        1.0,
        MediaQuery.textScalerOf(context).scale(14) / 14,
      );
      final board = constraints.maxWidth >= 1000 * scale;
      final columns = constraints.maxWidth >= 720 * scale ? 2 : 1;
      final query = _search.text.trim().toLowerCase();
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: CustomScrollView(
          key: const Key('upcoming-orders-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              sliver: SliverToBoxAdapter(
                child: PelinesFilterBar(
                  search: PelinesInput(
                    key: const Key('orders-search'),
                    controller: _search,
                    variant: PelinesInputVariant.search,
                    label: tr(context, 'Search orders'),
                    onChanged: (_) => setState(() {}),
                  ),
                  filters: [
                    widget.dateControl,
                    PelinesSelect<OrderType>(
                      key: const Key('orders-type-filter'),
                      value: _type,
                      label: tr(context, 'Order type'),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(tr(context, 'All types')),
                        ),
                        for (final type in OrderType.values)
                          DropdownMenuItem(
                            value: type,
                            child: Text(tr(context, orderTypeLabel(type))),
                          ),
                      ],
                      onChanged: (value) => setState(() => _type = value),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.dateContext != null)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    widget.dateContext!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            SliverToBoxAdapter(child: widget.statusFilters),
            ...widget.orders.when(
              loading: () => [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ],
              error: (error, _) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(error.toString()),
                        const SizedBox(height: 12),
                        PelinesButton(
                          label: tr(context, 'Try again'),
                          onPressed: widget.onRetry,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              data: (state) {
                final visible = state.orders
                    .where(
                      (order) =>
                          (widget.status == null ||
                              order.status == widget.status) &&
                          (_type == null || order.orderType == _type) &&
                          (query.isEmpty ||
                              [
                                order.orderNumber,
                                order.id,
                                order.contactName,
                                order.eventName ?? '',
                                tr(context, orderTypeLabel(order.orderType)),
                              ].join(' ').toLowerCase().contains(query)),
                    )
                    .toList();
                return <Widget>[
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
                        actions: [
                          TextButton(
                            onPressed: widget.onRefresh,
                            child: Text(tr(context, 'Retry')),
                          ),
                        ],
                      ),
                    ),
                  if (board)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: math.max(480, constraints.maxHeight * .8),
                        child: _OrdersBoard(orders: visible),
                      ),
                    )
                  else if (visible.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          tr(context, 'No orders match these filters.'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverList.builder(
                        key: Key('upcoming-cards-$columns'),
                        itemCount: (visible.length / columns).ceil(),
                        itemBuilder: (context, row) => Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var col = 0; col < columns; col++) ...[
                              if (col > 0) const SizedBox(width: 16),
                              Expanded(
                                child: row * columns + col < visible.length
                                    ? OrderPreviewCard(
                                        key: ValueKey(
                                          visible[row * columns + col].id,
                                        ),
                                        order: visible[row * columns + col],
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ];
              },
            ),
          ],
        ),
      );
    },
  );
}

class _OrdersBoard extends StatefulWidget {
  const _OrdersBoard({required this.orders});
  final List<OrderSummary> orders;
  @override
  State<_OrdersBoard> createState() => _OrdersBoardState();
}

class _OrdersBoardState extends State<_OrdersBoard> {
  final _horizontal = ScrollController();
  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const active = [
      OrderStatus.pending,
      OrderStatus.confirmed,
      OrderStatus.preparing,
      OrderStatus.ready,
    ];
    final statuses = [
      ...active,
      ...OrderStatus.values.where(
        (s) => !active.contains(s) && widget.orders.any((o) => o.status == s),
      ),
    ];
    return Scrollbar(
      controller: _horizontal,
      thumbVisibility: true,
      child: ListView.separated(
        key: const Key('orders-board'),
        controller: _horizontal,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: statuses.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final status = statuses[index];
          final orders = widget.orders
              .where((o) => o.status == status)
              .toList();
          final accent = switch (status) {
            OrderStatus.pending => PelinesColors.amberForeground,
            OrderStatus.confirmed => PelinesColors.successForeground,
            OrderStatus.preparing => PelinesColors.preparing,
            OrderStatus.ready => PelinesColors.brandPrimary,
            _ => PelinesColors.textSecondary,
          };
          return Container(
            key: Key('orders-column-${status.name}'),
            width: 320,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .06),
              border: Border.all(
                color: accent.withValues(alpha: .25),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr(
                          context,
                          statusLabel(
                            status,
                            FulfillmentType.delivery,
                            status.name,
                          ),
                        ).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Badge(
                      backgroundColor: PelinesColors.card,
                      textColor: PelinesColors.textPrimary,
                      label: Text('${orders.length}'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: orders.isEmpty
                      ? Text(
                          tr(context, 'No orders in this status.'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: PelinesColors.textSecondary,
                          ),
                        )
                      : ListView.builder(
                          primary: false,
                          itemCount: orders.length,
                          itemBuilder: (_, i) => OrderPreviewCard(
                            key: ValueKey(orders[i].id),
                            order: orders[i],
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
