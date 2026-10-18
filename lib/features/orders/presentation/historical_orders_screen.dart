import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'historical_orders_content.dart';
import 'historical_date_range.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_tokens.dart';

import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../models/order_models.dart';
import '../providers/orders_providers.dart';

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
  String? _locationId;
  DateTime? _from, _to;
  int _limit = 5;
  List<OrderSummary>? _source;

  @override
  void didUpdateWidget(covariant HistoricalOrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      _from = null;
      _to = null;
      _limit = 5;
      _source = null;
    }
  }

  Future<void> _range() async {
    final locationId = _locationId;
    final kind = widget.kind;
    final result = await showHistoricalDateRange(context, _from, _to);
    if (!mounted ||
        result == null ||
        _locationId != locationId ||
        widget.kind != kind ||
        ref.read(currentLocationProvider).value?.id != locationId) {
      return;
    }
    setState(() {
      _from = result.$1;
      _to = result.$2;
      _limit = 5;
    });
  }

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

    return AdminSectionScaffold(
      appBar: AdminAppBar(
        title: Text(
          title,
          style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
        ),
        actions: <Widget>[
          AdminHeaderRefresh(
            onPressed: location.value == null ? null : () => _refresh(ref),
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
            _from = null;
            _to = null;
            _limit = 5;
            _source = null;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[Expanded(child: _buildOrders(ref, orders))],
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
      if (!identical(_source, state.orders)) {
        _source = state.orders;
        _limit = 5;
      }
      final status = widget.kind == HistoricalOrdersKind.completed
          ? OrderStatus.delivered
          : OrderStatus.cancelled;
      final loaded = state.orders
          .where((o) => o.locationId == _locationId && o.status == status)
          .toList();
      final List<OrderSummary> visible = filterHistoricalDateRange(
        loaded,
        completed: widget.kind == HistoricalOrdersKind.completed,
        from: _from,
        to: _to,
      );
      final page = visible.take(_limit).toList();
      return RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: CustomScrollView(
          key: ValueKey('history-${widget.kind.name}-$_locationId'),
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OverflowBar(
                      alignment: MainAxisAlignment.spaceBetween,
                      overflowAlignment: OverflowBarAlignment.end,
                      spacing: 12,
                      overflowSpacing: 8,
                      children: [
                        Container(
                          key: const Key('history-loaded-count'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: PelinesColors.border,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '${tr(context, 'Loaded orders')}: ${visible.length}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const Key('history-date-range'),
                          onPressed: _range,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: const StadiumBorder(),
                          ),
                          icon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 18,
                          ),
                          label: Text(tr(context, 'Date range')),
                        ),
                      ],
                    ),
                    if (_from != null || _to != null)
                      Text(
                        '${_from == null ? tr(context, 'All loaded') : MaterialLocalizations.of(context).formatShortDate(_from!)} – '
                        '${_to == null ? tr(context, 'All loaded') : MaterialLocalizations.of(context).formatShortDate(_to!)}',
                      ),
                  ],
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
                          loaded.isNotEmpty
                              ? tr(
                                  context,
                                  'No loaded orders match these filters.',
                                )
                              : widget.kind == HistoricalOrdersKind.completed
                              ? tr(
                                  context,
                                  'No completed orders loaded for this location.',
                                )
                              : tr(
                                  context,
                                  'No cancelled orders loaded for this location.',
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
                    orders: page,
                    completed: widget.kind == HistoricalOrdersKind.completed,
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr(context, 'Showing {shown} of {count} loaded orders')
                          .replaceAll('{shown}', '${page.length}')
                          .replaceAll('{count}', '${visible.length}'),
                      key: const Key('history-showing-count'),
                      textAlign: TextAlign.center,
                    ),
                    if (page.length < visible.length) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        key: const Key('history-load-more'),
                        onPressed: () => setState(() => _limit += 5),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(tr(context, 'Load More')),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      tr(
                        context,
                        'History is limited to loaded orders; more may exist on the server.',
                      ),
                      style: const TextStyle(
                        color: PelinesColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
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
