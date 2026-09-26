import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/theme/pelines_components.dart';
import 'package:pelines_admin_app/core/time/pelines_time.dart';
import 'package:pelines_admin_app/features/analytics/application/analytics_operational_kpis.dart';
import 'package:pelines_admin_app/features/analytics/data/analytics_repository.dart';
import 'package:pelines_admin_app/features/analytics/models/analytics_date_range.dart';
import 'package:pelines_admin_app/features/analytics/presentation/analytics_operational_cards.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';

import 'analytics_test.dart' show order;
import 'analytics_visualizations_test.dart' show mount;

void main() {
  final range = AnalyticsDateRange.custom(
    DateTime(2026, 3, 9),
    DateTime(2026, 3, 10),
  );
  test('eligibility, location, Pacific dates, statuses and ties', () {
    final dataset = AnalyticsDataset(
      locationId: 'a',
      orders: [
        order(at: '2026-03-10T06:30:00Z', status: OrderStatus.pending),
        order(
          at: '2026-03-10T06:45:00Z',
          payment: PaymentStatus.refunded,
          status: OrderStatus.ready,
          fulfillment: FulfillmentType.delivery,
        ),
        order(at: '2026-03-10T19:00:00Z', status: OrderStatus.ready),
        order(at: '2026-03-10T19:30:00Z', payment: PaymentStatus.refunded),
        order(
          at: '2026-03-10T19:00:00Z',
          payment: PaymentStatus.unpaid,
          status: OrderStatus.pending,
        ),
        order(
          at: '2026-03-10T19:00:00Z',
          payment: PaymentStatus.failed,
          status: OrderStatus.ready,
        ),
        order(at: '2026-03-10T19:00:00Z', payment: PaymentStatus.unknown),
        order(location: 'b', status: OrderStatus.pending),
        order(at: '2026-03-09T06:59:59Z'),
        order(at: '2026-03-11T07:00:00Z'),
      ],
    );
    final kpis = AnalyticsOperationalKpis(dataset, range);
    expect(kpis.waiting, 1);
    expect(kpis.ready, 2);
    expect(AnalyticsOperationalKpis.leaders(kpis.hours), [12, 23]);
    expect(AnalyticsOperationalKpis.maximum(kpis.hours), 2);
    expect(AnalyticsOperationalKpis.leaders(kpis.weekdays), [0, 1]);
    expect(kpis.weekdays.take(2), [2, 2]);
    final onlyTuesday = AnalyticsOperationalKpis(
      dataset,
      AnalyticsDateRange.custom(DateTime(2026, 3, 10), DateTime(2026, 3, 10)),
    );
    expect(onlyTuesday.waiting, 0);
    expect(onlyTuesday.ready, 1);
    expect(AnalyticsOperationalKpis.leaders(onlyTuesday.hours), [12]);
  });

  test('DST repeated hours combine and spring gap is not fabricated', () {
    for (final fixture in [
      (
        DateTime(2026, 11, 1),
        ['2026-11-01T08:30:00Z', '2026-11-01T09:30:00Z'],
        [1],
      ),
      (
        DateTime(2026, 3, 8),
        ['2026-03-08T09:30:00Z', '2026-03-08T10:30:00Z'],
        [1, 3],
      ),
    ]) {
      final kpis = AnalyticsOperationalKpis(
        AnalyticsDataset(
          locationId: 'a',
          orders: [for (final at in fixture.$2) order(at: at)],
        ),
        AnalyticsDateRange.custom(fixture.$1, fixture.$1),
      );
      expect(AnalyticsOperationalKpis.leaders(kpis.hours), fixture.$3);
      expect(kpis.hours[2], 0);
      expect(kpis.weekdays[6], 2);
    }
  });

  for (final locale in ['en', 'es']) {
    for (final width in [390.0, 800.0, 1440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('localized ties $locale $width scale $scale', (
          tester,
        ) async {
          final dataset = AnalyticsDataset(
            locationId: 'a',
            orders: [
              order(at: '2026-03-09T19:00:00Z'),
              order(at: '2026-03-10T20:00:00Z'),
            ],
          );
          await mount(
            tester,
            AnalyticsOperationalCards(dataset: dataset, range: range),
            locale: locale,
            width: width,
            scale: scale,
          );
          final peak = tester.widget<PelinesKpiCard>(
            find.byKey(const Key('analytics-peak-hour')),
          );
          final busiest = tester.widget<PelinesKpiCard>(
            find.byKey(const Key('analytics-busiest-day')),
          );
          expect(peak.value.split('\n'), hasLength(2));
          expect(
            peak.label,
            locale == 'en' ? 'Peak Order Hour' : 'Hora pico de pedidos',
          );
          expect(
            peak.description,
            contains(locale == 'en' ? 'Tied' : 'Empate'),
          );
          expect(
            busiest.value,
            locale == 'en' ? 'Monday\nTuesday' : 'lunes\nmartes',
          );
          expect(
            tester
                .widget<PelinesKpiCard>(
                  find.byKey(const Key('analytics-ready')),
                )
                .label,
            locale == 'en' ? 'Ready' : 'Listos',
          );
          final peakRect = tester.getRect(
            find.byKey(const Key('analytics-peak-hour')),
          );
          final dayRect = tester.getRect(
            find.byKey(const Key('analytics-busiest-day')),
          );
          expect(dayRect.top == peakRect.top, width >= 520 * scale + 32);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('empty ranks, current partial period and coverage boundary', (
    tester,
  ) async {
    final today = PelinesTime.now();
    final current = AnalyticsDateRange.custom(today, today);
    await mount(
      tester,
      AnalyticsOperationalCards(
        dataset: AnalyticsDataset(locationId: 'a', orders: []),
        range: current,
      ),
    );
    expect(find.text('This period is still in progress.'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('0'), findsNWidgets(2));
    final dataset = AnalyticsDataset(
      locationId: 'a',
      orders: [
        order(at: '2026-03-08T18:00:00Z'),
        ...List.generate(1999, (_) => order()),
      ],
    );
    await mount(
      tester,
      AnalyticsOperationalCards(
        dataset: dataset,
        range: AnalyticsDateRange.custom(
          DateTime(2026, 3, 8),
          DateTime(2026, 3, 9),
        ),
      ),
    );
    expect(find.text('—'), findsNWidgets(2));
    expect(find.textContaining('Data may be incomplete'), findsNWidgets(2));
    await mount(
      tester,
      AnalyticsOperationalCards(dataset: dataset, range: range),
    );
    expect(find.text('—'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
