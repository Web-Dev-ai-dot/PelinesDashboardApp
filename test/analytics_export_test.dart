import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/features/analytics/application/analytics_export.dart';
import 'package:pelines_admin_app/features/analytics/application/analytics_calculator.dart';
import 'package:pelines_admin_app/features/analytics/data/analytics_repository.dart';
import 'package:pelines_admin_app/features/analytics/models/analytics_date_range.dart';
import 'package:pelines_admin_app/features/analytics/providers/analytics_providers.dart';
import 'package:pelines_admin_app/features/analytics/presentation/analytics_export_action.dart';
import 'package:pelines_admin_app/features/analytics/presentation/analytics_filters.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';

import 'analytics_test.dart' show order, item;
import 'analytics_providers_test.dart' show FakeLocation;

final range = AnalyticsDateRange.custom(
  DateTime.utc(2026, 3, 9),
  DateTime.utc(2026, 3, 9),
);
AnalyticsDataset data() => AnalyticsDataset(
  locationId: 'a',
  orders: [
    order(
      cents: 1001,
      status: OrderStatus.pending,
      items: [item('p', 'Taco, "niño"\ntray', 2, 1001)],
    ),
    order(cents: 2002, type: OrderType.catering, status: OrderStatus.ready),
    order(payment: PaymentStatus.refunded, status: OrderStatus.cancelled),
    order(payment: PaymentStatus.unpaid, cents: 999999),
    order(at: '2026-03-09T06:59:00Z', cents: 500), // March 8 Pacific
  ],
);
AnalyticsCsv csv(
  AnalyticsDataset dataset,
  AnalyticsReport report, {
  String location = 'a',
  String slug = 'a/../:é',
}) => buildAnalyticsCsv(
  report: report,
  dataset: dataset,
  result: const AnalyticsCalculator().calculate(
    dataset.orders,
    locationId: 'a',
    range: range,
  ),
  locationId: location,
  locationName: 'Pelines, "Niño"\nLocation',
  locationSlug: slug,
);

class ExportDataset extends AnalyticsDatasetController {
  @override
  AsyncValue<AnalyticsDatasetState?> build() =>
      AsyncData(AnalyticsDatasetState(dataset: data()));
  void replace(AsyncValue<AnalyticsDatasetState?> next) => state = next;
}

void main() {
  test(
    'Revenue uses canonical cohort, cents, top products and CSV escaping',
    () {
      final file = csv(data(), AnalyticsReport.revenue);
      final text = utf8.decode(file.bytes);
      expect(file.bytes.take(3), [239, 187, 191]);
      // UTF-8 decoder consumes the BOM; bytes above verify it on disk.
      expect(text, startsWith('Section,Metric,Value,Unit\r\n'));
      expect(text, contains('Total revenue,30.03,USD\r\n'));
      expect(text, contains('Average order value,15.02,USD'));
      expect(text, contains('Current,Order count,3,orders'));
      expect(text, contains('Previous,Total revenue,5.00,USD'));
      expect(text, contains('"Taco, ""niño""\ntray"'));
      expect(text, contains('Period start,2026-03-09,date'));
      expect(text, contains('America/Los_Angeles'));
      expect(text, isNot(contains('999999')));
      for (final pii in [
        'Customer',
        'Phone',
        'Email',
        'Internal notes',
        'Card',
        'Order ID',
      ]) {
        expect(text, isNot(contains(pii)));
      }
      expect(file.filename, 'pelines-revenue-a-20260309-20260309.csv');
    },
  );
  test('Operational uses existing KPIs and cancellation denominator', () {
    final text = utf8.decode(csv(data(), AnalyticsReport.operational).bytes);
    for (final row in [
      'Waiting,1,orders',
      'Ready,1,orders',
      'Cancelled,1,orders',
      'Cancellation rate,33.33,percent',
      'Peak Hour,11:00–12:00,Pacific hour',
      'Busiest Day,Monday,Pacific weekday',
    ]) {
      expect(text, contains(row));
    }
  });
  test('scope mismatch rejected; missing comparison blank; current coverage blocks', () {
    expect(
      () => csv(data(), AnalyticsReport.revenue, location: 'other'),
      throwsStateError,
    );
    final truncated = AnalyticsDataset(
      locationId: 'a',
      orders: List.generate(2000, (_) => order(at: '2026-03-08T18:00:00Z')),
    );
    final text = utf8.decode(csv(truncated, AnalyticsReport.revenue).bytes);
    expect(text, contains('Comparison covered,false,boolean'));
    expect(text, contains('Previous,Total revenue,,USD'));
    final incomplete = AnalyticsDataset(
      locationId: 'a',
      orders: List.generate(2000, (_) => order()),
    );
    expect(() => csv(incomplete, AnalyticsReport.revenue), throwsStateError);
    final contaminated = AnalyticsDataset(
      locationId: 'a',
      orders: [order(location: 'b')],
    );
    expect(() => csv(contaminated, AnalyticsReport.revenue), throwsStateError);
  });
  test('empty reports preserve zero vs unavailable and safe filename', () {
    final empty = AnalyticsDataset(locationId: 'a', orders: []);
    final revenue = csv(empty, AnalyticsReport.revenue, slug: '///');
    expect(revenue.filename, 'pelines-revenue-location-20260309-20260309.csv');
    expect(utf8.decode(revenue.bytes), contains('Total revenue,0.00,USD'));
    expect(utf8.decode(revenue.bytes), contains('Average order value,,USD'));
    expect(
      utf8.decode(csv(empty, AnalyticsReport.operational).bytes),
      contains('Peak Hour,,Pacific hour'),
    );
  });

  Future<ProviderContainer> mount(
    WidgetTester tester, {
    String lang = 'en',
    double width = 390,
    Future<ShareResult> Function(ShareParams)? share,
    Future<AnalyticsCsv> Function(AnalyticsCsv Function())? generate,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        currentLocationProvider.overrideWith(FakeLocation.new),
        analyticsDatasetProvider.overrideWith(ExportDataset.new),
        analyticsShareProvider.overrideWithValue(
          share ??
              (_) async => const ShareResult('', ShareResultStatus.dismissed),
        ),
        if (generate != null)
          analyticsCsvGenerationProvider.overrideWithValue(generate),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(analyticsRangeProvider.notifier)
        .selectCustom(range.startDate, range.endDate);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: Locale(lang),
          supportedLocales: AdminLocalizations.supportedLocales,
          localizationsDelegates: const [
            AdminLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [AnalyticsFilters(), AnalyticsExportAction()],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  for (final lang in ['en', 'es']) {
    for (final width in [320.0, 390.0, 768.0, 1400.0]) {
      testWidgets('labels ranges and share responsive $lang $width 2x', (
        tester,
      ) async {
        ShareParams? sent;
        final container = await mount(
          tester,
          lang: lang,
          width: width,
          share: (params) async {
            sent = params;
            return const ShareResult('', ShareResultStatus.dismissed);
          },
        );
        await tap(tester, 'analytics-date-range');
        expect(find.text(lang == 'en' ? 'Today' : 'Hoy'), findsOneWidget);
        expect(
          find.text(lang == 'en' ? 'Custom range' : 'Rango personalizado'),
          findsOneWidget,
        );
        for (final n in [7, 30, 90]) {
          expect(
            find.text(lang == 'en' ? 'Last $n days' : 'Últimos $n días'),
            findsOneWidget,
          );
          await tap(tester, 'analytics-last${n}Days');
          await tap(tester, 'analytics-range-apply');
          expect(container.read(analyticsRangeProvider).dayCount, n);
          if (n != 90) await tap(tester, 'analytics-date-range');
        }
        await tap(tester, 'analytics-export-revenue');
        expect(sent!.files, hasLength(1));
        expect(sent!.fileNameOverrides!.single, startsWith('pelines-revenue-'));
        expect(sent!.sharePositionOrigin!.width, greaterThan(0));
        expect(find.textContaining('Export failed'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final change in ['location', 'period', 'dataset']) {
    testWidgets('scope change during generation prevents sharing: $change', (
      tester,
    ) async {
      final pending = Completer<AnalyticsCsv>();
      var shares = 0;
      final container = await mount(
        tester,
        generate: (_) => pending.future,
        share: (_) async {
          shares++;
          return const ShareResult('', ShareResultStatus.success);
        },
      );
      await tester.tap(find.byKey(const Key('analytics-export-revenue')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      if (change == 'location') {
        (container.read(currentLocationProvider.notifier) as FakeLocation)
            .setLocation('b');
      } else if (change == 'period') {
        container
            .read(analyticsRangeProvider.notifier)
            .selectPreset(AnalyticsDatePreset.today);
      } else {
        (container.read(analyticsDatasetProvider.notifier) as ExportDataset)
            .replace(AsyncData(AnalyticsDatasetState(dataset: data())));
      }
      await tester.pump();
      pending.complete(csv(data(), AnalyticsReport.revenue));
      await tester.pumpAndSettle();
      expect(shares, 0);
      expect(
        find.text('Analytics changed. Please export again.'),
        findsOneWidget,
      );
    });
  }
  testWidgets('three vertical exports expose unavailable Orders honestly', (
    tester,
  ) async {
    await mount(tester);
    final buttons = [
      for (final name in ['orders', 'revenue', 'operational'])
        find.byKey(Key('analytics-export-$name')),
    ];
    expect(tester.widget<OutlinedButton>(buttons.first).onPressed, isNull);
    expect(
      find.text('Orders CSV export is not available in this app.'),
      findsOneWidget,
    );
    for (var i = 1; i < buttons.length; i++) {
      expect(
        tester.getRect(buttons[i]).top,
        greaterThan(tester.getRect(buttons[i - 1]).bottom),
      );
      expect(
        tester.getRect(buttons[i]).width,
        tester.getRect(buttons.first).width,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading stale error incomplete coverage block export', (
    tester,
  ) async {
    final container = await mount(tester);
    final controller =
        container.read(analyticsDatasetProvider.notifier) as ExportDataset;
    for (final state in <AsyncValue<AnalyticsDatasetState?>>[
      const AsyncLoading(),
      AsyncError(Exception('failed'), StackTrace.current),
      AsyncData(
        AnalyticsDatasetState(
          dataset: data(),
          refreshError: Exception('stale'),
        ),
      ),
      AsyncData(AnalyticsDatasetState(dataset: data(), isRefreshing: true)),
      AsyncData(
        AnalyticsDatasetState(
          dataset: AnalyticsDataset(
            locationId: 'a',
            orders: List.generate(2000, (_) => order()),
          ),
        ),
      ),
    ]) {
      controller.replace(state);
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('analytics-export-revenue')),
            )
            .onPressed,
        isNull,
      );
    }
  });
  testWidgets(
    'generation failure and share failure reported; double submit prevented',
    (tester) async {
      var calls = 0;
      final pending = Completer<ShareResult>();
      await mount(
        tester,
        share: (_) {
          calls++;
          return pending.future;
        },
      );
      // Do not pumpAndSettle while the loading spinner is running.
      await tester.tap(find.byKey(const Key('analytics-export-operational')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('analytics-export-revenue')),
            )
            .onPressed,
        isNull,
      );
      pending.completeError(Exception('share failed'));
      await tester.pumpAndSettle();
      expect(find.text('Export failed. Please try again.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(
        tester,
        generate: (_) async => throw Exception('generation failed'),
      );
      await tap(tester, 'analytics-export-revenue');
      expect(find.text('Export failed. Please try again.'), findsOneWidget);
    },
  );
}
