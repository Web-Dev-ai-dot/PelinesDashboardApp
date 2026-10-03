import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/history_filters.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/models/orders_date_filter.dart';
import 'package:pelines_admin_app/features/orders/presentation/orders_calendar_screen.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

import 'order_test_data.dart';
import 'calendar_test_helpers.dart';

import 'package:pelines_admin_app/features/orders/presentation/calendar_month_grid.dart';
import 'package:pelines_admin_app/features/orders/presentation/calendar_week_selector.dart';

import 'upcoming_sheet_helpers.dart';

void main() {
  for (final width in [390.0, 768.0]) {
    testWidgets('Calendar controls fit at $width with enlarged text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentLocationProvider.overrideWith(_CurrentLocation.new),
            ordersRepositoryProvider.overrideWithValue(_Repository()),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const OrdersCalendarScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await upcomingTap(tester, 'calendar-view-Month');
      expect(find.byType(DropdownButtonFormField<int>), findsNWidgets(2));
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'direct month selection clamps day for leap years and year boundaries',
    () {
      expect(dayInMonth(DateTime(2024, 1, 31), 2024, 2), DateTime(2024, 2, 29));
      expect(dayInMonth(DateTime(2024, 2, 29), 2025, 2), DateTime(2025, 2, 28));
      expect(
        dayInMonth(DateTime(2026, 12, 31), 2027, 1),
        DateTime(2027, 1, 31),
      );
      expect(
        dayInMonth(DateTime(2027, 1, 31), 2026, 12),
        DateTime(2026, 12, 31),
      );
    },
  );

  testWidgets(
    'Calendar Month Year dropdowns alone update grid and clamp selected day',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(768, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentLocationProvider.overrideWith(_CurrentLocation.new),
            ordersRepositoryProvider.overrideWithValue(_Repository()),
          ],
          child: const MaterialApp(home: OrdersCalendarScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await upcomingTap(tester, 'calendar-view-Month');
      final picker = find.byType(CalendarMonthGrid);
      expect(picker, findsOneWidget);
      expect(find.byType(DropdownButtonFormField<int>), findsNWidgets(2));
      final loc = MaterialLocalizations.of(tester.element(picker));
      expect(find.byType(CalendarDatePicker), findsNothing);
      expect(find.byTooltip(loc.nextMonthTooltip), findsNothing);
      expect(find.byTooltip(loc.previousMonthTooltip), findsNothing);
      await calendarPeriod(tester, 'Year', 2024);
      await calendarPeriod(tester, 'Month', 1);
      expect(
        find.byKey(const ValueKey('calendar-grid-2024-1')),
        findsOneWidget,
      );
      await upcomingTap(tester, 'calendar-day-31');
      expect(
        tester.widget<CalendarMonthGrid>(picker).selectedDay,
        DateTime(2024, 1, 31),
      );
      await calendarPeriod(tester, 'Month', 2);
      expect(
        tester.widget<CalendarMonthGrid>(picker).selectedDay,
        DateTime(2024, 2, 29),
      );
      expect(find.byKey(const ValueKey('calendar-day-30')), findsNothing);
      await calendarPeriod(tester, 'Year', 2025);
      expect(
        tester.widget<CalendarMonthGrid>(picker).selectedDay,
        DateTime(2025, 2, 28),
      );
      expect(
        find.byKey(const ValueKey('calendar-grid-2025-2')),
        findsOneWidget,
      );
      await upcomingTap(tester, 'calendar-day-15');
      final selected = DateTime(2025, 2, 15);
      expect(tester.widget<CalendarMonthGrid>(picker).selectedDay, selected);
      await upcomingTap(tester, 'calendar-view-Today');
      await upcomingTap(tester, 'calendar-view-Week');
      await upcomingTap(tester, 'calendar-view-Month');
      expect(tester.widget<CalendarMonthGrid>(picker).selectedDay, selected);
      expect(tester.takeException(), isNull);
    },
  );

  test('calendar includes only active statuses', () {
    final List<OrderSummary> result = calendarRelevantOrders(
      OrderStatus.values
          .map((status) => _order(status.name, status: status))
          .toList(),
    );
    expect(result.map((o) => o.status), <OrderStatus>[
      OrderStatus.pending,
      OrderStatus.confirmed,
      OrderStatus.preparing,
      OrderStatus.ready,
    ]);
  });

  test('calendar includes paid scheduled orders and excludes failed ones', () {
    final List<OrderSummary> result = calendarRelevantOrders(<OrderSummary>[
      _order('paid', scheduled: '2026-09-05T18:00:00Z'),
      _order(
        'failed',
        scheduled: '2026-09-05T18:00:00Z',
        payment: PaymentStatus.failed,
      ),
    ]);

    expect(result.map((OrderSummary order) => order.orderNumber), <String>[
      'paid',
    ]);
  });

  test('groups UTC instants by Pacific day and sorts by instant', () {
    final List<OrderSummary> orders = <OrderSummary>[
      _order('later', scheduled: '2026-09-05T07:30:00Z'),
      _order('earlier', scheduled: '2026-09-05T06:30:00Z'),
    ];
    final Map<String, List<OrderSummary>> grouped =
        groupCalendarOrdersByPacificDay(orders);
    expect(grouped['2026-09-04']?.single.orderNumber, 'earlier');
    expect(grouped['2026-09-05']?.single.orderNumber, 'later');
  });

  test(
    'Pacific grouping integrates ASAP by createdAt without losing orders',
    () {
      final OrderSummary beforeDst = _order(
        'before-dst',
        scheduled: '2026-03-08T07:30:00Z',
      );
      final OrderSummary afterDst = _order(
        'after-dst',
        scheduled: '2026-03-08T10:30:00Z',
      );
      final OrderSummary unscheduled = _order(
        'asap',
        created: '2026-03-08T10:15:00Z',
      );
      final grouped = groupCalendarOrdersByPacificDay(<OrderSummary>[
        beforeDst,
        afterDst,
        unscheduled,
      ]);
      expect(grouped['2026-03-07']?.single, beforeDst);
      expect(grouped['2026-03-08'], [unscheduled, afterDst]);
      expect(grouped.values.expand((day) => day).length, 3);
    },
  );

  test('ASAP uses Pacific dates across midnight and both DST changes', () {
    final orders = [
      _order('spring-before', created: '2026-03-08T07:59:00Z'),
      _order('spring-after', created: '2026-03-08T10:01:00Z'),
      _order('fall-before', created: '2026-11-01T06:59:00Z'),
      _order('fall-first', created: '2026-11-01T08:30:00Z'),
      _order('fall-second', created: '2026-11-01T09:30:00Z'),
    ];
    final grouped = groupCalendarOrdersByPacificDay(orders);
    expect(grouped['2026-03-07'], [orders[0]]);
    expect(grouped['2026-03-08'], [orders[1]]);
    expect(grouped['2026-10-31'], [orders[2]]);
    expect(grouped['2026-11-01'], [orders[3], orders[4]]);
    expect(grouped.values.expand((day) => day).toSet(), orders.toSet());
  });

  test('history date boundaries use Pacific and filters compose with AND', () {
    final DateTime now = DateTime.parse(
      '2026-09-05T06:30:00Z',
    ); // Sep 4 Pacific
    final List<OrderSummary> loaded = <OrderSummary>[
      _order(
        'match',
        created: '2026-09-04T08:00:00Z',
        type: OrderType.catering,
        fulfillment: FulfillmentType.delivery,
        payment: PaymentStatus.refunded,
      ),
      _order('wrong-type', created: '2026-09-04T08:00:00Z'),
      _order('seven-day-boundary', created: '2026-08-30T06:59:00Z'),
      _order('thirty-day-boundary', created: '2026-08-06T07:00:00Z'),
    ];
    expect(filterHistoricalOrders(loaded, const HistoryFilters()).length, 4);
    expect(
      filterHistoricalOrders(
        loaded,
        const HistoryFilters(
          date: HistoryDateFilter.today,
          orderType: OrderType.catering,
          fulfillment: FulfillmentType.delivery,
          payment: PaymentStatus.refunded,
        ),
        now: now,
      ).map((o) => o.orderNumber),
      <String>['match'],
    );
    expect(
      filterHistoricalOrders(
        loaded,
        const HistoryFilters(date: HistoryDateFilter.last7Days),
        now: now,
      ).map((o) => o.orderNumber),
      contains('seven-day-boundary'),
    );
    expect(
      filterHistoricalOrders(
        loaded,
        const HistoryFilters(date: HistoryDateFilter.last30Days),
        now: now,
      ).map((o) => o.orderNumber),
      contains('thirty-day-boundary'),
    );
    expect(const HistoryFilters().isClear, isTrue);
  });

  test(
    'calendar provider switches location without status query or mixing',
    () async {
      final _Repository repository = _Repository();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          currentLocationProvider.overrideWith(_CurrentLocation.new),
          ordersRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(calendarOrdersProvider, (_, _) {});
      addTearDown(subscription.close);
      expect(
        (await container.read(calendarOrdersProvider.future))
            .orders
            .single
            .locationId,
        'A',
      );
      (container.read(currentLocationProvider.notifier) as _CurrentLocation)
          .change(_location('B'));
      await Future<void>.delayed(Duration.zero);
      expect(
        (await container.read(calendarOrdersProvider.future))
            .orders
            .single
            .locationId,
        'B',
      );
      expect(repository.calls, <(String, OrderStatus?)>[
        ('A', null),
        ('B', null),
      ]);
    },
  );

  for (final view in ['Today', 'Week']) {
    testWidgets('calendar card opens detail UUID and Back restores $view', (
      tester,
    ) async {
      final GoRouter router = GoRouter(
        initialLocation: '/app/orders/calendar',
        routes: <RouteBase>[
          GoRoute(
            path: '/app/orders/calendar',
            builder: (_, _) => const OrdersCalendarScreen(),
          ),
          GoRoute(
            path: '/app/orders/:id',
            builder: (_, state) =>
                Scaffold(body: Text('detail ${state.pathParameters['id']}')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentLocationProvider.overrideWith(_CurrentLocation.new),
            ordersRepositoryProvider.overrideWithValue(
              _Repository(
                scheduled: DateTime.now()
                    .toUtc()
                    .add(Duration(days: view == 'Week' ? 7 : 0))
                    .toIso8601String(),
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await upcomingTap(tester, 'calendar-view-$view');
      if (view == 'Week') {
        await upcomingTap(tester, 'calendar-next-week');
      }
      final weekDay = view == 'Week'
          ? tester
                .widget<CalendarWeekSelector>(find.byType(CalendarWeekSelector))
                .selectedDay
          : null;
      await tester.enterText(find.byType(TextField), 'calendar-order');
      await tester.pumpAndSettle();
      await upcomingTap(tester, 'calendar-sort');
      await upcomingTap(tester, 'upcoming-type-online');
      await upcomingTap(tester, 'upcoming-sheet-apply');
      await upcomingTap(tester, 'calendar-filter-button');
      await upcomingTap(tester, 'upcoming-status-pending');
      await upcomingTap(tester, 'upcoming-sheet-apply');
      final orderCard = find.text('View Order Details');
      await tester.ensureVisible(orderCard);
      await tester.pumpAndSettle();
      final scroll = Scrollable.of(tester.element(orderCard)).position;
      final offset = scroll.pixels;
      await tester.tap(orderCard);
      await tester.pumpAndSettle();
      expect(find.text('detail calendar-uuid'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Calendar'), findsOneWidget);
      expect(scroll.pixels, offset);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(Key('calendar-view-$view')))
            .selected,
        isTrue,
      );
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'calendar-order',
      );
      if (weekDay != null) {
        expect(
          tester
              .widget<CalendarWeekSelector>(find.byType(CalendarWeekSelector))
              .selectedDay,
          weekDay,
        );
      }
      await upcomingTap(tester, 'calendar-sort');
      expect(
        tester
            .widget<RadioGroup<OrderType?>>(find.byType(RadioGroup<OrderType?>))
            .groupValue,
        OrderType.online,
      );
      await upcomingDismiss(tester);
      await upcomingTap(tester, 'calendar-filter-button');
      expect(
        tester
            .widget<RadioGroup<OrderStatus?>>(
              find.byType(RadioGroup<OrderStatus?>),
            )
            .groupValue,
        OrderStatus.pending,
      );
      await upcomingDismiss(tester);
    });
  }
}

OrderSummary _order(
  String number, {
  OrderStatus status = OrderStatus.pending,
  String created = '2026-09-04T08:00:00Z',
  String? scheduled,
  String location = 'A',
  OrderType type = OrderType.online,
  FulfillmentType fulfillment = FulfillmentType.pickup,
  PaymentStatus payment = PaymentStatus.paid,
  String? id,
}) => OrderSummary(
  id: id ?? '$number-id',
  orderNumber: number,
  locationId: location,
  orderType: type,
  status: status,
  rawStatus: status.name,
  paymentStatus: payment,
  fulfillmentType: fulfillment,
  contactName: 'Customer',
  scheduledFor: scheduled == null ? null : DateTime.parse(scheduled),
  createdAt: DateTime.parse(created),
  itemCount: 1,
  totalCents: 1000,
);

Location _location(String id) => Location(
  id: id,
  name: id,
  slug: id,
  isActive: true,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  isAcceptingOrders: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _CurrentLocation extends CurrentLocationController {
  @override
  Future<Location?> build() async => _location('A');
  void change(Location value) => state = AsyncData<Location?>(value);
}

class _Repository implements OrdersRepository {
  _Repository({this.scheduled});
  final String? scheduled;
  final List<(String, OrderStatus?)> calls = <(String, OrderStatus?)>[];
  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async {
    calls.add((locationId, status));
    return <OrderSummary>[
      _order(
        'calendar-order',
        id: 'calendar-uuid',
        location: locationId,
        scheduled: scheduled,
      ),
    ];
  }

  @override
  Future<OrderDetail> getOrderById(String id) async =>
      orderDetail(id: id, locationId: calls.last.$1);
  @override
  Future<OrderDetail> updateInternalNotes({
    required String orderId,
    required String internalNotes,
  }) => throw UnimplementedError();
  @override
  Future<OrderDetail> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  }) => throw UnimplementedError();
}
