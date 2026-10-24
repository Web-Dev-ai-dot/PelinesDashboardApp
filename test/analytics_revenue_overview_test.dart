import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';
import 'package:pelines_admin_app/features/analytics/application/analytics_calculator.dart';
import 'package:pelines_admin_app/features/analytics/models/analytics_date_range.dart';
import 'package:pelines_admin_app/features/analytics/models/analytics_order.dart';
import 'package:pelines_admin_app/features/analytics/models/analytics_result.dart';
import 'package:pelines_admin_app/features/analytics/presentation/analytics_revenue_overview.dart';

import 'order_test_data.dart';

AnalyticsResult revenueResult({bool huge = false, bool empty = false}) {
  final data = <AnalyticsOrder>[];
  if (!empty) {
    for (final (day, type, cents) in [
      (4, 'online', 10000),
      (4, 'catering', 30000),
      (3, 'online', 20000),
      (3, 'catering', 10000),
    ]) {
      data.add(
        AnalyticsOrder.fromJson({
          ...orderJson(),
          'id': '$day-$type',
          'createdAt': '2026-09-0${day}T18:00:00Z',
          'orderType': type,
          'totalCents': huge ? cents * 1234567 : cents,
        }),
      );
    }
  }
  return const AnalyticsCalculator().calculate(
    data,
    locationId: 'location-id',
    range: AnalyticsDateRange.custom(
      DateTime.utc(2026, 9, 4),
      DateTime.utc(2026, 9, 4),
    ),
  );
}

Future<void> mount(
  WidgetTester tester,
  AnalyticsResult result, {
  double width = 390,
  double scale = 1,
  String lang = 'en',
  bool covered = true,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
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
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AnalyticsRevenueOverview(
            result: result,
            comparisonCovered: covered,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0, 768.0, 1400.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'complete single-line money fits real card width $width/$scale',
        (tester) async {
          final order = AnalyticsOrder.fromJson({
            ...orderJson(),
            'createdAt': '2026-09-04T18:00:00Z',
            'totalCents': 100436,
          });
          final result = const AnalyticsCalculator().calculate(
            [order],
            locationId: 'location-id',
            range: AnalyticsDateRange.custom(
              DateTime.utc(2026, 9, 4),
              DateTime.utc(2026, 9, 4),
            ),
          );
          await mount(tester, result, width: width, scale: scale);
          final textFinder = find.descendant(
            of: find.byKey(const Key('analytics-kpi-Sales')),
            matching: find.text('US\$1,004.36'),
          );
          expect(textFinder, findsOneWidget);
          final text = tester.widget<Text>(textFinder);
          expect(text.maxLines, 1);
          expect(text.softWrap, isFalse);
          expect(text.overflow, isNot(TextOverflow.ellipsis));
          final fitted = find
              .ancestor(of: textFinder, matching: find.byType(FittedBox))
              .first;
          final paragraph = tester.renderObject<RenderParagraph>(textFinder);
          final fit = tester.renderObject<RenderFittedBox>(fitted);
          final transform = paragraph.getTransformTo(fit);
          expect(
            MatrixUtils.transformRect(transform, paragraph.paintBounds).width,
            lessThanOrEqualTo(fit.size.width + .01),
          );
          final factor = transform.getMaxScaleOnAxis();
          expect(factor, lessThanOrEqualTo(1));
          if (width >= 768 && scale == 1) expect(factor, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final width in [320.0, 390.0, 768.0, 1400.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final lang in ['en', 'es']) {
        testWidgets(
          'revenue cards two mobile columns large money $width/$scale/$lang',
          (tester) async {
            final result = revenueResult(huge: true);
            await mount(tester, result, width: width, scale: scale, lang: lang);
            final columns = width - 32 >= 1080 * scale ? 4 : 2;
            expect(
              find.byKey(ValueKey('analytics-kpi-columns-$columns')),
              findsOneWidget,
            );
            for (final fitted in find.byType(FittedBox).evaluate()) {
              final box = fitted.renderObject! as RenderFittedBox;
              final paragraph = box.child!;
              final rect = MatrixUtils.transformRect(
                paragraph.getTransformTo(box),
                paragraph.paintBounds,
              );
              expect(rect.width, lessThanOrEqualTo(box.size.width + .01));
            }
            final sales = tester.getRect(
              find.byKey(const Key('analytics-kpi-Sales')),
            );
            final orders = tester.getRect(
              find.byKey(const Key('analytics-kpi-Orders')),
            );
            expect(sales.top, orders.top);
            expect(sales.height, orders.height);
            expect(orders.left, greaterThan(sales.right));
            for (final key in [
              'analytics-kpi-Sales',
              'analytics-kpi-Orders',
              'analytics-kpi-Average Order',
              'analytics-kpi-Items Sold',
              'analytics-revenue-online',
              'analytics-revenue-catering',
              'analytics-revenue-comparison',
            ]) {
              expect(find.byKey(Key(key)), findsOneWidget);
              expect(
                tester.getRect(find.byKey(Key(key))).right,
                lessThanOrEqualTo(width - 16 + .1),
              );
            }
            final formatted = NumberFormat.currency(
              locale: lang,
              name: 'USD',
              symbol: 'US\$',
            ).format(result.current.salesCents / 100);
            expect(
              find.descendant(
                of: find.byKey(const Key('analytics-kpi-Sales')),
                matching: find.text(formatted),
              ),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  testWidgets(
    'real per-type current and previous revenue with directional comparisons',
    (tester) async {
      await mount(tester, revenueResult());
      final regular = find.byKey(const Key('analytics-revenue-online'));
      final catering = find.byKey(const Key('analytics-revenue-catering'));
      expect(
        find.descendant(of: regular, matching: find.text('US\$100.00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: regular, matching: find.text('US\$200.00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: regular, matching: find.text('Orders: 1')),
        findsNWidgets(2),
      );
      final negative = find.descendant(
        of: regular,
        matching: find.text('-50.0% vs previous period'),
      );
      final positive = find.descendant(
        of: catering,
        matching: find.text('+200.0% vs previous period'),
      );
      expect(
        tester.widget<Text>(negative).style!.color,
        PelinesColors.destructive,
      );
      expect(
        tester.widget<Text>(positive).style!.color,
        PelinesColors.successForeground,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('analytics-revenue-comparison')),
          matching: find.text('+US\$100.00'),
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'fulfillment cards follow Regular Catering with real orders and revenue',
    (tester) async {
      final orders = [
        for (final (type, cents) in [('pickup', 12345), ('delivery', 67890)])
          AnalyticsOrder.fromJson({
            ...orderJson(
              fulfillment: type,
              locationId: 'location-id',
              payment: 'paid',
              status: 'delivered',
            ),
            'createdAt': '2026-09-04T18:00:00Z',
            'totalCents': cents,
          }),
      ];
      final result = const AnalyticsCalculator().calculate(
        orders,
        locationId: 'location-id',
        range: AnalyticsDateRange.custom(
          DateTime(2026, 9, 4),
          DateTime(2026, 9, 4),
        ),
      );
      await mount(tester, result);
      final regular = tester.getRect(
        find.byKey(const Key('analytics-revenue-online')),
      );
      final catering = tester.getRect(
        find.byKey(const Key('analytics-revenue-catering')),
      );
      final pickup = find.byKey(const Key('analytics-revenue-pickup'));
      final delivery = find.byKey(const Key('analytics-revenue-delivery'));
      expect(regular.top, catering.top);
      expect(tester.getRect(pickup).top, greaterThan(regular.bottom));
      expect(tester.getRect(pickup).top, tester.getRect(delivery).top);
      expect(
        tester.getRect(pickup).left,
        lessThan(tester.getRect(delivery).left),
      );
      expect(
        find.descendant(of: pickup, matching: find.text('US\$123.45')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: delivery, matching: find.text('US\$678.90')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: pickup, matching: find.text('Orders: 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: delivery, matching: find.text('Orders: 1')),
        findsOneWidget,
      );
      expect(find.text('Fulfillment'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'empty periods never invent percentages and incomplete coverage hides prior values',
    (tester) async {
      await mount(tester, revenueResult(empty: true));
      expect(find.textContaining('NaN'), findsNothing);
      expect(find.textContaining('Infinity'), findsNothing);
      expect(find.text('— vs previous period'), findsNWidgets(9));
      await mount(tester, revenueResult(), covered: false);
      expect(find.text('Previous period:'), findsNWidgets(7));
      expect(find.text('Previous period: —'), findsNWidgets(2));
      expect(find.text('+33.3% vs previous period'), findsNothing);
    },
  );
}
