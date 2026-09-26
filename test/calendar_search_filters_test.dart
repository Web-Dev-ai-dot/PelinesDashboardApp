import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/core/time/pelines_time.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';
import 'package:pelines_admin_app/features/orders/presentation/orders_calendar_screen.dart';

import 'order_test_data.dart';

class _Location extends CurrentLocationController {
  @override
  Future<Location?> build() async => Location(
    id: 'A',
    name: 'Backend Location',
    slug: 'a',
    isActive: true,
    deliveryFeeCents: 0,
    deliveryMinimumCents: 0,
    isAcceptingOrders: true,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

class _Repo implements OrdersRepository {
  int calls = 0;
  bool empty = false;
  final now = DateTime.now().toUtc();
  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async {
    calls++;
    if (empty) return [];
    return [
      for (final entry in [
        ('one', 'Smith', 'catering', 'confirmed', 'Wedding Fiesta', 0),
        ('two', 'Smith', 'online', 'pending', '', 0),
        ('three', 'Smith', 'catering', 'ready', 'Office Lunch', 0),
        ('four', 'Jones', 'catering', 'confirmed', 'Team Dinner', 0),
        ('five', 'Smith', 'catering', 'confirmed', 'Next Day', 1),
        ('done', 'Smith', 'catering', 'delivered', '', 0),
        ('cancelled', 'Smith', 'catering', 'cancelled', '', 0),
      ])
        OrderSummary.fromJson({
          ...orderJson(
            id: 'ref-${entry.$1}',
            locationId: locationId,
            status: entry.$4,
          ),
          'orderNumber': 'ORD-${entry.$1}',
          'contactName': entry.$2,
          'orderType': entry.$3,
          'eventDetails': {'eventName': entry.$5},
          'scheduledFor': now.add(Duration(days: entry.$6)).toIso8601String(),
        }),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(
  WidgetTester tester,
  _Repo repo, {
  double width = 390,
  double scale = 1,
  String lang = 'en',
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentLocationProvider.overrideWith(_Location.new),
        ordersRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: Locale(lang),
        supportedLocales: AdminLocalizations.supportedLocales,
        localizationsDelegates: const [
          AdminLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const OrdersCalendarScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String value) async {
  final field = find.descendant(
    of: find.byKey(const Key('calendar-search')),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, String key, String value) async {
  final field = find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(DropdownButton<String>),
  );
  tester.widget<DropdownButton<String>>(field).onChanged!(value);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'search fields, trim/case, type/status AND and clearing are local',
    (tester) async {
      final repo = _Repo();
      await _mount(tester, repo);
      expect(find.text('ORD-one'), findsOneWidget);
      expect(find.text('ORD-done'), findsNothing);
      expect(find.text('ORD-cancelled'), findsNothing);
      for (final query in [
        '  sMiTh  ',
        'ORD-ONE',
        'wedding fiesta',
        'ref-one',
      ]) {
        await _search(tester, query);
        expect(find.text('ORD-one'), findsOneWidget);
        expect(find.text('ORD-four'), findsNothing);
      }
      await _search(tester, 'Smith');
      await _select(tester, 'calendar-type', 'catering');
      expect(find.text('ORD-two'), findsNothing);
      expect(find.text('ORD-three'), findsOneWidget);
      await _select(tester, 'calendar-status', 'confirmed');
      expect(find.text('ORD-one'), findsOneWidget);
      expect(find.text('ORD-three'), findsNothing);
      expect(find.text('ORD-five'), findsNothing);
      await _search(tester, '');
      expect(find.text('ORD-four'), findsOneWidget);
      await _select(tester, 'calendar-type', 'all');
      await _select(tester, 'calendar-status', 'all');
      expect(find.text('ORD-two'), findsOneWidget);
      expect(repo.calls, 1);
      final status = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(const Key('calendar-status')),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(status.items!.map((i) => i.value), [
        'all',
        'pending',
        'confirmed',
        'preparing',
        'ready',
      ]);
      await _select(tester, 'calendar-status', 'pending');
      expect(find.text('ORD-two'), findsOneWidget);
      expect(find.text('ORD-one'), findsNothing);
    },
  );
  testWidgets(
    'filtered empty differs from true empty; selected day/month preserved',
    (tester) async {
      final repo = _Repo();
      await _mount(tester, repo);
      final initial = tester
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .initialDate;
      await _search(tester, 'absent');
      expect(find.text('No orders match these filters'), findsOneWidget);
      expect(
        find.text('No scheduled orders found for this location.'),
        findsNothing,
      );
      expect(
        tester
            .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
            .initialDate,
        initial,
      );
      await _search(tester, 'Next Day');
      final next = PelinesTime.inPacific(repo.now.add(const Duration(days: 1)));
      tester
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .onDateChanged(DateTime(next.year, next.month, next.day));
      await tester.pumpAndSettle();
      expect(find.text('ORD-five'), findsOneWidget);
      expect(find.text('ORD-one'), findsNothing);
      await _search(tester, '');
      expect(find.text('ORD-five'), findsOneWidget);
      expect(find.text('ORD-one'), findsNothing);
      expect(repo.calls, 1);
      repo.empty = true;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OrdersCalendarScreen)),
      );
      await container.read(calendarOrdersProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(
        find.text('No scheduled orders found for this location.'),
        findsOneWidget,
      );
      expect(find.text('No orders match these filters'), findsNothing);
    },
  );
  for (final size in [
    (390.0, 1.0),
    (768.0, 1.0),
    (1400.0, 1.0),
    (320.0, 2.0),
  ]) {
    for (final lang in ['en', 'es']) {
      testWidgets('filters responsive ${size.$1} ${size.$2} $lang', (
        tester,
      ) async {
        await _mount(
          tester,
          _Repo(),
          width: size.$1,
          scale: size.$2,
          lang: lang,
        );
        expect(
          find.text(
            lang == 'es'
                ? 'Buscar cliente, evento u orden'
                : 'Search customer, event or order',
          ),
          findsOneWidget,
        );
        final field = find.descendant(
          of: find.byKey(const Key('calendar-type')),
          matching: find.byType(DropdownButton<String>),
        );
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Catering').last);
        await tester.pumpAndSettle();
        await _search(tester, 'absent');
        expect(
          find.text(
            lang == 'es'
                ? 'Ningún pedido coincide con estos filtros'
                : 'No orders match these filters',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
