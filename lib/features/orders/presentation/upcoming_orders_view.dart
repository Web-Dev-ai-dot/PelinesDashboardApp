import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_components.dart';
import '../models/order_models.dart';
import '../models/orders_date_filter.dart';
import '../models/upcoming_filters.dart';
import '../../../core/time/pelines_time.dart';
import 'upcoming_control_sheets.dart';
import '../providers/orders_providers.dart';
import 'order_ui_helpers.dart';
import 'todo_status_board.dart';

/// Local controls over the existing Pacific Upcoming snapshot. Board, cards,
/// printing and mutations are the same components used by To-Do.
class UpcomingOrdersView extends StatefulWidget {
  const UpcomingOrdersView({
    required this.orders,
    this.initialDateFilter = OrdersDateFilter.upcoming,
    required this.onRefresh,
    required this.onRetry,
    super.key,
  });
  final AsyncValue<TodayOrdersState> orders;
  final OrdersDateFilter initialDateFilter;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  @override
  State<UpcomingOrdersView> createState() => _UpcomingOrdersViewState();
}

class _UpcomingOrdersViewState extends State<UpcomingOrdersView> {
  final _search = TextEditingController();
  OrderType? _type;
  late UpcomingFilters _filters = _initialFilters();

  UpcomingFilters _initialFilters() {
    if (widget.initialDateFilter == OrdersDateFilter.tomorrow) {
      final today = pacificDate(PelinesTime.now());
      final tomorrow = DateTime.utc(today.year, today.month, today.day + 1);
      return UpcomingFilters(from: tomorrow, to: tomorrow);
    }
    return const UpcomingFilters();
  }

  @override
  void didUpdateWidget(covariant UpcomingOrdersView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDateFilter != widget.initialDateFilter) {
      _filters = _initialFilters();
    }
  }

  Future<void> _sort() async {
    final result = await showUpcomingSort(context, _type, polished: true);
    if (result != null && mounted && result.type != _type) {
      setState(() => _type = result.type);
    }
  }

  Future<void> _filter() async {
    final result = await showUpcomingFilters(context, _filters);
    if (result != null &&
        mounted &&
        (result.from != _filters.from ||
            result.to != _filters.to ||
            result.status != _filters.status)) {
      setState(() => _filters = result);
    }
  }

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PelinesInput(
                      key: const Key('orders-search'),
                      controller: _search,
                      variant: PelinesInputVariant.search,
                      hint: tr(context, 'Search customer, event or order #'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, controls) {
                        final buttons = <Widget>[
                          OutlinedButton.icon(
                            key: const Key('upcoming-sort'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              shape: const StadiumBorder(),
                            ),
                            onPressed: _sort,
                            icon: Icon(
                              _type == null
                                  ? Icons.sort
                                  : Icons.check_circle_outline,
                            ),
                            label: Text(tr(context, 'Sort by')),
                          ),
                          OutlinedButton.icon(
                            key: const Key('upcoming-filters'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              shape: const StadiumBorder(),
                            ),
                            onPressed: _filter,
                            icon: Icon(
                              _filters.isDefault
                                  ? Icons.tune
                                  : Icons.filter_alt,
                            ),
                            label: Text(tr(context, 'Filters')),
                          ),
                        ];
                        final scale =
                            MediaQuery.textScalerOf(context).scale(14) / 14;
                        final paired = controls.maxWidth >= 320 * scale;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            for (final button in buttons)
                              SizedBox(
                                width: paired
                                    ? (controls.maxWidth - 12) / 2
                                    : controls.maxWidth,
                                child: button,
                              ),
                          ],
                        );
                      },
                    ),
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
                              _filters.matches(order) &&
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
