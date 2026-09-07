import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../models/order_models.dart';
import '../providers/orders_providers.dart';
import 'order_ui_helpers.dart';

class OrdersCalendarScreen extends ConsumerStatefulWidget {
  const OrdersCalendarScreen({super.key});

  @override
  ConsumerState<OrdersCalendarScreen> createState() =>
      _OrdersCalendarScreenState();
}

class _OrdersCalendarScreenState extends ConsumerState<OrdersCalendarScreen> {
  late DateTime _selectedDay;
  String? _locationId;

  @override
  void initState() {
    super.initState();
    final DateTime pacific = PelinesTime.now();
    _selectedDay = DateTime(pacific.year, pacific.month, pacific.day);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Location?> location = ref.watch(currentLocationProvider);
    final AsyncValue<HistoricalOrdersState> orders = ref.watch(
      calendarOrdersProvider,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders Calendar'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: location.value == null
                ? null
                : ref.read(calendarOrdersProvider.notifier).refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: location.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _CalendarMessage(
          message: error.toString(),
          action: () => ref.invalidate(currentLocationProvider),
        ),
        data: (Location? selected) {
          if (selected == null) {
            return const _CalendarMessage(
              message: 'Choose a location to view the calendar.',
            );
          }
          if (_locationId != selected.id) {
            _locationId = selected.id;
            final DateTime pacific = PelinesTime.now();
            _selectedDay = DateTime(pacific.year, pacific.month, pacific.day);
          }
          return orders.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => _CalendarMessage(
              message: error.toString(),
              action: () => ref.invalidate(calendarOrdersProvider),
            ),
            data: (HistoricalOrdersState state) =>
                _calendarBody(selected, state),
          );
        },
      ),
    );
  }

  Widget _calendarBody(Location location, HistoricalOrdersState state) {
    final Map<String, List<OrderSummary>> grouped =
        groupScheduledOrdersByPacificDay(state.orders);
    final List<OrderSummary> selected =
        grouped[_localDayKey(_selectedDay)] ?? const <OrderSummary>[];
    final List<OrderSummary> unscheduled = unscheduledCalendarOrders(
      state.orders,
    );
    return RefreshIndicator(
      onRefresh: ref.read(calendarOrdersProvider.notifier).refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: PelinesSpacing.xl),
        children: <Widget>[
          if (state.isRefreshing) const LinearProgressIndicator(minHeight: 2),
          if (state.refreshError != null)
            MaterialBanner(
              content: Text('${state.refreshError} Showing previous data.'),
              actions: <Widget>[
                TextButton(
                  onPressed: ref.read(calendarOrdersProvider.notifier).refresh,
                  child: const Text('Retry'),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PelinesSpacing.md,
              PelinesSpacing.sm,
              PelinesSpacing.md,
              0,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: PelinesStateBadge(
                label: location.name,
                foreground: PelinesColors.brandPrimary,
                background: PelinesColors.brandPrimarySoft,
                icon: Icons.storefront_outlined,
              ),
            ),
          ),
          CalendarDatePicker(
            initialDate: _selectedDay,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
            onDateChanged: (DateTime value) =>
                setState(() => _selectedDay = value),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PelinesSpacing.sm),
            child: PelinesSectionHeading(
              DateFormat('EEEE, MMMM d').format(_selectedDay),
            ),
          ),
          if (grouped.isEmpty)
            const _CalendarMessage(
              message: 'No scheduled orders found for this location.',
            )
          else if (selected.isEmpty)
            const _CalendarMessage(message: 'No orders scheduled for this day.')
          else
            for (final OrderSummary order in selected)
              _CalendarOrderCard(order: order),
          if (unscheduled.isNotEmpty) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: PelinesSpacing.sm,
              ),
              child: const PelinesSectionHeading('Needs pickup time'),
            ),
            for (final OrderSummary order in unscheduled)
              _CalendarOrderCard(order: order, unscheduled: true),
          ],
          if (state.orders.length == 100)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Showing the latest 100 orders available from the server.',
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

String _localDayKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

class _CalendarOrderCard extends StatelessWidget {
  const _CalendarOrderCard({required this.order, this.unscheduled = false});
  final OrderSummary order;
  final bool unscheduled;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => context.push('/app/orders/${order.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    unscheduled
                        ? order.orderNumber
                        : '${PelinesTime.formatTime(order.scheduledFor!)} · ${order.orderNumber}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                StatusChip(
                  status: order.status,
                  fulfillment: order.fulfillmentType,
                  rawStatus: order.rawStatus,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              order.eventName?.isNotEmpty == true
                  ? order.eventName!
                  : order.contactName,
            ),
            Text(
              '${orderTypeLabel(order.orderType)} · ${fulfillmentLabel(order.fulfillmentType)} · ${money(order.totalCents)}',
            ),
          ],
        ),
      ),
    ),
  );
}

class _CalendarMessage extends StatelessWidget {
  const _CalendarMessage({required this.message, this.action});
  final String message;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(PelinesSpacing.xl),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(
          Icons.calendar_month_outlined,
          size: 48,
          color: PelinesColors.textSecondary,
        ),
        const SizedBox(height: PelinesSpacing.sm),
        Text(message, textAlign: TextAlign.center),
        if (action != null) ...<Widget>[
          const SizedBox(height: 12),
          FilledButton(onPressed: action, child: const Text('Try again')),
        ],
      ],
    ),
  );
}
