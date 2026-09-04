import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';

void main() {
  test(
    'parses summary enums, event name, modifiers count and exact payment',
    () {
      final OrderSummary order = OrderSummary.fromJson(_orderJson());
      expect(order.orderNumber, 'TUA-1001');
      expect(order.orderType, OrderType.catering);
      expect(order.status, OrderStatus.pending);
      expect(order.paymentStatus, PaymentStatus.refunded);
      expect(order.fulfillmentType, FulfillmentType.delivery);
      expect(order.eventName, 'Team lunch');
      expect(order.itemCount, 2);
    },
  );

  test('unknown enum values are retained without crashing', () {
    final Map<String, dynamic> json = _orderJson()..['status'] = 'on_hold';
    final OrderSummary order = OrderSummary.fromJson(json);
    expect(order.status, OrderStatus.unknown);
    expect(order.rawStatus, 'on_hold');
  });

  test('parses detail, null product, modifiers, nulls and partial JSON', () {
    final OrderDetail order = OrderDetail.fromJson(_orderJson());
    expect(order.items.single.productId, isNull);
    expect(order.items.single.modifiers.single.optionName, 'Hot');
    expect(order.deliveryAddress, <String, dynamic>{'line1': '1 Main'});
    expect(order.eventDetails?['attendees'], 12);
    expect(order.notes, isNull);
    expect(order.cardBrand, isNull);
    expect(order.taxCents, 0);
  });
}

Map<String, dynamic> _orderJson() => <String, dynamic>{
  'id': '11111111-1111-1111-1111-111111111111',
  'orderNumber': 'TUA-1001',
  'userId': '22222222-2222-2222-2222-222222222222',
  'locationId': '33333333-3333-3333-3333-333333333333',
  'orderType': 'catering',
  'status': 'pending',
  'paymentStatus': 'refunded',
  'fulfillmentType': 'delivery',
  'subtotalCents': 2000,
  'taxCents': 0,
  'serviceFeeCents': 80,
  'tipCents': 0,
  'discountCode': null,
  'discountCents': 0,
  'deliveryFeeCents': 500,
  'totalCents': 2580,
  'contactName': 'Test Customer',
  'contactPhone': '503-555-0100',
  'contactEmail': 'test@example.com',
  'deliveryAddress': <String, dynamic>{'line1': '1 Main'},
  'scheduledFor': '2026-09-04T19:00:00.000Z',
  'eventDetails': <String, dynamic>{'attendees': 12, 'eventName': 'Team lunch'},
  'notes': null,
  'internalNotes': null,
  'cardBrand': null,
  'cardLast4': null,
  'deliveredAt': null,
  'printedAt': null,
  'createdAt': '2026-09-04T16:00:00.000Z',
  'location': <String, dynamic>{'name': 'Tualatin'},
  'items': <dynamic>[
    <String, dynamic>{
      'id': 'item-1',
      'productId': null,
      'productName': 'Tacos',
      'unitPriceCents': 1000,
      'quantity': 2,
      'lineTotalCents': 2000,
      'notes': null,
      'modifiers': <dynamic>[
        <String, dynamic>{
          'id': 'modifier-1',
          'groupName': 'Salsa',
          'optionName': 'Hot',
          'priceDeltaCents': 0,
        },
      ],
    },
  ],
};
