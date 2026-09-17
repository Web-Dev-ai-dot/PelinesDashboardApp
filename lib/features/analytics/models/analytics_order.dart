import '../../orders/models/order_models.dart';

/// Projection of a list-order response; no detail request is needed.
class AnalyticsOrder {
  AnalyticsOrder({
    required this.id,
    required this.locationId,
    required this.createdAt,
    required this.status,
    required this.paymentStatus,
    required this.orderType,
    required this.fulfillmentType,
    required this.totalCents,
    required List<OrderItem> items,
  }) : items = List.unmodifiable(items);

  factory AnalyticsOrder.fromJson(Map<String, dynamic> json) => AnalyticsOrder(
    id: json['id'] as String,
    locationId: json['locationId'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    status: OrderStatus.fromJson(json['status']),
    paymentStatus: PaymentStatus.fromJson(json['paymentStatus']),
    orderType: OrderType.fromJson(json['orderType']),
    fulfillmentType: FulfillmentType.fromJson(json['fulfillmentType']),
    totalCents: json['totalCents'] as int,
    items: (json['items'] as List<dynamic>)
        .map((item) => OrderItem.fromJson(item as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String locationId;
  final DateTime createdAt;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final OrderType orderType;
  final FulfillmentType fulfillmentType;
  final int totalCents;
  final List<OrderItem> items;

  bool get isEligible =>
      paymentStatus == PaymentStatus.paid ||
      paymentStatus == PaymentStatus.refunded;
  bool get isSale =>
      paymentStatus == PaymentStatus.paid && status != OrderStatus.cancelled;
}
