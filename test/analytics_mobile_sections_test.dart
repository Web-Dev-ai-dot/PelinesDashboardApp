import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/analytics/presentation/analytics_metric_cards.dart';
import 'package:pelines_admin_app/features/analytics/presentation/analytics_operational_cards.dart';
import 'package:pelines_admin_app/features/analytics/presentation/analytics_order_sections.dart';

import 'analytics_visualizations_test.dart' as h;
import 'order_test_data.dart';

import 'package:pelines_admin_app/features/analytics/models/analytics_order.dart';

void main() {
  for (final width in [320.0, 390.0, 768.0, 1400.0]) {
    for (final locale in ['en', 'es']) {
      testWidgets(
        'six volume seven operations seven status cards $width/$locale/2x',
        (tester) async {
          final dataset = h.data([
            h.row(status: 'pending'),
            h.row(status: 'confirmed'),
            h.row(status: 'preparing'),
            h.row(status: 'ready'),
            h.row(status: 'delivered', fulfillment: 'pickup'),
            h.row(
              status: 'delivered',
              fulfillment: 'delivery',
              type: 'catering',
            ),
            h.row(status: 'cancelled'),
            h.row(status: 'delivered', payment: 'failed'),
          ]);
          final period = h.result(dataset, h.day()).current;
          await h.mount(
            tester,
            Column(
              children: [
                AnalyticsOrderVolume(
                  key: const Key('volume'),
                  dataset: dataset,
                  period: period,
                ),
                AnalyticsOperationalCards(
                  key: const Key('operations'),
                  dataset: dataset,
                  period: period,
                ),
                AnalyticsStatusCards(
                  key: const Key('status'),
                  dataset: dataset,
                  period: period,
                ),
              ],
            ),
            width: width,
            scale: 2,
            locale: locale,
          );
          expect(
            find.descendant(
              of: find.byKey(const Key('volume')),
              matching: find.byType(AnalyticsMetricCard),
            ),
            findsNWidgets(6),
          );
          expect(
            find.descendant(
              of: find.byKey(const Key('operations')),
              matching: find.byType(AnalyticsMetricCard),
            ),
            findsNWidgets(7),
          );
          final status = find.byKey(const Key('status'));
          expect(
            find.descendant(
              of: status,
              matching: find.byType(AnalyticsMetricCard),
            ),
            findsNWidgets(7),
          );
          final completed = tester.widget<AnalyticsMetricCard>(
            find.byKey(const Key('analytics-status-completed')),
          );
          expect(completed.value, '2');
          expect(completed.completed, isTrue);
          expect(
            find.byKey(const Key('analytics-status-picked-up')),
            findsNothing,
          );
          for (final (key, value) in [
            ('cancelled', '1'),
            ('in-progress', '4'),
          ]) {
            expect(
              tester
                  .widget<AnalyticsMetricCard>(
                    find.byKey(Key('analytics-status-$key')),
                  )
                  .value,
              value,
            );
          }
          final readyRect = tester.getRect(
            find.byKey(const Key('analytics-status-ready')),
          );
          final cancelledRect = tester.getRect(
            find.byKey(const Key('analytics-status-cancelled')),
          );
          final progressRect = tester.getRect(
            find.byKey(const Key('analytics-status-in-progress')),
          );
          expect(cancelledRect.top, progressRect.top);
          expect(cancelledRect.top, greaterThan(readyRect.bottom));
          expect(
            tester
                .getSize(find.byKey(const Key('analytics-status-completed')))
                .width,
            tester.getSize(status).width,
          );
          final pendingRect = tester.getRect(
            find.byKey(const Key('analytics-status-pending')),
          );
          final confirmedRect = tester.getRect(
            find.byKey(const Key('analytics-status-confirmed')),
          );
          expect(pendingRect.top, confirmedRect.top);
          expect(confirmedRect.left, greaterThan(pendingRect.right));
          for (final key in [
            'analytics-on-time',
            'analytics-approval-rate',
            'analytics-approval-time',
            'analytics-accuracy',
          ]) {
            expect(
              tester.widget<AnalyticsMetricCard>(find.byKey(Key(key))).value,
              '—',
            );
          }
          expect(
            tester
                .widget<AnalyticsMetricCard>(
                  find.byKey(const Key('analytics-waiting')),
                )
                .value,
            '1',
          );
          expect(
            tester
                .widget<AnalyticsMetricCard>(
                  find.byKey(const Key('analytics-ready')),
                )
                .value,
            '1',
          );
          expect(
            tester
                .widget<AnalyticsMetricCard>(
                  find.byKey(const Key('analytics-volume-total')),
                )
                .value,
            '7',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'status projection follows range and does not count ineligible or other locations',
    (tester) async {
      final dataset = h.data([
        h.row(),
        h.row(at: '2026-03-08T18:00:00Z'),
        h.row(payment: 'unpaid'),
        AnalyticsOrder.fromJson({
          ...orderJson(locationId: 'b', status: 'delivered', payment: 'paid'),
          'createdAt': '2026-03-09T18:00:00Z',
        }),
      ]);
      await h.mount(
        tester,
        AnalyticsStatusCards(
          dataset: dataset,
          period: h.result(dataset, h.day()).current,
        ),
      );
      expect(
        tester
            .widget<AnalyticsMetricCard>(
              find.byKey(const Key('analytics-status-completed')),
            )
            .value,
        '1',
      );
      expect(find.byKey(const Key('analytics-status-picked-up')), findsNothing);
    },
  );
}
