import 'package:pelines_admin_app/features/orders/models/order_models.dart';

Map<String, dynamic> orderJson({
  String id = '11111111-1111-4111-8111-111111111111',
  String status = 'pending',
  String locationId = 'location-id',
}) => <String, dynamic>{
  'id': id,
  'orderNumber': 'ORD-1048',
  'locationId': locationId,
  'orderType': 'online',
  'status': status,
  'paymentStatus': 'paid',
  'fulfillmentType': 'pickup',
  'contactName': 'Customer',
  'contactPhone': '555-0100',
  'contactEmail': 'customer@example.test',
  'createdAt': '2026-09-04T18:00:00.000Z',
  'subtotalCents': 1000,
  'taxCents': 100,
  'serviceFeeCents': 0,
  'tipCents': 0,
  'discountCents': 0,
  'deliveryFeeCents': 0,
  'totalCents': 1100,
  'items': <dynamic>[],
};

OrderDetail orderDetail({
  OrderStatus status = OrderStatus.pending,
  String id = '11111111-1111-4111-8111-111111111111',
  String locationId = 'location-id',
}) => OrderDetail.fromJson(
  orderJson(id: id, status: status.name, locationId: locationId),
);
