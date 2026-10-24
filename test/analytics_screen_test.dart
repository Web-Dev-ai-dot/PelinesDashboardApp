import 'package:pelines_admin_app/features/analytics/presentation/analytics_date_range_sheet.dart';
import 'package:pelines_admin_app/features/orders/presentation/upcoming_date_range.dart';
import 'package:pelines_admin_app/features/analytics/models/analytics_date_range.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/features/locations/presentation/pelines_location_context.dart';

import 'dart:async';

import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/features/analytics/data/analytics_repository.dart';
import 'package:pelines_admin_app/features/analytics/models/analytics_order.dart';
import 'package:pelines_admin_app/features/analytics/providers/analytics_providers.dart';
import 'package:pelines_admin_app/features/analytics/presentation/analytics_screen.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_providers.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/core/time/pelines_time.dart';

import 'analytics_providers_test.dart'
    show FakeAuth, FakeLocation, makeLocation;
import 'order_test_data.dart';

class ScreenRepository implements AnalyticsRepository {
  final requests = <Completer<AnalyticsDataset>>[];
  final locations = <String>[];
  @override
  Future<AnalyticsDataset> getDataset({required String locationId}) {
    locations.add(locationId);
    final request = Completer<AnalyticsDataset>();
    requests.add(request);
    return request.future;
  }
}

class ScreenLocation extends FakeLocation {
  @override
  Future<void> select(Location location) async => setLocation(location.id);
}

class ScreenLocations extends LocationsController {
  @override
  Future<List<Location>> build() async => [
    makeLocation('a'),
    makeLocation('b'),
  ];
}

AnalyticsDataset sample({
  int count = 1,
  String location = 'a',
  String payment = 'paid',
}) => AnalyticsDataset(
  locationId: location,
  orders: List.generate(
    count,
    (i) => AnalyticsOrder.fromJson(
      orderJson(id: '$i', locationId: location, payment: payment)
        ..['createdAt'] = DateTime.now().toUtc().toIso8601String()
        ..['items'] = [
          {
            'id': 'line',
            'productId': 'p',
            'productName': 'Backend Taco',
            'unitPriceCents': 500,
            'quantity': 2,
            'lineTotalCents': 1000,
            'modifiers': [],
          },
        ],
    ),
  ),
);

Future<void> rangeTap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void expectRangePresentation(
  WidgetTester tester,
  String key,
  double width, {
  required bool chevron,
}) {
  final button = find.byKey(Key(key));
  final fieldFinder = find
      .ancestor(of: button, matching: find.byType(AnalyticsDateRangeField))
      .first;
  final field = tester.widget<AnalyticsDateRangeField>(fieldFinder);
  final label = find.descendant(
    of: fieldFinder,
    matching: find.text(field.label),
  );
  expect(label, findsOneWidget);
  expect(
    find.descendant(of: button, matching: find.text(field.label)),
    findsNothing,
  );
  expect(
    find.descendant(of: button, matching: find.text(field.dates)),
    findsOneWidget,
  );
  expect(field.dates, isNot(contains('Pacific')));
  expect(tester.getRect(label).bottom, lessThan(tester.getRect(button).top));
  expect(tester.getSize(button).width, closeTo(width, .1));
  expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
  expect(
    find.descendant(of: button, matching: find.byIcon(Icons.expand_more)),
    chevron ? findsOneWidget : findsNothing,
  );
  final style = tester.widget<OutlinedButton>(button).style!;
  expect(style.side!.resolve({})!.color, PelinesColors.border);
  expect(style.shape!.resolve({}), isA<StadiumBorder>());
}

void main() {
  late ScreenRepository repository;
  late ProviderContainer container;
  Future<void> mount(
    WidgetTester tester, {
    String language = 'en',
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repository = ScreenRepository();
    container = ProviderContainer(
      overrides: [
        analyticsRepositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith(FakeAuth.new),
        currentLocationProvider.overrideWith(ScreenLocation.new),
        locationsProvider.overrideWith(ScreenLocations.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          locale: Locale(language),
          supportedLocales: AdminLocalizations.supportedLocales,
          localizationsDelegates: const [
            AdminLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const AnalyticsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  for (final language in ['en', 'es']) {
    for (final width in [320.0, 768.0]) {
      testWidgets(
        'range panel drafts presets reset cancel and custom $language/$width/2x',
        (tester) async {
          await mount(tester, language: language, width: width, scale: 2);
          repository.requests.single.complete(sample());
          await tester.pumpAndSettle();
          expectRangePresentation(
            tester,
            'analytics-date-range',
            width - 32,
            chevron: true,
          );
          final initial = container.read(analyticsRangeProvider);
          await rangeTap(tester, 'analytics-date-range');
          expect(
            tester
                .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
                .groupValue,
            'last30Days',
          );
          for (final preset in [
            'today',
            'last7Days',
            'last30Days',
            'last90Days',
          ]) {
            await rangeTap(tester, 'analytics-$preset');
            expect(container.read(analyticsRangeProvider), same(initial));
            expect(repository.requests.length, 1);
          }
          await rangeTap(tester, 'analytics-range-cancel');
          expect(container.read(analyticsRangeProvider), same(initial));
          await rangeTap(tester, 'analytics-date-range');
          await rangeTap(tester, 'analytics-last7Days');
          await rangeTap(tester, 'analytics-range-apply');
          expect(container.read(analyticsRangeProvider).dayCount, 7);
          await rangeTap(tester, 'analytics-date-range');
          expect(
            tester
                .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
                .groupValue,
            'last7Days',
          );
          await rangeTap(tester, 'analytics-custom');
          expectRangePresentation(
            tester,
            'analytics-select-range',
            (width < 640 ? width : 640) - 32,
            chevron: false,
          );
          await rangeTap(tester, 'analytics-select-range');
          UpcomingRangeCalendar calendar() =>
              tester.widget<UpcomingRangeCalendar>(
                find.byType(UpcomingRangeCalendar),
              );
          final today = calendar().currentDate;
          final start = today.subtract(const Duration(days: 5));
          calendar().onDateChanged(start);
          await tester.pumpAndSettle();
          calendar().onDateChanged(today);
          await tester.pumpAndSettle();
          await rangeTap(tester, 'analytics-calendar-cancel');
          await rangeTap(tester, 'analytics-select-range');
          expect(
            calendar().from,
            container.read(analyticsRangeProvider).startDate,
          );
          calendar().onDateChanged(start);
          await tester.pumpAndSettle();
          calendar().onDateChanged(today);
          await tester.pumpAndSettle();
          await rangeTap(tester, 'analytics-calendar-confirm');
          expect(container.read(analyticsRangeProvider).dayCount, 7);
          await rangeTap(tester, 'analytics-range-apply');
          expect(container.read(analyticsRangeProvider).dayCount, 6);
          expect(container.read(analyticsRangeProvider).preset, isNull);
          await rangeTap(tester, 'analytics-date-range');
          expect(
            tester
                .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
                .groupValue,
            'custom',
          );
          await rangeTap(tester, 'analytics-range-reset');
          expect(container.read(analyticsRangeProvider).dayCount, 6);
          await rangeTap(tester, 'analytics-range-cancel');
          expect(container.read(analyticsRangeProvider).dayCount, 6);
          await rangeTap(tester, 'analytics-date-range');
          await rangeTap(tester, 'analytics-range-reset');
          await rangeTap(tester, 'analytics-range-apply');
          expect(
            container.read(analyticsRangeProvider).preset,
            AnalyticsDatePreset.last30Days,
          );
          expect(repository.requests.length, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final viewport in [
    (390.0, 1.0, 2),
    (768.0, 1.0, 2),
    (1400.0, 1.0, 4),
    (320.0, 2.0, 2),
  ]) {
    for (final lang in ['en', 'es']) {
      testWidgets(
        'web analytics hierarchy ${viewport.$1} ${viewport.$2} $lang',
        (tester) async {
          await mount(
            tester,
            width: viewport.$1,
            scale: viewport.$2,
            language: lang,
          );
          repository.requests.single.complete(sample());
          await tester.pumpAndSettle();
          expectRangePresentation(
            tester,
            'analytics-date-range',
            viewport.$1 - 32,
            chevron: true,
          );
          final export = find.byKey(const Key('analytics-export'));
          final refresh = find.descendant(
            of: find.byKey(const Key('analytics-refresh')),
            matching: find.byType(OutlinedButton),
          );
          final primary = tester.widget<FilledButton>(export);
          final secondary = tester.widget<OutlinedButton>(refresh);
          expect(primary.onPressed, isNotNull);
          expect(secondary.onPressed, isNotNull);
          expect(
            primary.style!.backgroundColor!.resolve({}),
            PelinesColors.brandPrimary,
          );
          expect(
            secondary.style!.foregroundColor!.resolve({}),
            PelinesColors.textPrimary,
          );
          expect(tester.getSize(export).height, greaterThanOrEqualTo(48));
          expect(tester.getSize(refresh).height, greaterThanOrEqualTo(48));
          expect(
            find.descendant(of: export, matching: find.byIcon(Icons.ios_share)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: refresh, matching: find.byIcon(Icons.refresh)),
            findsOneWidget,
          );
          final titleRect = tester.getRect(
            find.byKey(const Key('analytics-title')),
          );
          expect(
            tester.getRect(refresh).center.dy,
            closeTo(titleRect.center.dy, 1),
          );
          expect(tester.getRect(refresh).left, greaterThan(titleRect.left));
          expect(
            tester.getRect(find.byType(PelinesLocationContext)).top,
            greaterThanOrEqualTo(titleRect.bottom),
          );
          final exportRect = tester.getRect(export);
          final refreshRect = tester.getRect(refresh);
          expect(refreshRect.bottom, lessThan(exportRect.top));
          final header = find.byKey(const Key('persistent-section-header'));
          expect(
            find.descendant(of: header, matching: refresh),
            findsOneWidget,
          );
          final status = find.byKey(
            const Key('analytics-section-Order Status'),
          );
          final statusTexts = find.descendant(
            of: status,
            matching: find.byType(Text),
          );
          final left = tester.getTopLeft(statusTexts.first).dx;
          for (final element in statusTexts.evaluate()) {
            expect(
              tester.getTopLeft(find.byWidget(element.widget)).dx,
              closeTo(left, 0.01),
            );
          }
          expect(find.byKey(const Key('analytics-filter-bar')), findsOneWidget);
          expect(find.byType(PelinesLocationContext), findsOneWidget);
          expect(
            find.byKey(ValueKey('analytics-kpi-columns-${viewport.$3}')),
            findsOneWidget,
          );
          final sections = lang == 'es'
              ? [
                  'Resumen de ventas',
                  'Volumen de pedidos',
                  'Productos',
                  'Operaciones',
                ]
              : ['Sales Overview', 'Order Volume', 'Products', 'Operations'];
          for (final title in sections) {
            expect(find.text(title), findsOneWidget);
          }
          for (var i = 1; i < sections.length; i++) {
            expect(
              tester.getTopLeft(find.text(sections[i])).dy,
              greaterThan(tester.getTopLeft(find.text(sections[i - 1])).dy),
            );
          }
          expect(find.text('Backend Taco'), findsOneWidget);
          expect(find.text('#1'), findsOneWidget);
          expect(
            find.byKey(const Key('analytics-sales-chart')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('analytics-cancellation-comparison')),
            findsOneWidget,
          );
          for (var i = 0; i < 6; i++) {
            await tester.drag(
              find.byType(SingleChildScrollView).first,
              const Offset(0, -650),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
  testWidgets('loading then four KPIs, local range change and refresh', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Loading analytics...'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(
              of: find.byKey(const Key('analytics-refresh')),
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('analytics-export')))
          .onPressed,
      isNull,
    );
    repository.requests.single.complete(sample());
    await tester.pumpAndSettle();
    for (final label in ['Sales', 'Orders', 'Average Order', 'Items Sold']) {
      expect(find.byKey(Key('analytics-kpi-$label')), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const Key('analytics-kpi-columns-2')),
        matching: find.text('US\$11.00'),
      ),
      findsNWidgets(2),
    );
    // The page and operational cohort both identify the ongoing period.
    expect(find.text('This period is still in progress.'), findsNWidgets(2));
    await rangeTap(tester, 'analytics-date-range');
    await rangeTap(tester, 'analytics-last7Days');
    await rangeTap(tester, 'analytics-range-apply');
    await tester.pumpAndSettle();
    expect(repository.requests.length, 1);
    expect(container.read(analyticsRangeProvider).dayCount, 7);
    await tester.tap(find.byKey(const Key('analytics-refresh')));
    await tester.pump();
    expect(repository.requests.length, 2);
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(
              of: find.byKey(const Key('analytics-refresh')),
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('analytics-export')))
          .onPressed,
      isNull,
    );
    repository.requests.last.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('analytics-refresh-error')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('analytics-kpi-columns-2')),
        matching: find.text('US\$11.00'),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('initial error offers retry without fake zeros', (tester) async {
    await mount(tester);
    repository.requests.single.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Analytics could not be loaded.'), findsOneWidget);
    expect(find.byKey(const Key('analytics-kpi-Sales')), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    repository.requests.last.complete(sample());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('analytics-kpi-Sales')), findsOneWidget);
  });

  testWidgets('empty displays absent average', (tester) async {
    await mount(tester);
    repository.requests.single.complete(sample(count: 0));
    await tester.pumpAndSettle();
    expect(find.text('No eligible orders in this period.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('analytics-kpi-Average Order')),
        matching: find.text('—'),
      ),
      // Both the current and the separately fitted previous amount are absent.
      findsNWidgets(2),
    );
  });

  testWidgets('Spanish KPIs and truncation metadata', (tester) async {
    await mount(tester, language: 'es', width: 1100);
    repository.requests.single.complete(sample(count: 2000));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Actualizar'), findsOneWidget);
    for (final text in [
      'Analíticas',
      'Ventas',
      'Órdenes',
      'Pedido promedio',
      'Artículos vendidos',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.textContaining('Pedido más antiguo cargado'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('analytics-truncation')),
        matching: find.text('Los datos pueden estar incompletos'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Pedidos cargados'), findsOneWidget);
    expect(
      find.byKey(const Key('analytics-comparison-unavailable')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('analytics-kpi-columns-2')),
        matching: find.text('— vs. período anterior'),
      ),
      findsNWidgets(4),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('KPI comparisons use actual previous-period data', (
    tester,
  ) async {
    await mount(tester);
    final now = PelinesTime.now();
    final previous = AnalyticsOrder.fromJson(
      orderJson(locationId: 'a')
        ..['createdAt'] = DateTime.utc(
          now.year,
          now.month,
          now.day - 1,
          20,
        ).toIso8601String()
        ..['totalCents'] = 550
        ..['items'] = [
          {
            'id': 'line',
            'productId': 'p',
            'productName': 'Backend Taco',
            'unitPriceCents': 500,
            'quantity': 1,
            'lineTotalCents': 500,
            'modifiers': [],
          },
        ],
    );
    repository.requests.single.complete(
      AnalyticsDataset(locationId: 'a', orders: [...sample().orders, previous]),
    );
    await tester.pumpAndSettle();
    await rangeTap(tester, 'analytics-date-range');
    await rangeTap(tester, 'analytics-today');
    await rangeTap(tester, 'analytics-range-apply');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('analytics-kpi-columns-2')),
        matching: find.text('+100.0% vs previous period'),
      ),
      findsNWidgets(3),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('analytics-kpi-columns-2')),
        matching: find.text('0.0% vs previous period'),
      ),
      findsOneWidget,
    );
    expect(repository.requests.length, 1);
  });

  for (final width in [320.0, 390.0, 768.0, 1400.0]) {
    testWidgets('responsive columns at $width', (tester) async {
      await mount(tester, width: width);
      repository.requests.single.complete(sample());
      await tester.pumpAndSettle();
      final sales = tester.getTopLeft(
        find.byKey(const Key('analytics-kpi-Sales')),
      );
      final orders = tester.getTopLeft(
        find.byKey(const Key('analytics-kpi-Orders')),
      );
      final average = tester.getTopLeft(
        find.byKey(const Key('analytics-kpi-Average Order')),
      );
      expect(orders.dy, sales.dy);
      expect(orders.dx, greaterThan(sales.dx));
      expect(average.dy, width == 1400 ? sales.dy : greaterThan(sales.dy));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('large Spanish text fits narrow phone', (tester) async {
    await mount(tester, width: 320, scale: 2, language: 'es');
    repository.requests.single.complete(sample());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('location picker changes dataset', (tester) async {
    await mount(tester);
    repository.requests.single.complete(sample());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('location-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('b'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(repository.locations, ['a', 'b']);
    repository.requests.last.complete(sample(location: 'b'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PelinesLocationContext),
        matching: find.text('b'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Custom calendar confirms same-day draft then Apply updates all analytics without request',
    (tester) async {
      await mount(tester);
      repository.requests.single.complete(sample());
      await tester.pumpAndSettle();
      final before = container.read(analyticsRangeProvider);
      await rangeTap(tester, 'analytics-date-range');
      await rangeTap(tester, 'analytics-custom');
      await rangeTap(tester, 'analytics-select-range');
      expect(find.byType(SwitchListTile), findsNothing);
      final picker = tester.widget<UpcomingRangeCalendar>(
        find.byType(UpcomingRangeCalendar),
      );
      final now = PelinesTime.now();
      final day = DateTime.utc(now.year, now.month, now.day);
      expect(picker.lastDate, day);
      expect(picker.firstDate, DateTime.utc(2000));
      picker.onDateChanged(day);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('analytics-calendar-confirm')),
            )
            .onPressed,
        isNull,
      );
      tester
          .widget<UpcomingRangeCalendar>(find.byType(UpcomingRangeCalendar))
          .onDateChanged(day);
      await tester.pumpAndSettle();
      await rangeTap(tester, 'analytics-calendar-confirm');
      expect(container.read(analyticsRangeProvider), same(before));
      expect(repository.requests.length, 1);
      await rangeTap(tester, 'analytics-range-apply');
      expect(container.read(analyticsRangeProvider).dayCount, 1);
      expect(container.read(analyticsRangeProvider).preset, isNull);
      expect(
        container.read(analyticsResultProvider).value!.current.range.startDate,
        day,
      );
      expect(repository.requests.length, 1);
    },
  );
}
