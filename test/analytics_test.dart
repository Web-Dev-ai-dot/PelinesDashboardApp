import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/analytics/application/analytics_calculator.dart';
import 'package:pelines_admin_app/features/analytics/models/analytics_date_range.dart';
import 'package:pelines_admin_app/features/analytics/models/analytics_order.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';

OrderItem item(String? id, String name, int qty, int cents) => OrderItem(
  id: 'line',
  productId: id,
  productName: name,
  unitPriceCents: 1,
  quantity: qty,
  lineTotalCents: cents,
  modifiers: const [],
);

AnalyticsOrder order({
  PaymentStatus payment = PaymentStatus.paid,
  OrderStatus status = OrderStatus.delivered,
  int cents = 1000,
  String at = '2026-03-09T18:00:00Z',
  String location = 'a',
  OrderType type = OrderType.online,
  FulfillmentType fulfillment = FulfillmentType.pickup,
  List<OrderItem> items = const [],
}) => AnalyticsOrder(
  id: 'order',
  locationId: location,
  createdAt: DateTime.parse(at),
  status: status,
  paymentStatus: payment,
  orderType: type,
  fulfillmentType: fulfillment,
  totalCents: cents,
  items: items,
);

void main() {
  final range = AnalyticsDateRange.custom(
    DateTime(2026, 3, 9),
    DateTime(2026, 3, 9),
  );
  const calculator = AnalyticsCalculator();

  test('cohorts, denominators, breakdowns, products and comparisons', () {
    final result = calculator.calculate(
      [
        order(cents: 1001, items: [item('p', 'Taco', 2, 800)]),
        order(
          cents: 2000,
          status: OrderStatus.ready,
          type: OrderType.catering,
          fulfillment: FulfillmentType.delivery,
          items: [
            item('p', 'Taco renamed', 3, 1200),
            item(null, 'Other', 1, 200),
          ],
        ),
        order(payment: PaymentStatus.refunded, status: OrderStatus.cancelled),
        order(status: OrderStatus.cancelled),
        order(payment: PaymentStatus.refunded),
        order(payment: PaymentStatus.failed),
        order(payment: PaymentStatus.unpaid),
        order(payment: PaymentStatus.unknown),
        order(location: 'b', cents: 99999),
        order(
          at: '2026-03-08T18:00:00Z',
          cents: 1000,
          items: [item('p', 'Taco', 1, 800)],
        ),
      ],
      locationId: 'a',
      range: range,
    );
    final current = result.current;
    expect(current.salesCents, 3001);
    expect(current.orders, 5);
    expect(current.salesOrderCount, 2);
    expect(current.averageOrderCents, 1500.5);
    expect(current.itemsSold, 6);
    expect(current.cancellationRate, 40);
    expect(current.completed, 2);
    expect(current.cancelled, 2);
    expect(current.inProgress, 1);
    expect(current.products.first.quantity, 5);
    expect(current.products.first.lineSalesCents, 2000);
    expect(current.products.last.productId, isNull);
    expect(current.orderTypes[OrderType.online]!.orders, 4);
    expect(current.orderTypes[OrderType.catering]!.salesCents, 2000);
    expect(current.fulfillmentTypes[FulfillmentType.pickup]!.salesCents, 1001);
    expect(current.fulfillmentTypes[FulfillmentType.delivery]!.orders, 1);
    expect(current.dailySales.single.salesCents, 3001);
    expect(result.previous.salesCents, 1000);
    expect(result.sales.difference, 2001);
    expect(result.sales.percentChange, closeTo(200.1, 0.0001));
    expect(result.orders.difference, 4);
    expect(result.itemsSold.difference, 5);
    expect(result.averageOrder.difference, 500.5);
    expect(result.cancellationRatePointChange, 40);
  });

  test(
    'empty denominators are absent; no-sales eligible orders remain counted',
    () {
      final empty = calculator.calculate([], locationId: 'a', range: range);
      expect(empty.current.averageOrderCents, isNull);
      expect(empty.current.cancellationRate, isNull);
      expect(empty.sales.percentChange, isNull);
      expect(empty.cancellationRatePointChange, isNull);
      final onlyRefund = calculator
          .calculate(
            [order(payment: PaymentStatus.refunded)],
            locationId: 'a',
            range: range,
          )
          .current;
      expect(onlyRefund.orders, 1);
      expect(onlyRefund.averageOrderCents, isNull);
      expect(onlyRefund.cancellationRate, 0);
    },
  );

  test(
    'product IDs separate equal names; fallback and ties are deterministic',
    () {
      final result = calculator
          .calculate(
            [
              order(
                items: [
                  item('b', 'Same', 2, 20),
                  item('a', 'Same', 2, 10),
                  item(null, 'Same', 1, 5),
                  item(null, 'Same', 1, 5),
                ],
              ),
            ],
            locationId: 'a',
            range: range,
          )
          .current;
      expect(result.products.map((p) => p.key), ['id:a', 'id:b', 'name:Same']);
      expect(result.products.last.lineSalesCents, 10);
      expect(() => result.products.clear(), throwsUnsupportedError);
    },
  );

  test(
    'unknown operational state remains visible and follows exact sales rule',
    () {
      final result = calculator
          .calculate(
            [
              order(
                status: OrderStatus.unknown,
                type: OrderType.unknown,
                fulfillment: FulfillmentType.unknown,
              ),
            ],
            locationId: 'a',
            range: range,
          )
          .current;
      expect(result.unknownStatusOrders, 1);
      expect(result.inProgress, 0);
      expect(result.salesCents, 1000);
      expect(result.orderTypes[OrderType.unknown]!.orders, 1);
    },
  );

  test(
    'presets contain exactly 1/7/30/90 Pacific dates with adjacent previous',
    () {
      for (final entry in {
        AnalyticsDatePreset.today: 1,
        AnalyticsDatePreset.last7Days: 7,
        AnalyticsDatePreset.last30Days: 30,
        AnalyticsDatePreset.last90Days: 90,
      }.entries) {
        final selected = AnalyticsDateRange.preset(
          entry.key,
          now: DateTime.parse('2026-03-10T06:59:59Z'),
        );
        expect(selected.dayCount, entry.value);
        expect(selected.dates.length, entry.value);
        expect(selected.endDate, DateTime.utc(2026, 3, 9));
        expect(selected.previous.dayCount, entry.value);
        expect(
          selected.previous.endDate,
          selected.startDate.subtract(const Duration(days: 1)),
        );
      }
    },
  );

  test('custom inclusive and Pacific midnight boundaries', () {
    expect(range.contains(DateTime.parse('2026-03-09T06:59:59Z')), isFalse);
    expect(range.contains(DateTime.parse('2026-03-09T07:00:00Z')), isTrue);
    expect(
      range.contains(DateTime.parse('2026-03-10T06:59:59.999999Z')),
      isTrue,
    );
    expect(range.contains(DateTime.parse('2026-03-10T07:00:00Z')), isFalse);
    final custom = AnalyticsDateRange.custom(
      DateTime(2026, 2, 28),
      DateTime(2026, 3, 2),
    );
    expect(custom.dayCount, 3);
    expect(custom.previous.startDate, DateTime.utc(2026, 2, 25));
    expect(
      () =>
          AnalyticsDateRange.custom(DateTime(2026, 3, 2), DateTime(2026, 3, 1)),
      throwsArgumentError,
    );
  });

  test('spring 23-hour day and fall 25-hour day include both DST sides', () {
    for (final data in [
      [
        '2026-03-08',
        '2026-03-08T08:00:00Z',
        '2026-03-09T07:00:00Z',
        '2026-03-08T09:30:00Z',
        '2026-03-08T10:30:00Z',
      ],
      [
        '2026-11-01',
        '2026-11-01T07:00:00Z',
        '2026-11-02T08:00:00Z',
        '2026-11-01T08:30:00Z',
        '2026-11-01T09:30:00Z',
      ],
    ]) {
      final day = DateTime.parse(data[0]);
      final selected = AnalyticsDateRange.custom(day, day);
      expect(selected.contains(DateTime.parse(data[1])), isTrue);
      expect(selected.contains(DateTime.parse(data[2])), isFalse);
      expect(selected.contains(DateTime.parse(data[3])), isTrue);
      expect(selected.contains(DateTime.parse(data[4])), isTrue);
      final result = calculator.calculate(
        [order(at: data[3]), order(at: data[4])],
        locationId: 'a',
        range: selected,
      );
      expect(result.current.dailySales.single.salesCents, 2000);
      expect(selected.previous.dayCount, 1);
    }
  });

  test(
    'daily series retains gaps and reports dataset cap before filtering',
    () {
      final result = calculator.calculate(
        List.generate(2000, (_) => order(payment: PaymentStatus.failed)),
        locationId: 'a',
        range: AnalyticsDateRange.custom(
          DateTime(2026, 3, 8),
          DateTime(2026, 3, 10),
        ),
      );
      expect(result.mayBeTruncated, isTrue);
      expect(result.current.orders, 0);
      expect(result.current.dailySales.map((d) => d.salesCents), [0, 0, 0]);
    },
  );

  test('list JSON retains item data without detail-only fields', () {
    final parsed = AnalyticsOrder.fromJson({
      'id': '1',
      'locationId': 'a',
      'createdAt': '2026-03-09T18:00:00Z',
      'status': 'ready',
      'paymentStatus': 'paid',
      'orderType': 'online',
      'fulfillmentType': 'pickup',
      'totalCents': 1000,
      'items': [
        {
          'id': 'line',
          'productId': 'p',
          'productName': 'Taco',
          'unitPriceCents': 200,
          'quantity': 3,
          'lineTotalCents': 600,
          'modifiers': [],
        },
      ],
    });
    expect(parsed.items.single.quantity, 3);
    expect(parsed.items.single.lineTotalCents, 600);
    expect(parsed.isSale, isTrue);
    expect(() => parsed.items.clear(), throwsUnsupportedError);
  });
}
