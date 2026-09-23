import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../../locations/presentation/pelines_location_selector.dart';
import '../../locations/models/location.dart';
import '../models/order_models.dart';
import '../models/order_status_action.dart';
import '../models/orders_date_filter.dart';
import '../providers/order_alerts_controller.dart';
import '../providers/orders_providers.dart';
import 'order_ui_helpers.dart';
import 'order_preview_action.dart';

class TodayOrdersView extends ConsumerStatefulWidget {
  const TodayOrdersView({
    required this.location,
    required this.onChangeLocation,
    this.showLocationSelector = true,
    this.initialDateFilter = OrdersDateFilter.today,
    super.key,
  });
  final Location location;
  final VoidCallback onChangeLocation;
  final bool showLocationSelector;
  final OrdersDateFilter initialDateFilter;

  @override
  ConsumerState<TodayOrdersView> createState() => TodayOrdersViewState();
}

class TodayOrdersViewState extends ConsumerState<TodayOrdersView> {
  OrderStatus? _filter = OrderStatus.confirmed;
  late OrdersDateFilter _date = widget.initialDateFilter;
  DateTime? _chosenDate;
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant TodayOrdersView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Shell shortcuts reuse the existing filter; polling and local choices do
    // not reset it. No fetching or filtering logic is duplicated here.
    if (oldWidget.initialDateFilter != widget.initialDateFilter) {
      _date = widget.initialDateFilter;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _selectDate(OrdersDateFilter value) async {
    if (value == OrdersDateFilter.chooseDate) {
      final now = PelinesTime.now();
      final selected = await showDatePicker(
        context: context,
        initialDate: _chosenDate ?? DateTime(now.year, now.month, now.day),
        currentDate: DateTime(now.year, now.month, now.day),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100, 12, 31),
      );
      if (selected == null || !mounted) return;
      _chosenDate = selected;
    }
    if (mounted) setState(() => _date = value);
  }

  Future<void> refresh() => _date == OrdersDateFilter.today
      ? ref.read(todayOrdersProvider.notifier).refresh()
      : ref.read(calendarOrdersProvider.notifier).refresh();

  void _retry() {
    if (_date == OrdersDateFilter.today) {
      ref.invalidate(todayOrdersProvider);
    } else {
      ref.invalidate(calendarOrdersProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayOrdersProvider);
    final AsyncValue<TodayOrdersState> asyncOrders =
        _date == OrdersDateFilter.today
        ? today
        : ref.watch(calendarOrdersProvider).whenData((state) {
            final orders = filterOrdersByDate(
              state.orders,
              _date,
              chosenDate: _chosenDate,
            )..sort(compareOperationalOrders);
            return TodayOrdersState(
              orders: orders,
              isRefreshing: state.isRefreshing,
              refreshError: state.refreshError,
            );
          });
    // Change the view only after an explicit Accept has reconciled successfully.
    // Polling and remote status changes never reset the selected filter.
    for (final order in asyncOrders.value?.orders ?? <OrderSummary>[]) {
      if (order.status != OrderStatus.pending ||
          order.locationId != widget.location.id) {
        continue;
      }
      ref.listen(orderMutationProvider(order.id), (previous, next) {
        if (_filter == OrderStatus.pending &&
            next.phase == OrderMutationPhase.success &&
            next.action == OrderStatusAction.acceptOrder &&
            next.canonicalOrder?.status == OrderStatus.confirmed) {
          setState(() => _filter = OrderStatus.confirmed);
        }
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PelinesSpacing.md,
            vertical: PelinesSpacing.sm,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final dateSelector = PopupMenuButton<OrdersDateFilter>(
                key: const Key('orders-date-selector'),
                tooltip: tr(context, 'Choose order date'),
                initialValue: _date,
                onSelected: _selectDate,
                itemBuilder: (_) => [
                  for (final value in OrdersDateFilter.values)
                    PopupMenuItem(value: value, child: Text(value.label)),
                ],
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.all(PelinesSpacing.xs),
                  decoration: BoxDecoration(
                    border: Border.all(color: PelinesColors.border),
                    borderRadius: BorderRadius.circular(PelinesRadius.control),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_outlined),
                      const SizedBox(width: PelinesSpacing.xs),
                      Flexible(
                        child: Text(
                          _date == OrdersDateFilter.chooseDate
                              ? DateFormat.yMMMd().format(_chosenDate!)
                              : _date.label,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const Icon(Icons.expand_more),
                    ],
                  ),
                ),
              );
              if (!widget.showLocationSelector) {
                return Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: dateSelector,
                );
              }
              final locationSelector = PelinesLocationSelector(
                locationName: widget.location.name,
                onPressed: widget.onChangeLocation,
              );
              final narrow =
                  constraints.maxWidth < 330 ||
                  (constraints.maxWidth < 600 &&
                      MediaQuery.textScalerOf(context).scale(1) > 1.5);
              return narrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        dateSelector,
                        const SizedBox(height: PelinesSpacing.xs),
                        locationSelector,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: dateSelector),
                        const SizedBox(width: PelinesSpacing.sm),
                        Expanded(child: locationSelector),
                      ],
                    );
            },
          ),
        ),
        if (_date != OrdersDateFilter.today)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PelinesSpacing.lg),
            child: Text(
              _date == OrdersDateFilter.upcoming
                  ? tr(
                      context,
                      'From tomorrow · Pacific time · Available orders only',
                    )
                  : tr(
                      context,
                      'Pacific time · Available orders only; not a complete history',
                    ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        _Filters(
          selected: _filter,
          waitingCount:
              asyncOrders.value?.orders
                  .where(
                    (order) =>
                        order.status == OrderStatus.pending &&
                        order.locationId == widget.location.id &&
                        order.paymentStatus.isOperationallyPaid,
                  )
                  .length ??
              0,
          onSelected: (OrderStatus? value) => setState(() => _filter = value),
        ),
        Expanded(
          child: asyncOrders.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object error, StackTrace stack) =>
                _ErrorState(message: error.toString(), onRetry: _retry),
            data: (TodayOrdersState state) {
              final List<OrderSummary> visible = _filter == null
                  ? state.orders
                  : state.orders
                        .where((OrderSummary order) => order.status == _filter)
                        .toList();
              return RefreshIndicator(
                onRefresh: refresh,
                child: CustomScrollView(
                  controller: _scroll,
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
                              onPressed: refresh,
                              child: Text(tr(context, 'Retry')),
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
  const _Filters({
    required this.selected,
    required this.onSelected,
    required this.waitingCount,
  });
  final int waitingCount;
  final OrderStatus? selected;
  final ValueChanged<OrderStatus?> onSelected;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: PelinesSpacing.md,
      vertical: PelinesSpacing.xs,
    ),
    child: Row(
      children: <Widget>[
        ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr(context, 'Waiting')),
              if (waitingCount > 0) ...[
                const SizedBox(width: PelinesSpacing.xs),
                Semantics(
                  label: '$waitingCount pending orders',
                  child: Badge(
                    key: const Key('waiting-count'),
                    label: Text('$waitingCount'),
                  ),
                ),
              ],
            ],
          ),
          selected: selected == OrderStatus.pending,
          onSelected: (_) => onSelected(OrderStatus.pending),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final (OrderStatus status, String label)
                    in <(OrderStatus, String)>[
                      (OrderStatus.confirmed, tr(context, 'Confirmed')),
                      (OrderStatus.preparing, tr(context, 'Preparing')),
                      (OrderStatus.ready, tr(context, 'Ready')),
                    ]) ...<Widget>[
                  const SizedBox(width: PelinesSpacing.xs),
                  ChoiceChip(
                    label: Text(label),
                    selected: selected == status,
                    onSelected: (_) => onSelected(status),
                  ),
                ],
                const SizedBox(width: PelinesSpacing.xs),
                ChoiceChip(
                  label: Text(tr(context, 'All')),
                  selected: selected == null,
                  onSelected: (_) => onSelected(null),
                ),
              ],
            ),
          ),
        ),
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
              const SizedBox(height: PelinesSpacing.sm),
              OrderPreviewAction(key: ValueKey(order.id), order: order),
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
            tr(context, 'No active orders'),
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: PelinesSpacing.xs),
          Text(
            tr(context, 'No active orders match the selected date and status.'),
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
          FilledButton(
            onPressed: onRetry,
            child: Text(tr(context, 'Try again')),
          ),
        ],
      ),
    ),
  );
}
