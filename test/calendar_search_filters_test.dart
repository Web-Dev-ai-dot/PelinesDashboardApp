import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/core/time/pelines_time.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';
import 'package:pelines_admin_app/features/orders/presentation/orders_calendar_screen.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_preview_card.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_preview_action.dart';
import 'package:pelines_admin_app/features/orders/models/calendar_planning.dart';

import 'order_test_data.dart';
import 'calendar_test_helpers.dart';

import 'package:pelines_admin_app/features/orders/presentation/calendar_month_grid.dart';

import 'upcoming_sheet_helpers.dart';

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
  _Repo({this.includeAsap = false});
  final bool includeAsap;
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
        if (includeAsap) ('asap', 'ASAP Customer', 'online', 'pending', '', 0),
      ])
        OrderSummary.fromJson({
          ...orderJson(
            id: 'ref-${entry.$1}',
            locationId: locationId,
            status: entry.$4,
            fulfillment: entry.$1 == 'four' ? 'delivery' : 'pickup',
          ),
          'orderNumber': 'ORD-${entry.$1}',
          'contactName': entry.$2,
          'orderType': entry.$3,
          'eventDetails': {'eventName': entry.$5},
          'scheduledFor': entry.$1 == 'asap'
              ? null
              : now.add(Duration(days: entry.$6)).toIso8601String(),
        }),
    ];
  }

  @override
  Future<OrderDetail> getOrderById(String id) async => OrderDetail.fromJson({
    ...orderJson(id: id, locationId: 'A'),
    'source': 'ios',
    'items': [
      {
        'id': 'item',
        'productName': 'Taco tray',
        'unitPriceCents': 1000,
        'quantity': 1,
        'lineTotalCents': 1200,
        'modifiers': [
          {
            'id': 'extra',
            'groupName': 'Extras',
            'optionName': 'Guacamole',
            'priceDeltaCents': 200,
          },
        ],
      },
    ],
  });
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
  final type = key == 'calendar-type';
  await upcomingTap(tester, type ? 'calendar-sort' : 'calendar-filter-button');
  await upcomingTap(tester, 'upcoming-${type ? 'type' : 'status'}-$value');
  await upcomingTap(tester, 'upcoming-sheet-apply');
}

void main() {
  testWidgets(
    'phone Month and Year share a row and popup selection updates grid',
    (tester) async {
      await _mount(tester, _Repo(), width: 390);
      await upcomingTap(tester, 'calendar-view-Month');
      final selected = tester
          .widget<CalendarMonthGrid>(find.byType(CalendarMonthGrid))
          .selectedDay;
      final month = find.byKey(ValueKey('calendar-Month-${selected.month}'));
      final year = find.byKey(ValueKey('calendar-Year-${selected.year}'));
      expect(tester.getTopLeft(month).dy, tester.getTopLeft(year).dy);
      await tester.ensureVisible(month);
      await tester.pumpAndSettle();
      await tester.tap(month);
      await tester.pumpAndSettle();
      final nextMonth = selected.month == 12 ? 11 : selected.month + 1;
      await tester.tap(
        find
            .text(
              DateFormat.MMMM('en').format(DateTime(selected.year, nextMonth)),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('calendar-grid-${selected.year}-$nextMonth')),
        findsOneWidget,
      );
      await tester.ensureVisible(year);
      await tester.pumpAndSettle();
      await tester.tap(year);
      await tester.pumpAndSettle();
      await tester.tap(find.text('${selected.year + 1}').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('calendar-grid-${selected.year + 1}-$nextMonth')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 768.0]) {
    for (final lang in ['en', 'es']) {
      testWidgets('only Month Year dropdowns without KPIs $width/$lang/2x', (
        tester,
      ) async {
        await _mount(tester, _Repo(), width: width, scale: 2, lang: lang);
        for (final view in ['Today', 'Week', 'Month']) {
          await upcomingTap(tester, 'calendar-view-$view');
          expect(find.byKey(const Key('calendar-today-kpi')), findsNothing);
          expect(find.byKey(const Key('calendar-revenue-kpi')), findsNothing);
          expect(
            find.text(lang == 'en' ? 'Orders Today' : 'Órdenes de hoy'),
            findsNothing,
          );
          expect(
            find.text(
              lang == 'en' ? 'Estimated Revenue' : 'Ingresos estimados',
            ),
            findsNothing,
          );
        }
        final picker = find.byType(CalendarMonthGrid);
        expect(picker, findsOneWidget);
        expect(find.byType(DropdownButtonFormField<int>), findsNWidgets(2));
        expect(find.byType(CalendarDatePicker), findsNothing);
        final loc = MaterialLocalizations.of(tester.element(picker));
        expect(find.byTooltip(loc.nextMonthTooltip), findsNothing);
        expect(find.byTooltip(loc.previousMonthTooltip), findsNothing);
        await calendarPeriod(tester, lang == 'en' ? 'Year' : 'Año', 2028);
        await calendarPeriod(tester, lang == 'en' ? 'Month' : 'Mes', 2);
        expect(
          find.byKey(const ValueKey('calendar-grid-2028-2')),
          findsOneWidget,
        );
        expect(
          find.text(DateFormat.MMMM(lang).format(DateTime(2028, 2))),
          findsOneWidget,
        );
        await upcomingTap(tester, 'calendar-day-29');
        expect(
          tester.widget<CalendarMonthGrid>(picker).selectedDay,
          DateTime(2028, 2, 29),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'ASAP stays separate from scheduled Today; fulfillment context preserved',
    (tester) async {
      await _mount(tester, _Repo(includeAsap: true));
      expect(find.text('Needs pickup time'), findsOneWidget);
      expect(find.text('ASAP'), findsOneWidget);
      expect(find.text('Pickup'), findsWidgets);
      expect(find.text('Delivery'), findsWidgets);

      expect(find.byType(OrderPreviewAction), findsNothing);
    },
  );
  testWidgets('Today has no KPI cards and retains planning cards and filters', (
    tester,
  ) async {
    final repo = _Repo();
    await _mount(tester, repo);
    expect(find.byKey(const Key('calendar-today-kpi')), findsNothing);
    expect(find.byKey(const Key('calendar-revenue-kpi')), findsNothing);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('calendar-view-Today')))
          .selected,
      isTrue,
    );
    expect(find.byType(CalendarMonthGrid), findsNothing);
    expect(find.byKey(const Key('todo-board-scroll')), findsNothing);
    expect(find.byType(OrderPreviewAction), findsNothing);
    expect(find.text('Print ticket'), findsNothing);
    expect(find.text('View Order Details'), findsNWidgets(4));
    expect(find.textContaining('Taco tray'), findsWidgets);
    expect(find.textContaining('Guacamole'), findsWidgets);
    expect(find.text('iOS'), findsWidgets);
    final cards = tester.getRect(find.byType(OrderPreviewCard).first);
    final second = tester.getRect(find.byType(OrderPreviewCard).at(1));
    expect(second.top, greaterThanOrEqualTo(cards.bottom));
    await _search(tester, 'wedding');
    expect(find.text('1 order'), findsOneWidget);

    await _select(tester, 'calendar-type', 'online');
    expect(find.text('0 orders'), findsOneWidget);

    expect(repo.calls, 1);
  });

  test('Week calendar coordinates span DST and year boundaries', () {
    expect(
      calendarWeek(DateTime.utc(2026, 3, 8)),
      List.generate(7, (i) => DateTime.utc(2026, 3, 2 + i)),
    );
    expect(
      calendarWeek(DateTime.utc(2026, 11, 1)).last,
      DateTime.utc(2026, 11, 1),
    );
    expect(
      calendarWeek(DateTime.utc(2027, 1, 1)).first,
      DateTime.utc(2026, 12, 28),
    );
  });

  for (final lang in ['en', 'es']) {
    testWidgets(
      'Today full date localized and Week/Month return preserves search $lang',
      (tester) async {
        final repo = _Repo();
        await _mount(tester, repo, lang: lang);
        expect(
          find.text(DateFormat.yMMMMEEEEd(lang).format(PelinesTime.now())),
          findsOneWidget,
        );
        await _search(tester, 'Wedding');
        expect(find.text(lang == 'en' ? '1 order' : '1 orden'), findsOneWidget);
        await upcomingTap(tester, 'calendar-view-Week');
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(const Key('calendar-view-Week')))
              .selected,
          isTrue,
        );
        expect(find.text('ORD-one'), findsOneWidget);
        await upcomingTap(tester, 'calendar-view-Month');
        expect(find.byType(CalendarMonthGrid), findsOneWidget);
        await upcomingTap(tester, 'calendar-view-Today');
        expect(find.byType(CalendarMonthGrid), findsNothing);
        expect(find.text('ORD-one'), findsOneWidget);
        expect(find.text('ORD-two'), findsNothing);
        expect(repo.calls, 1);
      },
    );
  }
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
      await upcomingTap(tester, 'calendar-filter-button');
      expect(find.byKey(const Key('upcoming-status-delivered')), findsNothing);
      expect(find.byKey(const Key('upcoming-from')), findsNothing);
      expect(find.byType(RadioListTile<OrderStatus?>), findsNWidgets(5));
      await upcomingDismiss(tester);
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
      await upcomingTap(tester, 'calendar-view-Month');
      final initial = tester
          .widget<CalendarMonthGrid>(find.byType(CalendarMonthGrid))
          .selectedDay;
      await _search(tester, 'absent');
      expect(find.text('No orders match these filters'), findsOneWidget);
      expect(
        find.text('No scheduled orders found for this location.'),
        findsNothing,
      );
      expect(
        tester
            .widget<CalendarMonthGrid>(find.byType(CalendarMonthGrid))
            .selectedDay,
        initial,
      );
      await _search(tester, 'Next Day');
      final next = PelinesTime.inPacific(repo.now.add(const Duration(days: 1)));
      tester
          .widget<CalendarMonthGrid>(find.byType(CalendarMonthGrid))
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
                ? 'Buscar cliente, evento o número de orden'
                : 'Search customer, event or order #',
          ),
          findsOneWidget,
        );
        await _select(tester, 'calendar-type', 'catering');
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
