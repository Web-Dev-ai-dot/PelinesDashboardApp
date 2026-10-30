import 'package:pelines_admin_app/features/orders/presentation/order_parity_content.dart';
import 'package:pelines_admin_app/app/theme/pelines_components.dart';
import 'package:flutter/material.dart';
import 'package:pelines_admin_app/features/locations/presentation/pelines_location_context.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';
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
import 'package:pelines_admin_app/features/orders/presentation/calendar_week_selector.dart';

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
          'createdAt': now.toIso8601String(),
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
  double height = 1400,
  double keyboard = 0,
  String lang = 'en',
}) async {
  tester.view.physicalSize = Size(width, height);
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
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
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
  final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
  expect(sheet.showDragHandle, isTrue);
  expect(sheet.backgroundColor, PelinesColors.card);
  expect(
    (sheet.shape! as RoundedRectangleBorder).borderRadius,
    const BorderRadius.vertical(top: Radius.circular(32)),
  );
  await upcomingTap(tester, 'upcoming-${type ? 'type' : 'status'}-$value');
  await upcomingTap(tester, 'upcoming-sheet-apply');
}

void main() {
  for (final viewport in [
    for (final width in [320.0, 390.0, 1000.0])
      for (final view in ['Week', 'Month']) (width, view),
  ]) {
    final width = viewport.$1;
    final view = viewport.$2;
    for (final lang in ['en', 'es']) {
      testWidgets(
        '$view compact cards preserve all items without prices $width $lang 2x',
        (tester) async {
          await _mount(
            tester,
            _CompactMonthRepo(),
            width: width,
            scale: 2,
            lang: lang,
          );
          final selectedCard = find.byWidgetPredicate(
            (w) => w is OrderPreviewCard && w.order.id == 'ref-one',
          );
          final todayHeight = tester.getSize(selectedCard).height;
          await upcomingTap(tester, 'calendar-view-$view');
          final card = find.byWidgetPredicate(
            (w) => w is OrderPreviewCard && w.order.id == 'ref-one',
          );
          final texts = find
              .descendant(of: card, matching: find.byType(Text))
              .evaluate()
              .map((e) => (e.widget as Text).data ?? '')
              .toList();
          expect(texts.any((text) => text.contains(r'$')), false);
          expect(texts, isNot(contains('Total')));
          expect(
            texts,
            isNot(contains(lang == 'en' ? 'Confirmed' : 'Confirmado')),
          );
          expect(texts, contains('2× Taco tray with a long product name'));
          expect(texts, contains('1× Refreshments'));
          expect(texts, contains('Extras: Guacamole'));
          expect(
            texts,
            contains('${lang == 'en' ? 'Note' : 'Nota'}: No onions'),
          );
          expect(texts, contains(lang == 'en' ? '3 items' : '3 artículos'));
          expect(texts, contains('Smith'));
          expect(texts, contains('Wedding Fiesta'));
          final items = find.descendant(
            of: card,
            matching: find.byType(OrderParityItem),
          );
          expect(items, findsNWidgets(2));
          expect(
            tester
                .widgetList<OrderParityItem>(items)
                .every((item) => !item.showAmounts),
            true,
          );
          final date = find.descendant(
            of: card,
            matching: find.byKey(const ValueKey('month-order-date-ref-one')),
          );
          expect(
            tester.getRect(date).right,
            closeTo(tester.getRect(card).right - 16, 1),
          );
          final badges = find.byKey(
            const ValueKey('month-order-badges-ref-one'),
          );
          expect(
            find.descendant(
              of: badges,
              matching: find.byType(PelinesStateBadge),
            ),
            findsNWidgets(3),
          );
          expect(tester.getSize(card).height, lessThan(todayHeight));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final lang in ['en', 'es']) {
    testWidgets(
      'Week and Month use primary full-width details action; Today remains secondary $lang',
      (tester) async {
        final repo = _Repo(includeAsap: true);
        await _mount(tester, repo, width: 390, lang: lang);
        final label = lang == 'en'
            ? 'View Order Details'
            : 'Ver detalles de la orden';
        for (final view in ['Month', 'Today', 'Week', 'Month']) {
          await upcomingTap(tester, 'calendar-view-$view');
          final cards = find.byType(OrderPreviewCard);
          expect(cards, findsNWidgets(5));
          for (final element in cards.evaluate()) {
            final button = find.descendant(
              of: find.byWidget(element.widget),
              matching: find.widgetWithText(PelinesButton, label),
            );
            expect(button, findsOneWidget);
            expect(
              tester.widget<PelinesButton>(button).variant,
              view != 'Today'
                  ? PelinesButtonVariant.primary
                  : PelinesButtonVariant.secondary,
            );
            if (view != 'Today') {
              expect(
                find.descendant(
                  of: button,
                  matching: find.byType(FilledButton),
                ),
                findsOneWidget,
              );
              expect(
                tester.getSize(button).width,
                closeTo(
                  tester.getSize(find.byWidget(element.widget)).width - 32,
                  1,
                ),
              );
            }
          }
          expect(find.text('ORD-asap'), findsOneWidget);
          expect(find.text('This Month'), findsNothing);
          expect(find.text('Est. Revenue'), findsNothing);
        }
        expect(repo.calls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Calendar shares short-height sheet shell without future dates', (
    tester,
  ) async {
    final repo = _Repo();
    await _mount(
      tester,
      repo,
      width: 320,
      height: 500,
      keyboard: 180,
      scale: 2,
      lang: 'es',
    );
    await _select(tester, 'calendar-type', 'online');
    await _select(tester, 'calendar-status', 'pending');
    expect(repo.calls, 1);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final lang in ['en', 'es']) {
    testWidgets(
      'Month canonical dots survive filters; Sunday first and selected circle $lang',
      (tester) async {
        final repo = _Repo(includeAsap: true);
        await _mount(tester, repo, width: 320, scale: 2, lang: lang);
        await upcomingTap(tester, 'calendar-view-Month');
        CalendarMonthGrid grid() =>
            tester.widget<CalendarMonthGrid>(find.byType(CalendarMonthGrid));
        final initial = grid().selectedDay;
        final dot = find.byKey(ValueKey('calendar-month-dot-${initial.day}'));
        expect(dot, findsOneWidget);
        expect(grid().hasOrders!(initial), isTrue);
        final selected = tester.widget<TextButton>(
          find.byKey(ValueKey('calendar-day-${initial.day}')),
        );
        expect(selected.style!.shape!.resolve({}), isA<CircleBorder>());
        expect(
          selected.style!.backgroundColor!.resolve({}),
          Colors.transparent,
        );
        expect(selected.style!.foregroundColor!.resolve({}), Colors.white);
        expect(selected.style!.side?.resolve({}), isNull);
        final circle = find.byKey(
          ValueKey('calendar-selected-circle-${initial.day}'),
        );
        final circleBox =
            tester.widget<Container>(circle).decoration as BoxDecoration;
        expect(circleBox.color, PelinesColors.brandPrimary);
        expect(circleBox.shape, BoxShape.circle);
        expect(circleBox.border, isNull);
        expect(tester.getSize(circle).width, tester.getSize(circle).height);
        expect(tester.getSize(circle).width, lessThanOrEqualTo(42));
        expect(tester.getSize(circle).width, greaterThanOrEqualTo(30));
        expect(
          tester.getRect(circle).bottom,
          lessThan(tester.getRect(dot).top),
        );

        final digit = find.descendant(of: circle, matching: find.byType(Text));
        expect(
          tester.getCenter(digit).dx,
          closeTo(tester.getCenter(circle).dx, .1),
        );
        expect(
          tester.getCenter(digit).dy,
          closeTo(tester.getCenter(circle).dy, .1),
        );
        expect(
          tester
              .getSize(find.byKey(ValueKey('calendar-day-${initial.day}')))
              .height,
          greaterThanOrEqualTo(48),
        );
        final otherDay = initial.day == 1 ? 2 : 1;
        grid().onDateChanged(DateTime(initial.year, initial.month, otherDay));
        await tester.pumpAndSettle();
        final todayButton = tester.widget<TextButton>(
          find.byKey(ValueKey('calendar-day-${initial.day}')),
        );
        expect(
          todayButton.style!.side!.resolve({})!.color,
          PelinesColors.brandPrimary,
        );
        expect(
          find.byKey(ValueKey('calendar-selected-circle-${initial.day}')),
          findsNothing,
        );
        expect(
          tester
              .widget<TextButton>(
                find.byKey(ValueKey('calendar-day-$otherDay')),
              )
              .style!
              .side
              ?.resolve({}),
          isNull,
        );
        grid().onDateChanged(initial);
        await tester.pumpAndSettle();
        await _search(tester, 'absent');
        await _select(tester, 'calendar-type', 'online');
        await _select(tester, 'calendar-status', 'ready');
        expect(dot, findsOneWidget);
        expect(grid().hasOrders!(initial), isTrue);
        expect(find.byType(OrderPreviewCard), findsNothing);
        expect(repo.calls, 1);
        grid().onDateChanged(DateTime(2026, 3, 8));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const Key('calendar-day-1'))).left,
          tester.getRect(find.byKey(const Key('calendar-day-8'))).left,
        );
        expect(
          tester.getRect(find.byKey(const Key('calendar-day-7'))).left,
          greaterThan(
            tester.getRect(find.byKey(const Key('calendar-day-1'))).left,
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Week selects one day; canonical dots survive composed filters and drafts',
    (tester) async {
      final repo = _Repo();
      await _mount(tester, repo);
      await upcomingTap(tester, 'calendar-view-Week');
      CalendarWeekSelector selector() => tester.widget<CalendarWeekSelector>(
        find.byType(CalendarWeekSelector),
      );
      final initial = selector().selectedDay;
      expect(find.text('4 orders'), findsOneWidget);
      expect(find.text('ORD-five'), findsNothing);
      expect(find.byType(OrderPreviewCard), findsNWidgets(4));
      expect(find.byType(OrderPreviewAction), findsNothing);
      expect(find.text('Print ticket'), findsNothing);
      expect(find.textContaining('Guacamole'), findsWidgets);
      for (var weekday = 1; weekday <= 7; weekday++) {
        expect(
          find.byKey(ValueKey('calendar-week-day-$weekday')),
          findsOneWidget,
        );
      }
      expect(selector().hasOrders(initial), isTrue);
      await _search(tester, 'Smith');
      await _select(tester, 'calendar-type', 'catering');
      await _select(tester, 'calendar-status', 'confirmed');
      expect(find.text('1 order'), findsOneWidget);
      await upcomingTap(tester, 'calendar-filter-button');
      await upcomingTap(tester, 'upcoming-filter-reset');
      await upcomingDismiss(tester);
      expect(find.text('1 order'), findsOneWidget);
      await upcomingTap(tester, 'calendar-sort');
      await upcomingTap(tester, 'upcoming-type-online');
      await upcomingDismiss(tester);
      expect(find.text('1 order'), findsOneWidget);
      await upcomingTap(tester, 'calendar-next-week');
      expect(selector().selectedDay, shiftCalendarWeek(initial, 1));
      expect(selector().selectedDay.weekday, initial.weekday);
      expect(find.text('0 orders'), findsOneWidget);
      await upcomingTap(tester, 'calendar-previous-week');
      expect(find.text('1 order'), findsOneWidget);
      final tomorrow = DateTime.utc(
        initial.year,
        initial.month,
        initial.day + 1,
      );
      if (tomorrow.weekday == DateTime.monday) {
        await upcomingTap(tester, 'calendar-next-week');
      }
      await upcomingTap(tester, 'calendar-week-day-${tomorrow.weekday}');
      expect(selector().selectedDay, tomorrow);
      expect(find.text('ORD-five'), findsOneWidget);
      expect(find.text('ORD-one'), findsNothing);
      expect(
        find.text(DateFormat.yMMMMEEEEd('en').format(tomorrow)),
        findsOneWidget,
      );
      await _search(tester, 'absent');
      expect(find.text('0 orders'), findsOneWidget);
      expect(
        find.byKey(ValueKey('calendar-week-dot-${tomorrow.weekday}')),
        findsOneWidget,
      );
      expect(find.text('No orders match these filters'), findsOneWidget);
      expect(repo.calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Week shifts preserve weekday across Pacific DST and year boundaries',
    () {
      for (final date in [
        DateTime.utc(2026, 3, 8),
        DateTime.utc(2026, 11, 1),
        DateTime.utc(2026, 12, 31),
      ]) {
        final next = shiftCalendarWeek(date, 1);
        expect(next.weekday, date.weekday);
        expect(shiftCalendarWeek(next, -1), date);
        expect(calendarWeek(date), contains(date));
      }
    },
  );

  for (final width in [320.0, 390.0, 768.0, 1400.0]) {
    for (final lang in ['en', 'es']) {
      testWidgets('Week selector responsive localized $width $lang 2x', (
        tester,
      ) async {
        await _mount(tester, _Repo(), width: width, scale: 2, lang: lang);
        await upcomingTap(tester, 'calendar-view-Week');
        expect(find.byKey(const Key('calendar-week-range')), findsNothing);
        final surface = find.byKey(const Key('calendar-week-surface'));
        final decoration =
            tester.widget<Container>(surface).decoration as BoxDecoration;
        expect(decoration.color, PelinesColors.card);
        expect(
          decoration.borderRadius,
          BorderRadius.circular(PelinesRadius.prominentCard),
        );
        final selectedDay = tester
            .widget<CalendarWeekSelector>(find.byType(CalendarWeekSelector))
            .selectedDay;
        expect(
          find.text(DateFormat.yMMMMEEEEd(lang).format(selectedDay)),
          findsOneWidget,
        );
        final week = calendarWeek(selectedDay);
        expect(
          find.text(
            '${DateFormat.yMMMd(lang).format(week.first)} – ${DateFormat.yMMMd(lang).format(week.last)}',
          ),
          findsNothing,
        );
        final daysViewport = find.byKey(const Key('calendar-week-days'));
        final previous = find.byKey(const Key('calendar-previous-week'));
        final next = find.byKey(const Key('calendar-next-week'));
        expect(
          tester.getRect(surface).contains(tester.getCenter(previous)),
          true,
        );
        expect(tester.getRect(surface).contains(tester.getCenter(next)), true);
        expect(
          tester.getRect(previous).right,
          lessThanOrEqualTo(tester.getRect(daysViewport).left),
        );
        expect(
          tester.getRect(next).left,
          greaterThanOrEqualTo(tester.getRect(daysViewport).right),
        );
        expect(
          tester.getCenter(previous).dy,
          closeTo(tester.getCenter(daysViewport).dy, .1),
        );
        expect(
          tester.getCenter(next).dy,
          closeTo(tester.getCenter(daysViewport).dy, .1),
        );
        expect(tester.getSize(previous).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(next).width, greaterThanOrEqualTo(48));
        final dayWidths = [
          for (var day = 1; day <= 7; day++)
            tester
                .getSize(find.byKey(ValueKey('calendar-week-day-$day')))
                .width,
        ];
        expect(dayWidths.every((w) => (w - dayWidths.first).abs() < .1), true);
        expect(
          find.text(lang == 'en' ? '4 orders' : '4 órdenes'),
          findsOneWidget,
        );
        await _search(tester, 'Wedding');
        expect(find.text(lang == 'en' ? '1 order' : '1 orden'), findsOneWidget);
        await _search(tester, 'absent');
        expect(
          find.text(lang == 'en' ? '0 orders' : '0 órdenes'),
          findsOneWidget,
        );
        await _search(tester, '');
        final selector = tester.widget<CalendarWeekSelector>(
          find.byType(CalendarWeekSelector),
        );
        expect(
          tester
              .widget<TextButton>(find.byKey(const Key('calendar-view-Week')))
              .style!
              .backgroundColor!
              .resolve({}),
          PelinesColors.brandPrimary,
        );
        for (final date in calendarWeek(selector.selectedDay)) {
          await upcomingTap(tester, 'calendar-week-day-${date.weekday}');
          expect(
            find.text(DateFormat.yMMMMEEEEd(lang).format(date)),
            findsOneWidget,
          );
          final button = find.byKey(
            ValueKey('calendar-week-day-${date.weekday}'),
          );
          expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
          expect(
            tester
                .widget<TextButton>(button)
                .style!
                .backgroundColor!
                .resolve({}),
            PelinesColors.brandPrimary,
          );
          expect(find.text(DateFormat.E(lang).format(date)), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        expect(find.byKey(const Key('calendar-today-kpi')), findsNothing);
        expect(find.byKey(const Key('calendar-revenue-kpi')), findsNothing);
      });
    }
  }
  for (final width in [320.0, 768.0, 1400.0]) {
    for (final lang in ['en', 'es']) {
      testWidgets('month arrows and title without KPIs $width/$lang/2x', (
        tester,
      ) async {
        final repo = _Repo();
        await _mount(tester, repo, width: width, scale: 2, lang: lang);
        final segmentRect = tester.getRect(
          find.byKey(const Key('calendar-view-segments')),
        );
        final segmentsDecoration =
            tester
                    .widget<Container>(
                      find.byKey(const Key('calendar-view-segments')),
                    )
                    .decoration
                as BoxDecoration;
        expect(segmentsDecoration.color, const Color(0xFFEEEEEE));
        expect(
          segmentsDecoration.borderRadius,
          BorderRadius.circular(PelinesRadius.pill),
        );

        expect(
          segmentRect.width,
          closeTo(
            tester.getSize(find.byKey(const Key('calendar-filters'))).width,
            .01,
          ),
        );
        final widths = [
          for (final view in ['Today', 'Week', 'Month'])
            tester.getSize(find.byKey(Key('calendar-view-$view'))).width,
        ];
        expect(widths[0], closeTo(widths[1], .01));
        expect(widths[1], closeTo(widths[2], .01));
        expect(
          widths.reduce((a, b) => a + b),
          closeTo(segmentRect.width - 8, .01),
        );
        for (final view in ['Today', 'Week', 'Month']) {
          await upcomingTap(tester, 'calendar-view-$view');
          final active = tester.widget<TextButton>(
            find.byKey(Key('calendar-view-$view')),
          );
          expect(
            active.style!.backgroundColor!.resolve({}),
            PelinesColors.brandPrimary,
          );
          expect(active.style!.foregroundColor!.resolve({}), Colors.white);
          for (final inactive in [
            'Today',
            'Week',
            'Month',
          ].where((entry) => entry != view)) {
            expect(
              tester
                  .widget<TextButton>(
                    find.byKey(Key('calendar-view-$inactive')),
                  )
                  .style!
                  .backgroundColor!
                  .resolve({}),
              Colors.transparent,
            );
          }

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
        final weekdays = lang == 'en'
            ? ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
            : ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];
        for (var i = 0; i < 7; i++) {
          final label = find.byKey(ValueKey('calendar-weekday-$i'));
          expect(tester.widget<Text>(label).data, weekdays[i]);
          if (i > 0) {
            expect(
              tester.getCenter(label).dx,
              greaterThan(
                tester
                    .getCenter(
                      find.byKey(ValueKey('calendar-weekday-${i - 1}')),
                    )
                    .dx,
              ),
            );
          }
        }
        final visibleGrid = tester.widget<CalendarMonthGrid>(
          find.byType(CalendarMonthGrid),
        );
        final circle = find.byKey(
          ValueKey('calendar-selected-circle-${visibleGrid.selectedDay.day}'),
        );
        if (width >= 768) expect(tester.getSize(circle).width, closeTo(40, 1));
        CalendarMonthGrid grid() =>
            tester.widget<CalendarMonthGrid>(find.byType(CalendarMonthGrid));
        for (final entry in [
          (DateTime(2024, 1, 31), 'next', DateTime(2024, 2, 29)),
          (DateTime(2025, 1, 31), 'next', DateTime(2025, 2, 28)),
          (DateTime(2024, 12, 31), 'next', DateTime(2025, 1, 31)),
          (DateTime(2025, 1, 31), 'previous', DateTime(2024, 12, 31)),
          (DateTime(2024, 3, 31), 'previous', DateTime(2024, 2, 29)),
          (DateTime(2025, 3, 30), 'next', DateTime(2025, 4, 30)),
        ]) {
          grid().onDateChanged(entry.$1);
          await tester.pumpAndSettle();
          await upcomingTap(tester, 'calendar-${entry.$2}-month');
          expect(grid().selectedDay, entry.$3);
          expect(
            find.byKey(
              ValueKey('calendar-grid-${entry.$3.year}-${entry.$3.month}'),
            ),
            findsOneWidget,
          );
          expect(
            find.text(DateFormat.yMMMM(lang).format(entry.$3)),
            findsOneWidget,
          );
          expect(
            find.text(DateFormat.yMMMMEEEEd(lang).format(entry.$3)),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
        expect(repo.calls, 1);
        final picker = find.byType(CalendarMonthGrid);
        expect(picker, findsOneWidget);
        expect(find.byType(DropdownButtonFormField<int>), findsNothing);
        expect(find.byType(CalendarDatePicker), findsNothing);
        final loc = MaterialLocalizations.of(tester.element(picker));
        expect(find.byTooltip(loc.nextMonthTooltip), findsOneWidget);
        expect(find.byTooltip(loc.previousMonthTooltip), findsOneWidget);
        await calendarPeriod(tester, lang == 'en' ? 'Year' : 'Año', 2028);
        await calendarPeriod(tester, lang == 'en' ? 'Month' : 'Mes', 2);
        expect(
          find.byKey(const ValueKey('calendar-grid-2028-2')),
          findsOneWidget,
        );
        expect(
          find.text(DateFormat.yMMMM(lang).format(DateTime(2028, 2))),
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
  for (final lang in ['en', 'es']) {
    testWidgets(
      'ASAP is integrated in the correct day in Today Week Month $lang',
      (tester) async {
        final repo = _Repo(includeAsap: true);
        await _mount(tester, repo, lang: lang);
        for (final view in ['Today', 'Week', 'Month']) {
          await upcomingTap(tester, 'calendar-view-$view');
          expect(find.text('Needs pickup time'), findsNothing);
          expect(find.text('Requiere hora de recogida'), findsNothing);
          expect(find.text('ASAP'), findsOneWidget);
          expect(find.text('ORD-asap'), findsOneWidget);
          expect(
            find.text(lang == 'en' ? '5 orders' : '5 órdenes'),
            findsOneWidget,
          );
          expect(find.byType(OrderPreviewCard), findsNWidgets(5));
          expect(find.byType(OrderPreviewAction), findsNothing);
        }
        final day = tester
            .widget<CalendarMonthGrid>(find.byType(CalendarMonthGrid))
            .selectedDay;
        tester
            .widget<CalendarMonthGrid>(find.byType(CalendarMonthGrid))
            .onDateChanged(DateTime(day.year, day.month, day.day + 1));
        await tester.pumpAndSettle();
        expect(find.text('ORD-asap'), findsNothing);
        expect(find.text(lang == 'en' ? '1 order' : '1 orden'), findsOneWidget);
        await upcomingTap(tester, 'calendar-view-Week');
        expect(find.text('ORD-asap'), findsNothing);
        await upcomingTap(tester, 'calendar-view-Today');
        await _search(tester, 'ASAP Customer');
        expect(find.text('ORD-asap'), findsOneWidget);
        expect(find.text(lang == 'en' ? '1 order' : '1 orden'), findsOneWidget);
        expect(repo.calls, 1);
      },
    );
  }
  testWidgets('Today has no KPI cards and retains planning cards and filters', (
    tester,
  ) async {
    final repo = _Repo();
    await _mount(tester, repo);
    expect(find.byKey(const Key('calendar-today-kpi')), findsNothing);
    expect(find.byKey(const Key('calendar-revenue-kpi')), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('calendar-view-Today')))
          .style!
          .backgroundColor!
          .resolve({}),
      PelinesColors.brandPrimary,
    );
    expect(find.byType(CalendarMonthGrid), findsNothing);
    expect(find.byKey(const Key('todo-board-scroll')), findsNothing);
    expect(find.byType(OrderPreviewAction), findsNothing);
    expect(find.text('Print ticket'), findsNothing);
    expect(find.text('View Order Details'), findsNWidgets(4));
    expect(find.byType(PelinesLocationContext), findsOneWidget);
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
              .widget<TextButton>(find.byKey(const Key('calendar-view-Week')))
              .style!
              .backgroundColor!
              .resolve({}),
          PelinesColors.brandPrimary,
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
        final sort = find.byKey(const Key('calendar-sort'));
        final filters = find.byKey(const Key('calendar-filter-button'));
        expect(
          tester.getSize(sort).width,
          closeTo(tester.getSize(filters).width, .01),
        );
        for (final button in [sort, filters]) {
          expect(
            tester.widget<OutlinedButton>(button).style!.shape!.resolve({}),
            isA<StadiumBorder>(),
          );
        }
        if (size.$1 - 32 >= 320 * size.$2) {
          expect(tester.getRect(sort).top, tester.getRect(filters).top);
        } else {
          expect(
            tester.getRect(filters).top,
            greaterThanOrEqualTo(tester.getRect(sort).bottom),
          );
        }
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

class _CompactMonthRepo extends _Repo {
  _CompactMonthRepo() : super(includeAsap: true);
  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async => [
    for (final order in await super.getOrders(
      locationId: locationId,
      status: status,
    ))
      OrderSummary(
        id: order.id,
        orderNumber: order.orderNumber,
        locationId: order.locationId,
        orderType: order.orderType,
        status: order.status,
        rawStatus: order.rawStatus,
        paymentStatus: order.paymentStatus,
        fulfillmentType: order.fulfillmentType,
        contactName: order.contactName,
        createdAt: order.createdAt,
        scheduledFor: order.scheduledFor,
        eventName: order.eventName,
        itemCount: 3,
        totalCents: order.totalCents,
      ),
  ];
  @override
  Future<OrderDetail> getOrderById(String id) async => OrderDetail.fromJson({
    ...orderJson(id: id, locationId: 'A'),
    'source': 'ios',
    'items': [
      {
        'id': 'first',
        'productName': 'Taco tray with a long product name',
        'unitPriceCents': 1000,
        'quantity': 2,
        'lineTotalCents': 2200,
        'notes': 'No onions',
        'modifiers': [
          {
            'id': 'extra',
            'groupName': 'Extras',
            'optionName': 'Guacamole',
            'priceDeltaCents': 200,
          },
        ],
      },
      {
        'id': 'second',
        'productName': 'Refreshments',
        'unitPriceCents': 500,
        'quantity': 1,
        'lineTotalCents': 500,
        'modifiers': [],
      },
    ],
  });
}
