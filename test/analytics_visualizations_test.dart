import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/features/analytics/application/analytics_calculator.dart';
import 'package:pelines_admin_app/features/analytics/application/analytics_visualization_data.dart';
import 'package:pelines_admin_app/features/analytics/data/analytics_repository.dart';
import 'package:pelines_admin_app/features/analytics/models/analytics_date_range.dart';
import 'package:pelines_admin_app/features/analytics/models/analytics_order.dart';
import 'package:pelines_admin_app/features/analytics/models/analytics_result.dart';
import 'package:pelines_admin_app/features/analytics/presentation/analytics_visualizations.dart';

import 'order_test_data.dart';

AnalyticsOrder row({
  String at = '2026-03-09T18:00:00Z',
  String status = 'delivered',
  String payment = 'paid',
  String type = 'online',
  String fulfillment = 'pickup',
  int total = 1000,
  int qty = 1,
  String product = 'Taco',
  String id = 'p',
  int line = 600,
}) => AnalyticsOrder.fromJson(
  orderJson(
      status: status,
      payment: payment,
      locationId: 'a',
      fulfillment: fulfillment,
    )
    ..['createdAt'] = at
    ..['orderType'] = type
    ..['totalCents'] = total
    ..['items'] = [
      {
        'id': 'line',
        'productId': id,
        'productName': product,
        'quantity': qty,
        'unitPriceCents': 600,
        'lineTotalCents': line,
        'modifiers': [],
      },
    ],
);

AnalyticsDataset data(List<AnalyticsOrder> orders) =>
    AnalyticsDataset(locationId: 'a', orders: orders);
AnalyticsDateRange day() =>
    AnalyticsDateRange.custom(DateTime(2026, 3, 9), DateTime(2026, 3, 9));
AnalyticsResult result(AnalyticsDataset dataset, AnalyticsDateRange range) =>
    const AnalyticsCalculator().calculate(
      dataset.orders,
      locationId: 'a',
      range: range,
    );

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  String locale = 'en',
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
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
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('Today aggregates actual Pacific hours across both DST transitions', () {
    for (final fixture in [
      (
        '2026-03-08T20:00:00Z',
        '2026-03-08T09:30:00Z',
        '2026-03-08T10:30:00Z',
        23,
      ),
      (
        '2026-11-01T20:00:00Z',
        '2026-11-01T08:30:00Z',
        '2026-11-01T09:30:00Z',
        25,
      ),
    ]) {
      final now = DateTime.parse(fixture.$1);
      final range = AnalyticsDateRange.preset(
        AnalyticsDatePreset.today,
        now: now,
      );
      final dataset = data([
        row(at: fixture.$2),
        row(at: fixture.$3, total: 2000),
        row(at: fixture.$3, payment: 'refunded'),
      ]);
      final series = analyticsSalesSeries(
        dataset,
        result(dataset, range).current,
        now: now,
      );
      expect(series.length, fixture.$4);
      expect(
        series.where((p) => (p.salesCents ?? 0) > 0).map((p) => p.salesCents),
        [1000, 2000],
      );
      expect(series.last.salesCents, isNull); // Future hours aren't zero sales.
      if (fixture.$4 == 25) {
        expect(series[1].start.hour, 1);
        expect(series[2].start.hour, 1);
        expect(
          series[1].start.timeZoneOffset,
          isNot(series[2].start.timeZoneOffset),
        );
      }
    }
  });

  test('7/30/90 and single-day Custom remain daily', () {
    for (final preset in [
      AnalyticsDatePreset.last7Days,
      AnalyticsDatePreset.last30Days,
      AnalyticsDatePreset.last90Days,
    ]) {
      final range = AnalyticsDateRange.preset(
        preset,
        now: DateTime.utc(2026, 3, 9, 20),
      );
      final dataset = data([row()]);
      final series = analyticsSalesSeries(
        dataset,
        result(dataset, range).current,
        now: DateTime.utc(2026, 3, 10),
      );
      expect(series.length, range.dayCount);
      expect(series.last.salesCents, 1000);
    }
    final dataset = data([row()]);
    expect(
      analyticsSalesSeries(dataset, result(dataset, day()).current).length,
      1,
    );
  });

  test(
    'truncated boundary and earlier days are null; safe later zero remains',
    () {
      final dataset = data(List.generate(2000, (_) => row()));
      final range = AnalyticsDateRange.custom(
        DateTime(2026, 3, 8),
        DateTime(2026, 3, 10),
      );
      final computed = result(dataset, range);
      final series = analyticsSalesSeries(dataset, computed.current);
      expect(series.map((p) => p.salesCents), [null, null, 0]);
      expect(analyticsComparisonIsCovered(dataset, computed), isFalse);
      expect(analyticsRangeIsCovered(dataset, day()), isFalse);
      final safe = AnalyticsDateRange.custom(
        DateTime(2026, 3, 11),
        DateTime(2026, 3, 11),
      );
      expect(
        analyticsComparisonIsCovered(dataset, result(dataset, safe)),
        isTrue,
      );
    },
  );

  test('hourly truncation suppresses the partially loaded boundary hour', () {
    final dataset = data(
      List.generate(2000, (_) => row(at: '2026-03-09T18:30:00Z')),
    );
    final range = AnalyticsDateRange.preset(
      AnalyticsDatePreset.today,
      now: DateTime.utc(2026, 3, 9, 22),
    );
    final series = analyticsSalesSeries(
      dataset,
      result(dataset, range).current,
      now: DateTime.utc(2026, 3, 9, 22),
    );
    expect(series[11].salesCents, isNull);
    expect(series[12].salesCents, 0);
  });

  testWidgets('chart uses USD data, and correct empty states', (tester) async {
    final dataset = data([row()]);
    await mount(
      tester,
      AnalyticsSalesChart(
        dataset: dataset,
        period: result(dataset, day()).current,
      ),
    );
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots.single.y, 10);
    final tooltip = chart.data.lineTouchData.touchTooltipData.getTooltipItems([
      LineBarSpot(
        chart.data.lineBarsData.single,
        0,
        chart.data.lineBarsData.single.spots.single,
      ),
    ]).single!;
    expect(tooltip.text, contains('US\$10.00'));
    final empty = data([]);
    await mount(
      tester,
      AnalyticsSalesChart(dataset: empty, period: result(empty, day()).current),
    );
    expect(find.byType(LineChart), findsNothing);
    expect(
      find.text('No sales in the loaded data for this period.'),
      findsOneWidget,
    );
    final truncated = data(List.generate(2000, (_) => row()));
    await mount(
      tester,
      AnalyticsSalesChart(
        dataset: truncated,
        period: result(truncated, day()).current,
      ),
    );
    expect(find.byType(LineChart), findsNothing);
    expect(
      find.text('No reliable chart data for this period.'),
      findsOneWidget,
    );
  });

  testWidgets('chart gaps are null spots, never synthetic zero history', (
    tester,
  ) async {
    final dataset = data([
      ...List.generate(1999, (_) => row()),
      row(at: '2026-03-10T18:00:00Z'),
    ]);
    final range = AnalyticsDateRange.custom(
      DateTime(2026, 3, 8),
      DateTime(2026, 3, 10),
    );
    await mount(
      tester,
      AnalyticsSalesChart(
        dataset: dataset,
        period: result(dataset, range).current,
      ),
    );
    final spots = tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .lineBarsData
        .single
        .spots;
    expect(spots[0], FlSpot.nullSpot);
    expect(spots[1], FlSpot.nullSpot);
    expect(spots[2].y, 10);
  });

  testWidgets('Top 5 quantity order and line sales independent of Sales KPI', (
    tester,
  ) async {
    final dataset = data(
      List.generate(
        6,
        (i) => row(
          id: '$i',
          product: 'Product $i',
          qty: i + 1,
          line: 600 * (i + 1),
        ),
      ),
    );
    final computed = result(dataset, day());
    await mount(
      tester,
      AnalyticsTopProducts(products: computed.current.products),
    );
    expect(find.text('Product 0'), findsNothing);
    for (var i = 1; i < 6; i++) {
      expect(find.text('Product $i'), findsOneWidget);
      expect(find.text('Quantity: ${i + 1}'), findsOneWidget);
    }
    expect(
      tester.getTopLeft(find.text('Product 5')).dy,
      lessThan(tester.getTopLeft(find.text('Product 4')).dy),
    );
    expect(find.text('Product Sales: US\$36.00'), findsOneWidget);
    expect(computed.current.salesCents, 6000);
  });

  testWidgets('types, fulfillment and operational status use agreed cohorts', (
    tester,
  ) async {
    final dataset = data([
      row(),
      row(
        type: 'catering',
        fulfillment: 'delivery',
        status: 'ready',
        total: 2000,
      ),
      row(payment: 'refunded', status: 'cancelled'),
      row(payment: 'failed', status: 'cancelled'),
    ]);
    await mount(
      tester,
      AnalyticsVisualizations(dataset: dataset, result: result(dataset, day())),
    );
    final type = find.byKey(const Key('analytics-section-Order Type'));
    expect(
      find.descendant(of: type, matching: find.text('Orders: 2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: type, matching: find.text('Sales: US\$10.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: type, matching: find.text('Sales: US\$20.00')),
      findsOneWidget,
    );
    final fulfillment = find.byKey(const Key('analytics-section-Fulfillment'));
    expect(
      find.descendant(of: fulfillment, matching: find.text('Orders: 2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: fulfillment, matching: find.text('Orders: 1')),
      findsOneWidget,
    );
    final status = find.byKey(const Key('analytics-section-Order Status'));
    expect(
      find.descendant(of: status, matching: find.text('1')),
      findsNWidgets(3),
    );
    expect(find.text('33.3%'), findsOneWidget);
    for (final name in [
      'Completed',
      'Cancelled',
      'In Progress',
      'Cancellation Rate',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('comparison percent, zero denominator and suppressed coverage', (
    tester,
  ) async {
    await mount(
      tester,
      const AnalyticsComparison(
        metric: MetricComparison(1500, 1000),
        covered: true,
      ),
    );
    expect(find.text('+50.0% vs previous period'), findsOneWidget);
    await mount(
      tester,
      const AnalyticsComparison(
        metric: MetricComparison(1500, 0),
        covered: true,
      ),
    );
    expect(find.text('— vs previous period'), findsOneWidget);
    await mount(
      tester,
      const AnalyticsComparison(
        metric: MetricComparison(1500, 1000),
        covered: false,
      ),
    );
    expect(find.text('— vs previous period'), findsOneWidget);
    expect(find.textContaining('50.0%'), findsNothing);
  });

  for (final width in [320.0, 1100.0]) {
    testWidgets('Spanish visualizations and responsive groups at $width', (
      tester,
    ) async {
      final dataset = data([row(product: 'Backend Taco')]);
      await mount(
        tester,
        AnalyticsVisualizations(
          dataset: dataset,
          result: result(dataset, day()),
        ),
        width: width,
        locale: 'es',
      );
      for (final label in [
        'Ventas a lo largo del tiempo',
        'Productos más vendidos',
        'Backend Taco',
        'Tasa de cancelación',
        'Tipo de pedido',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      final a = tester.getTopLeft(
        find.byKey(const Key('analytics-section-Order Type')),
      );
      final b = tester.getTopLeft(
        find.byKey(const Key('analytics-section-Fulfillment')),
      );
      expect(b.dy, width == 1100 ? a.dy : greaterThan(a.dy));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('large text phone has no overflow', (tester) async {
    final dataset = data([row()]);
    await mount(
      tester,
      AnalyticsVisualizations(dataset: dataset, result: result(dataset, day())),
      width: 320,
      locale: 'es',
      scale: 2,
    );
    expect(tester.takeException(), isNull);
  });
}
