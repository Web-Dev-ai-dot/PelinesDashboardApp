import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
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
import 'order_preview_action.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_order_badges.dart';

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
  String _search = '';
  String _type = 'all';
  String _status = 'all';

  bool _matches(OrderSummary order) {
    final query = _search.trim().toLowerCase();
    return (_type == 'all' || order.orderType.name == _type) &&
        (_status == 'all' || order.status.name == _status) &&
        (query.isEmpty ||
            [
              order.contactName,
              order.orderNumber,
              order.eventName ?? '',
              order.id,
            ].any((text) => text.toLowerCase().contains(query)));
  }

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
        title: Text(
          tr(context, 'Orders Calendar'),
          style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: tr(context, 'Refresh'),
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
            return _CalendarMessage(
              message: tr(context, 'Choose a location to view the calendar.'),
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

  Widget _filters() => PelinesCard(
    key: const Key('calendar-filters'),
    padding: const EdgeInsets.all(16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final controls = <Widget>[
          PelinesInput(
            key: const Key('calendar-search'),
            variant: PelinesInputVariant.search,
            hint: tr(context, 'Search customer, event or order'),
            onChanged: (value) => setState(() => _search = value),
          ),
          PelinesSelect<String>(
            key: const Key('calendar-type'),
            value: _type,
            items: [
              for (final entry in {
                'all': 'All Types',
                'online': 'Regular',
                'catering': 'Catering',
              }.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(tr(context, entry.value)),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _type = value);
              }
            },
          ),
          PelinesSelect<String>(
            key: const Key('calendar-status'),
            value: _status,
            // calendarRelevantOrders admits only these operational states.
            items: [
              for (final entry in {
                'all': 'All Statuses',
                'pending': 'Waiting',
                'confirmed': 'Confirmed',
                'preparing': 'Preparing',
                'ready': 'Ready',
              }.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(tr(context, entry.value)),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _status = value);
              }
            },
          ),
        ];
        if (constraints.maxWidth >=
            900 * MediaQuery.textScalerOf(context).scale(1)) {
          return Row(
            children: [
              Expanded(flex: 2, child: controls[0]),
              const SizedBox(width: 16),
              Expanded(child: controls[1]),
              const SizedBox(width: 16),
              Expanded(child: controls[2]),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            controls[0],
            const SizedBox(height: 12),
            controls[1],
            const SizedBox(height: 12),
            controls[2],
          ],
        );
      },
    ),
  );
  Widget _calendarBody(Location location, HistoricalOrdersState state) {
    final originalGrouped = groupScheduledOrdersByPacificDay(state.orders);
    final filtered = state.orders.where(_matches).toList();
    final Map<String, List<OrderSummary>> grouped =
        groupScheduledOrdersByPacificDay(filtered);
    final List<OrderSummary> selected =
        grouped[_localDayKey(_selectedDay)] ?? const <OrderSummary>[];
    final List<OrderSummary> unscheduled = unscheduledCalendarOrders(filtered);
    final calendar = PelinesCard(
      key: const Key('calendar-month-panel'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _monthControl(
                  label: 'Month',
                  value: _displayedMonth.month,
                  values: List.generate(12, (i) => i + 1),
                  text: (month) => tr(
                    context,
                    DateFormat.MMMM().format(DateTime(2024, month)),
                  ),
                  onChanged: (month) =>
                      _jumpToMonth(_displayedMonth.year, month),
                  width: 200,
                ),
                _monthControl(
                  label: 'Year',
                  value: _displayedMonth.year,
                  values: List.generate(81, (i) => i + 2020),
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
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              tr(context, 'Pacific time'),
              style: PelinesTypography.smallLabel,
            ),
          ),
        ],
      ),
    );
    final agenda = Column(
      key: const Key('calendar-day-agenda'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PelinesCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                MaterialLocalizations.of(context).formatFullDate(_selectedDay),
                key: const Key('calendar-selected-date'),
                style: PelinesTypography.sectionTitle(
                  Theme.of(context).textTheme,
                )?.copyWith(fontSize: 24),
              ),
              const SizedBox(height: 12),
              PelinesStateBadge(
                label: '${selected.length} ${tr(context, 'orders')}',
                foreground: PelinesColors.brandPrimary,
                background: PelinesColors.brandPrimarySoft,
                icon: Icons.receipt_long_outlined,
              ),
            ],
          ),
        ),
        if ((selected.isEmpty &&
                (originalGrouped[_localDayKey(_selectedDay)]?.isNotEmpty ??
                    false)) ||
            (originalGrouped.isEmpty &&
                unscheduled.isEmpty &&
                unscheduledCalendarOrders(state.orders).isNotEmpty))
          _CalendarMessage(
            message: tr(context, 'No orders match these filters'),
          )
        else if (originalGrouped.isEmpty)
          _CalendarMessage(
            message: tr(
              context,
              'No scheduled orders found for this location.',
            ),
          )
        else if (selected.isEmpty)
          _CalendarMessage(
            message: tr(context, 'No orders scheduled for this day.'),
          )
        else
          for (final order in selected) _CalendarOrderCard(order: order),
        if (unscheduled.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              tr(context, 'Needs pickup time'),
              style: PelinesTypography.sectionTitle(
                Theme.of(context).textTheme,
              ),
            ),
          ),
          for (final order in unscheduled)
            _CalendarOrderCard(order: order, unscheduled: true),
        ],
      ],
    );
    return RefreshIndicator(
      onRefresh: ref.read(calendarOrdersProvider.notifier).refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (state.isRefreshing) const LinearProgressIndicator(minHeight: 2),
          if (state.refreshError != null)
            MaterialBanner(
              content: Text(
                '${state.refreshError} ${tr(context, 'Showing previous data.')}',
              ),
              actions: [
                TextButton(
                  onPressed: ref.read(calendarOrdersProvider.notifier).refresh,
                  child: Text(tr(context, 'Retry')),
                ),
              ],
            ),
          PelinesPageBody(
            width: PelinesPageWidth.dashboard,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(context, 'Plan scheduled orders by Pacific date.'),
                  style: const TextStyle(color: PelinesColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: PelinesStateBadge(
                    label: location.name,
                    foreground: PelinesColors.brandPrimary,
                    background: PelinesColors.brandPrimarySoft,
                    icon: Icons.storefront_outlined,
                  ),
                ),
                const SizedBox(height: 24),
                _filters(),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide =
                        constraints.maxWidth >=
                        1000 * MediaQuery.textScalerOf(context).scale(1);
                    return wide
                        ? Row(
                            key: const Key('calendar-wide-layout'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 440, child: calendar),
                              const SizedBox(width: 24),
                              Expanded(child: agenda),
                            ],
                          )
                        : Column(
                            key: const Key('calendar-stacked-layout'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 520,
                                  ),
                                  child: calendar,
                                ),
                              ),
                              const SizedBox(height: 24),
                              agenda,
                            ],
                          );
                  },
                ),
                if (state.orders.length == 100)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      tr(
                        context,
                        'Showing the latest 100 orders available from the server.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
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
      decoration: PelinesControlStyles.input(label: tr(context, label)),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: PelinesCard(
      variant: PelinesCardVariant.compact,
      child: InkWell(
        onTap: () => context.push('/app/orders/${order.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              unscheduled
                  ? tr(context, 'Needs pickup time')
                  : PelinesTime.formatTime(order.scheduledFor!),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(order.orderNumber, style: PelinesTypography.smallLabel),
            const SizedBox(height: 12),
            Text(
              order.contactName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            if (order.eventName?.isNotEmpty == true)
              Text(
                order.eventName!,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PelinesOrderBadges.status(
                  status: order.status,
                  label: tr(
                    context,
                    statusLabel(
                      order.status,
                      order.fulfillmentType,
                      order.rawStatus,
                    ),
                  ),
                ),
                PelinesOrderBadges.type(
                  type: order.orderType,
                  label: tr(context, orderTypeLabel(order.orderType)),
                ),
                PelinesOrderBadges.fulfillment(
                  fulfillment: order.fulfillmentType,
                  label: tr(context, fulfillmentLabel(order.fulfillmentType)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              money(order.totalCents),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            OrderPreviewAction(
              key: ValueKey(order.id),
              order: order,
              webStyle: true,
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
          FilledButton(
            onPressed: action,
            child: Text(tr(context, 'Try again')),
          ),
        ],
      ],
    ),
  );
}
