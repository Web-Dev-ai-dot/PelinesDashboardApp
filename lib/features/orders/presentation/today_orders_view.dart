import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/pelines_tokens.dart';
import '../../locations/presentation/pelines_location_selector.dart';
import '../../locations/models/location.dart';
import '../models/order_models.dart';
import '../providers/order_alerts_controller.dart';
import '../providers/orders_providers.dart';
import 'order_ui_helpers.dart';

class TodayOrdersView extends ConsumerStatefulWidget {
  const TodayOrdersView({
    required this.location,
    required this.onChangeLocation,
    super.key,
  });
  final Location location;
  final VoidCallback onChangeLocation;

  @override
  ConsumerState<TodayOrdersView> createState() => _TodayOrdersViewState();
}

class _TodayOrdersViewState extends ConsumerState<TodayOrdersView> {
  OrderStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<TodayOrdersState> asyncOrders = ref.watch(
      todayOrdersProvider,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PelinesSpacing.lg,
            PelinesSpacing.md,
            PelinesSpacing.sm,
            PelinesSpacing.xs,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Today',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: PelinesSpacing.xs),
                    PelinesLocationSelector(
                      locationName: widget.location.name,
                      onPressed: widget.onChangeLocation,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () =>
                    ref.read(todayOrdersProvider.notifier).refresh(),
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        _Filters(
          selected: _filter,
          onSelected: (OrderStatus? value) => setState(() => _filter = value),
        ),
        Expanded(
          child: asyncOrders.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object error, StackTrace stack) => _ErrorState(
              message: error.toString(),
              onRetry: () => ref.invalidate(todayOrdersProvider),
            ),
            data: (TodayOrdersState state) {
              final List<OrderSummary> visible = _filter == null
                  ? state.orders
                  : state.orders
                        .where((OrderSummary order) => order.status == _filter)
                        .toList();
              return RefreshIndicator(
                onRefresh: ref.read(todayOrdersProvider.notifier).refresh,
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
                          content: Text(
                            '${state.refreshError} Showing previous data.',
                          ),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => ref
                                  .read(todayOrdersProvider.notifier)
                                  .refresh(),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    if (visible.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyState(),
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
                              _OrderCard(order: visible[index]),
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

class _Filters extends StatelessWidget {
  const _Filters({required this.selected, required this.onSelected});
  final OrderStatus? selected;
  final ValueChanged<OrderStatus?> onSelected;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(
      horizontal: PelinesSpacing.md,
      vertical: PelinesSpacing.xs,
    ),
    child: Row(
      children: <Widget>[
        ChoiceChip(
          label: const Text('All'),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final (OrderStatus status, String label)
            in <(OrderStatus, String)>[
              (OrderStatus.pending, 'Waiting'),
              (OrderStatus.confirmed, 'Confirmed'),
              (OrderStatus.preparing, 'Preparing'),
              (OrderStatus.ready, 'Ready'),
            ]) ...<Widget>[
          const SizedBox(width: PelinesSpacing.xs),
          ChoiceChip(
            label: Text(label),
            selected: selected == status,
            onSelected: (_) => onSelected(status),
          ),
        ],
      ],
    ),
  );
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order});
  final OrderSummary order;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    margin: const EdgeInsets.only(bottom: PelinesSpacing.sm),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(PelinesRadius.prominentCard),
      boxShadow: PelinesShadows.subtle,
    ),
    child: Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PelinesRadius.prominentCard),
        side: const BorderSide(color: PelinesColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          ref.read(orderAlertsProvider.notifier).acknowledge(order.id);
          context.push('/app/orders/${order.id}');
        },
        child: Padding(
          padding: const EdgeInsets.all(PelinesSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      requestedTime(order.scheduledFor),
                      style: Theme.of(context).textTheme.titleLarge
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
                order.orderNumber,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(
                order.eventName?.isNotEmpty == true
                    ? order.eventName!
                    : order.contactName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${orderTypeLabel(order.orderType)} · ${fulfillmentLabel(order.fulfillmentType)}',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: PelinesColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    '${order.itemCount} ${order.itemCount == 1 ? 'item' : 'items'}',
                  ),
                  Text(
                    money(order.totalCents),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
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
          const SizedBox(height: PelinesSpacing.md),
          Text(
            'No active orders',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: PelinesSpacing.xs),
          Text(
            'New orders for today will appear here.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: PelinesColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
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
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
