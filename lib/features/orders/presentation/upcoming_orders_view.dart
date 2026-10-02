import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_components.dart';
import '../models/order_models.dart';
import '../providers/orders_providers.dart';
import 'order_ui_helpers.dart';
import 'todo_status_board.dart';

/// Local controls over the existing Pacific Upcoming snapshot. Board, cards,
/// printing and mutations are the same components used by To-Do.
class UpcomingOrdersView extends StatefulWidget {
  const UpcomingOrdersView({
    required this.orders,
    required this.dateControl,
    required this.dateContext,
    required this.onRefresh,
    required this.onRetry,
    required this.onReset,
    super.key,
  });
  final AsyncValue<TodayOrdersState> orders;
  final Widget dateControl;
  final String? dateContext;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry, onReset;
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
      final query = _search.text.trim().toLowerCase();
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: CustomScrollView(
          key: const PageStorageKey('upcoming-orders-scroll'),
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
                    label: tr(context, 'Search customer, event or order #'),
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
                    TextButton.icon(
                      key: const Key('upcoming-reset'),
                      onPressed: () {
                        setState(() {
                          _search.clear();
                          _type = null;
                        });
                        widget.onReset();
                      },
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: Text(tr(context, 'Clear filters')),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Existing Upcoming has only this operational comparator.
                    Tooltip(
                      message: tr(
                        context,
                        'Scheduled orders first, earliest first.',
                      ),
                      child: Text(
                        tr(context, 'Sort by: Fulfillment time'),
                        key: const Key('upcoming-sort'),
                      ),
                    ),
                    if (widget.dateContext != null)
                      Text(
                        widget.dateContext!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            ...widget.orders.when(
              loading: () => [
                const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (error, _) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(error.toString()),
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
                final visible =
                    state.orders
                        .where(
                          (order) =>
                              (_type == null || order.orderType == _type) &&
                              (query.isEmpty ||
                                  [
                                    order.orderNumber,
                                    order.id,
                                    order.contactName,
                                    order.eventName ?? '',
                                    tr(
                                      context,
                                      orderTypeLabel(order.orderType),
                                    ),
                                  ].join(' ').toLowerCase().contains(query)),
                        )
                        .toList()
                      ..sort(compareOperationalOrders);
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
                  SliverToBoxAdapter(
                    key: const ValueKey('upcoming-board'),
                    child: SizedBox(
                      height: math.max(480, constraints.maxHeight * .8),
                      child: TodoStatusBoard(
                        orders: visible,
                        showChannel: true,
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
