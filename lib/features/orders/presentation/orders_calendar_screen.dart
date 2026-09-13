import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../models/order_models.dart';
import '../models/orders_date_filter.dart';
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
  late DateTime _displayedMonth;
  int _pickerRevision = 0;
  String? _locationId;

  @override
  void initState() {
    super.initState();
    final DateTime pacific = PelinesTime.now();
    _selectedDay = DateTime(pacific.year, pacific.month, pacific.day);
    _displayedMonth = DateTime(pacific.year, pacific.month);
  }

  void _jumpToMonth(int year, int month) {
    setState(() {
      _selectedDay = dayInMonth(_selectedDay, year, month);
      _displayedMonth = DateTime(year, month);
      // CalendarDatePicker only consumes initialDate when its State is created.
      // Recreate it for explicit jumps, never for swipe or ordinary rebuilds.
      _pickerRevision++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Location?> location = ref.watch(currentLocationProvider);
    final AsyncValue<HistoricalOrdersState> orders = ref.watch(
      calendarOrdersProvider,
    );
    return Scaffold(
      appBar: AdminAppBar(
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
            _displayedMonth = DateTime(pacific.year, pacific.month);
            _pickerRevision++;
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
          Padding(
            padding: const EdgeInsets.all(PelinesSpacing.md),
            child: Wrap(
              spacing: PelinesSpacing.sm,
              runSpacing: PelinesSpacing.sm,
              children: [
                _monthControl(
                  label: 'Month',
                  value: _displayedMonth.month,
                  values: List.generate(12, (index) => index + 1),
                  text: (month) =>
                      DateFormat.MMMM().format(DateTime(2024, month)),
                  onChanged: (month) =>
                      _jumpToMonth(_displayedMonth.year, month),
                  width: 200,
                ),
                _monthControl(
                  label: 'Year',
                  value: _displayedMonth.year,
                  values: List.generate(81, (index) => index + 2020),
                  text: (year) => '$year',
                  onChanged: (year) =>
                      _jumpToMonth(year, _displayedMonth.month),
                  width: 132,
                ),
              ],
            ),
          ),
          CalendarDatePicker(
            key: ValueKey('calendar-picker-$_pickerRevision'),
            initialDate: _selectedDay,
            currentDate: PelinesTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100, 12, 31),
            onDisplayedMonthChanged: (value) => setState(
              () => _displayedMonth = DateTime(value.year, value.month),
            ),
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

  Widget _monthControl({
    required String label,
    required int value,
    required List<int> values,
    required String Function(int) text,
    required ValueChanged<int> onChanged,
    required double width,
  }) => SizedBox(
    width: width,
    child: DropdownButtonFormField<int>(
      key: ValueKey('calendar-$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: PelinesSpacing.sm,
          vertical: PelinesSpacing.sm,
        ),
      ),
      items: [
        for (final option in values)
          DropdownMenuItem(
            value: option,
            child: Text(
              text(option),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    ),
  );
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
