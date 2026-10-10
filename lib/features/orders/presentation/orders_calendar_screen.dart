import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../models/order_models.dart';
import '../models/orders_date_filter.dart';
import 'calendar_week_selector.dart';
import '../providers/orders_providers.dart';
import 'order_preview_card.dart';
import 'calendar_month_grid.dart';
import 'upcoming_control_sheets.dart';
import '../models/upcoming_filters.dart';
import '../../../app/theme/app_theme.dart';

class OrdersCalendarScreen extends ConsumerStatefulWidget {
  const OrdersCalendarScreen({super.key});

  @override
  ConsumerState<OrdersCalendarScreen> createState() =>
      _OrdersCalendarScreenState();
}

class _OrdersCalendarScreenState extends ConsumerState<OrdersCalendarScreen> {
  late DateTime _selectedDay;
  String? _locationId;
  String _search = '';
  OrderType? _type;
  UpcomingFilters _applied = const UpcomingFilters();
  String _view = 'Today';

  bool _matches(OrderSummary order) {
    final query = _search.trim().toLowerCase();
    return (_type == null || order.orderType == _type) &&
        (_applied.status == null || order.status == _applied.status) &&
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
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Location?> location = ref.watch(currentLocationProvider);
    final AsyncValue<HistoricalOrdersState> orders = ref.watch(
      calendarOrdersProvider,
    );
    return AdminSectionScaffold(
      appBar: AdminAppBar(
        title: Text(
          tr(context, 'Calendar'),
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

  Widget _filters() => Column(
    key: const Key('calendar-filters'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PelinesInput(
        key: const Key('calendar-search'),
        variant: PelinesInputVariant.search,
        hint: tr(context, 'Search customer, event or order #'),
        onChanged: (value) => setState(() => _search = value),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const Key('calendar-sort'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: Icon(_type == null ? Icons.sort : Icons.check_circle_outline),
            label: Text(tr(context, 'Sort by')),
            onPressed: () async {
              final result = await showUpcomingSort(context, _type);
              if (mounted && result != null) {
                setState(() => _type = result.type);
              }
            },
          ),
          OutlinedButton.icon(
            key: const Key('calendar-filter-button'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: Icon(_applied.isDefault ? Icons.tune : Icons.filter_alt),
            label: Text(tr(context, 'Filters')),
            onPressed: () async {
              final result = await showCalendarFilters(context, _applied);
              if (mounted && result != null) setState(() => _applied = result);
            },
          ),
        ],
      ),
    ],
  );
  Widget _calendarBody(Location location, HistoricalOrdersState state) {
    final today = pacificDate(PelinesTime.now());
    final day = _view == 'Today' ? today : _selectedDay;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final fullDate = DateFormat.yMMMMEEEEd(locale);
    final originalGrouped = groupCalendarOrdersByPacificDay(state.orders);
    final filtered = state.orders.where(_matches).toList();
    final Map<String, List<OrderSummary>> grouped =
        groupCalendarOrdersByPacificDay(filtered);
    final selected = grouped[_localDayKey(day)] ?? const <OrderSummary>[];
    final calendar = PelinesCard(
      key: const Key('calendar-month-panel'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CalendarMonthGrid(
            selectedDay: _selectedDay,
            today: PelinesTime.now(),
            onDateChanged: (value) => setState(() => _selectedDay = value),
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
                fullDate.format(day),
                key: const Key('calendar-selected-date'),
                style: PelinesTypography.sectionTitle(
                  Theme.of(context).textTheme,
                )?.copyWith(fontSize: 24),
              ),
              const SizedBox(height: 12),
              PelinesStateBadge(
                label:
                    '${selected.length} ${tr(context, selected.length == 1 ? 'order' : 'orders')}',
                foreground: PelinesColors.brandPrimary,
                background: PelinesColors.brandPrimarySoft,
                icon: Icons.receipt_long_outlined,
              ),
            ],
          ),
        ),
        if (selected.isEmpty &&
            (originalGrouped[_localDayKey(day)]?.isNotEmpty ?? false))
          _CalendarMessage(
            compact: _view == 'Week',
            message: tr(context, 'No orders match these filters'),
          )
        else if (originalGrouped.isEmpty)
          _CalendarMessage(
            compact: _view == 'Week',
            message: tr(
              context,
              'No scheduled orders found for this location.',
            ),
          )
        else if (selected.isEmpty)
          _CalendarMessage(
            compact: _view == 'Week',
            message: tr(context, 'No orders scheduled for this day.'),
          )
        else
          for (final order in selected)
            OrderPreviewCard(order: order, planning: true, showChannel: true),
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
                  tr(
                    context,
                    'View upcoming orders by week or month to plan kitchen production and pickup flow.',
                  ),
                  style: const TextStyle(color: PelinesColors.textSecondary),
                ),
                const SizedBox(height: 12),
                _filters(),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final view in ['Today', 'Week', 'Month'])
                      ChoiceChip(
                        key: Key('calendar-view-$view'),
                        label: Text(tr(context, view)),
                        selected: _view == view,
                        selectedColor: PelinesColors.brandPrimary,
                        labelStyle: TextStyle(
                          color: _view == view
                              ? Colors.white
                              : PelinesColors.textPrimary,
                        ),
                        onSelected: (_) => setState(() => _view = view),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_view == 'Week')
                  CalendarWeekSelector(
                    selectedDay: day,
                    hasOrders: (date) =>
                        originalGrouped[_localDayKey(date)]?.isNotEmpty ??
                        false,
                    onChanged: (date) => setState(() => _selectedDay = date),
                  ),
                if (_view != 'Month')
                  agenda
                else
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
              ],
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

class _CalendarMessage extends StatelessWidget {
  const _CalendarMessage({
    required this.message,
    this.action,
    this.compact = false,
  });
  final String message;
  final VoidCallback? action;
  final bool compact;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(compact ? 16 : PelinesSpacing.xl),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (!compact)
          const Icon(
            Icons.calendar_month_outlined,
            size: 48,
            color: PelinesColors.textSecondary,
          ),
        if (!compact) const SizedBox(height: PelinesSpacing.sm),
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
