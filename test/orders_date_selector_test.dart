import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/core/time/pelines_time.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/models/orders_date_filter.dart';
import 'package:pelines_admin_app/features/orders/presentation/today_orders_view.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

import 'order_test_data.dart';

OrderSummary _order(
  String id,
  DateTime created, {
  DateTime? scheduled,
  OrderStatus status = OrderStatus.pending,
  PaymentStatus payment = PaymentStatus.paid,
  String locationId = 'A',
}) => OrderSummary(
  id: id,
  orderNumber: id,
  locationId: locationId,
  orderType: OrderType.online,
  status: status,
  rawStatus: status.name,
  paymentStatus: payment,
  fulfillmentType: FulfillmentType.pickup,
  contactName: 'Customer',
  scheduledFor: scheduled,
  createdAt: created,
  itemCount: 1,
  totalCents: 1000,
);

final _location = Location(
  id: 'A',
  name: 'Troutdale',
  slug: 'A',
  isActive: true,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  isAcceptingOrders: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _Current extends CurrentLocationController {
  @override
  Future<Location?> build() async => _location;
}

class _Repository implements OrdersRepository {
  _Repository(this.orders);
  final List<OrderSummary> orders;
  int calls = 0;
  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async {
    calls++;
    return orders;
  }

  @override
  Future<OrderDetail> getOrderById(String id) async {
    final summary = orders.firstWhere((o) => o.id == id);
    return OrderDetail.fromJson(
      orderJson(
        id: id,
        status: summary.status.name,
        locationId: summary.locationId,
        fulfillment: summary.fulfillmentType.name,
        payment: summary.paymentStatus.name,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _date(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('orders-date-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(PopupMenuItem<OrdersDateFilter>, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Waiting badge counts paid pending for current location and updates without another poller',
    (tester) async {
      final now = DateTime.now();
      final repository = _Repository([
        _order('pending-one', now),
        _order('pending-two', now),
        _order('accepted', now, status: OrderStatus.confirmed),
        _order('failed', now, payment: PaymentStatus.failed),
        _order('other-location', now, locationId: 'B'),
        for (final status in [
          OrderStatus.pending,
          OrderStatus.confirmed,
          OrderStatus.preparing,
          OrderStatus.ready,
        ])
          _order(
            'future-${status.name}',
            now,
            scheduled: now.add(const Duration(days: 7)),
            status: status,
          ),
      ]);
      final container = ProviderContainer(
        overrides: [
          currentLocationProvider.overrideWith(_Current.new),
          ordersRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: TodayOrdersView(
                location: _location,
                onChangeLocation: () {},
                // To Do must ignore dates even if a caller supplies one.
                initialDateFilter: OrdersDateFilter.upcoming,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final badge = find.byKey(const Key('waiting-count'));
      expect(find.byKey(const Key('orders-date-selector')), findsNothing);
      expect(
        find.descendant(of: badge, matching: find.text('2')),
        findsOneWidget,
      );
      expect(find.text('accepted'), findsOneWidget);
      expect(find.text('pending-one'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Waiting'));
      await tester.pumpAndSettle();
      expect(find.text('pending-one'), findsOneWidget);
      expect(find.text('accepted'), findsNothing);
      repository.orders.removeWhere((order) => order.id == 'pending-one');
      await container.read(todayOrdersProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: badge, matching: find.text('1')),
        findsOneWidget,
      );
      final calls = repository.calls;
      for (final label in [
        'Confirmed',
        'Preparing',
        'Ready',
        'All',
        'Waiting',
      ]) {
        final chip = find.widgetWithText(ChoiceChip, label);
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(find.textContaining('future-'), findsNothing);
      }
      await tester.pump(const Duration(seconds: 45));
      expect(repository.calls, calls);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Orders date options fit phone with enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentLocationProvider.overrideWith(_Current.new),
          ordersRepositoryProvider.overrideWithValue(_Repository([])),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: TodayOrdersView(
              location: _location,
              onChangeLocation: () {},
              webOrders: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final value in ['Tomorrow', 'Upcoming', 'All dates', 'Today']) {
      await _date(tester, value);
      expect(
        tester.getSize(find.byKey(const Key('orders-date-selector'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    }
  });

  for (final (now, today, tomorrow, later) in [
    (
      '2026-03-08T08:30:00Z',
      '2026-03-09T06:59:00Z',
      '2026-03-09T07:00:00Z',
      '2026-03-10T07:00:00Z',
    ),
    (
      '2026-11-01T07:30:00Z',
      '2026-11-02T07:59:00Z',
      '2026-11-02T08:00:00Z',
      '2026-11-03T08:00:00Z',
    ),
  ]) {
    test(
      'date filters respect Pacific calendar boundaries across DST at $now',
      () {
        final orders = [
          _order('today', DateTime.parse(today)),
          _order(
            'tomorrow',
            DateTime.utc(2020),
            scheduled: DateTime.parse(tomorrow),
          ),
          _order('later', DateTime.parse(later)),
        ];
        List<String> ids(OrdersDateFilter filter) => filterOrdersByDate(
          orders,
          filter,
          now: DateTime.parse(now),
        ).map((o) => o.id).toList();
        expect(ids(OrdersDateFilter.today), ['today']);
        expect(ids(OrdersDateFilter.tomorrow), ['tomorrow']);
        expect(ids(OrdersDateFilter.upcoming), ['tomorrow', 'later']);
        expect(ids(OrdersDateFilter.allDates), ['today', 'tomorrow', 'later']);
        expect(
          filterOrdersByDate(
            orders,
            OrdersDateFilter.chooseDate,
            chosenDate: pacificDate(DateTime.parse(tomorrow)),
          ).single.id,
          'tomorrow',
        );
      },
    );
  }
  test('UTC date rollover still uses yesterday in Pacific', () {
    final order = _order('pacific', DateTime.parse('2026-09-05T06:30:00Z'));
    expect(
      filterOrdersByDate(
        [order],
        OrdersDateFilter.chooseDate,
        chosenDate: DateTime(2026, 9, 4),
      ),
      [order],
    );
    expect(
      filterOrdersByDate(
        [order],
        OrdersDateFilter.chooseDate,
        chosenDate: DateTime(2026, 9, 5),
      ),
      isEmpty,
    );
  });

  testWidgets(
    'Confirmed initial, ordered filters, dates reuse Calendar, detail and refresh preserve state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pacific = PelinesTime.now();
      DateTime at(int offset) =>
          DateTime.utc(pacific.year, pacific.month, pacific.day + offset, 18);
      final repository = _Repository([
        _order('waiting-today', at(0)),
        for (var i = 0; i < 15; i++)
          _order('confirmed-$i', at(0), status: OrderStatus.confirmed),
        _order('waiting-tomorrow', at(1)),
        _order('waiting-later', at(3)),
        _order('waiting-past', at(-1)),
        _order('completed', at(0), status: OrderStatus.delivered),
        _order('unpaid', at(0), payment: PaymentStatus.failed),
      ]);
      final container = ProviderContainer(
        overrides: [
          currentLocationProvider.overrideWith(_Current.new),
          ordersRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: TodayOrdersView(
                webOrders: true,
                location: _location,
                onChangeLocation: () {},
              ),
            ),
          ),
          GoRoute(
            path: '/app/orders/:id',
            builder: (_, state) =>
                Scaffold(body: Text('detail ${state.pathParameters['id']}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .map((c) => c.label is Text ? (c.label as Text).data : 'Waiting'),
        ['Waiting', 'Confirmed', 'Preparing', 'Ready', 'All'],
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Confirmed'))
            .selected,
        isTrue,
      );
      expect(find.textContaining(RegExp(r'^confirmed-')), findsWidgets);
      expect(repository.calls, 1);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Confirmed'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      final offset = scroll.pixels;
      final card = find
          .textContaining(RegExp(r'^confirmed-'))
          .hitTestable()
          .first;
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.textContaining('detail confirmed-'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(scroll.pixels, offset);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Confirmed'))
            .selected,
        isTrue,
      );
      await container.read(todayOrdersProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(scroll.pixels, offset);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Confirmed'))
            .selected,
        isTrue,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Waiting'));
      await tester.pumpAndSettle();
      await _date(tester, 'Tomorrow');
      expect(find.text('waiting-tomorrow'), findsOneWidget);
      final loadedCalls = repository.calls;
      await _date(tester, 'Upcoming');
      expect(find.text('waiting-tomorrow'), findsOneWidget);
      expect(find.text('waiting-later'), findsOneWidget);
      await _date(tester, 'All dates');
      expect(find.textContaining('not a complete history'), findsOneWidget);
      expect(repository.calls, loadedCalls);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      final all = container.read(calendarOrdersProvider).requireValue.orders;
      expect(all.any((o) => o.id == 'completed' || o.id == 'unpaid'), isFalse);
      await _date(tester, 'Choose date…');
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('All dates'), findsOneWidget);
      await _date(tester, 'Choose date…');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(
        tester
            .widget<PopupMenuButton<OrdersDateFilter>>(
              find.byKey(const Key('orders-date-selector')),
            )
            .initialValue,
        OrdersDateFilter.chooseDate,
      );
      await _date(tester, 'Today');
      expect(repository.calls, loadedCalls);
      expect(tester.takeException(), isNull);
    },
  );
}
