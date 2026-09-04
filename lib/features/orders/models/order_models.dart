enum OrderStatus {
  pending,
  confirmed,
  preparing,
  ready,
  delivered,
  cancelled,
  unknown;

  static OrderStatus fromJson(Object? value) => switch (value) {
    'pending' => pending,
    'confirmed' => confirmed,
    'preparing' => preparing,
    'ready' => ready,
    'delivered' => delivered,
    'cancelled' => cancelled,
    _ => unknown,
  };
}

enum PaymentStatus {
  unpaid,
  paid,
  refunded,
  failed,
  unknown;

  static PaymentStatus fromJson(Object? value) => switch (value) {
    'unpaid' => unpaid,
    'paid' => paid,
    'refunded' => refunded,
    'failed' => failed,
    _ => unknown,
  };
}

enum OrderType {
  online,
  catering,
  unknown;

  static OrderType fromJson(Object? value) => switch (value) {
    'online' => online,
    'catering' => catering,
    _ => unknown,
  };
}

enum FulfillmentType {
  pickup,
  delivery,
  unknown;

  static FulfillmentType fromJson(Object? value) => switch (value) {
    'pickup' => pickup,
    'delivery' => delivery,
    _ => unknown,
  };
}

class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.orderNumber,
    required this.locationId,
    required this.orderType,
    required this.status,
    required this.rawStatus,
    required this.paymentStatus,
    required this.fulfillmentType,
    required this.contactName,
    required this.createdAt,
    required this.itemCount,
    required this.totalCents,
    this.scheduledFor,
    this.eventName,
    this.deliveredAt,
  });

  factory OrderSummary.fromJson(Map<String, dynamic> json) {
    final List<dynamic> items = _list(json['items'], 'items');
    final Map<String, dynamic>? event = _optionalMap(json['eventDetails']);
    return OrderSummary(
      id: _string(json, 'id'),
      orderNumber: _string(json, 'orderNumber'),
      locationId: _string(json, 'locationId'),
      orderType: OrderType.fromJson(json['orderType']),
      status: OrderStatus.fromJson(json['status']),
      rawStatus: json['status']?.toString() ?? 'unknown',
      paymentStatus: PaymentStatus.fromJson(json['paymentStatus']),
      fulfillmentType: FulfillmentType.fromJson(json['fulfillmentType']),
      contactName: _string(json, 'contactName'),
      scheduledFor: _optionalDate(json['scheduledFor']),
      createdAt: DateTime.parse(_string(json, 'createdAt')),
      eventName: event?['eventName'] is String
          ? event!['eventName'] as String
          : null,
      deliveredAt: _optionalDate(json['deliveredAt']),
      itemCount: items.fold<int>(
        0,
        (int sum, dynamic item) =>
            sum +
            (item is Map<String, dynamic> && item['quantity'] is int
                ? item['quantity'] as int
                : 0),
      ),
      totalCents: _int(json, 'totalCents'),
    );
  }

  final String id;
  final String orderNumber;
  final String locationId;
  final OrderType orderType;
  final OrderStatus status;
  final String rawStatus;
  final PaymentStatus paymentStatus;
  final FulfillmentType fulfillmentType;
  final String contactName;
  final DateTime? scheduledFor;
  final DateTime createdAt;
  final String? eventName;
  final DateTime? deliveredAt;
  final int itemCount;
  final int totalCents;

  DateTime get operationalAt => scheduledFor ?? createdAt;
}

class OrderDetail {
  const OrderDetail({
    required this.id,
    required this.orderNumber,
    required this.locationId,
    required this.orderType,
    required this.status,
    required this.rawStatus,
    required this.paymentStatus,
    required this.fulfillmentType,
    required this.contactName,
    required this.contactPhone,
    required this.contactEmail,
    required this.createdAt,
    required this.subtotalCents,
    required this.taxCents,
    required this.serviceFeeCents,
    required this.tipCents,
    required this.discountCents,
    required this.deliveryFeeCents,
    required this.totalCents,
    required this.items,
    this.location,
    this.scheduledFor,
    this.eventDetails,
    this.deliveryAddress,
    this.notes,
    this.internalNotes,
    this.discountCode,
    this.cardBrand,
    this.cardLast4,
    this.deliveredAt,
    this.printedAt,
  });

  factory OrderDetail.fromJson(Map<String, dynamic> json) {
    return OrderDetail(
      id: _string(json, 'id'),
      orderNumber: _string(json, 'orderNumber'),
      locationId: _string(json, 'locationId'),
      orderType: OrderType.fromJson(json['orderType']),
      status: OrderStatus.fromJson(json['status']),
      rawStatus: json['status']?.toString() ?? 'unknown',
      paymentStatus: PaymentStatus.fromJson(json['paymentStatus']),
      fulfillmentType: FulfillmentType.fromJson(json['fulfillmentType']),
      contactName: _string(json, 'contactName'),
      contactPhone: _string(json, 'contactPhone'),
      contactEmail: _string(json, 'contactEmail'),
      location: _optionalMap(json['location']),
      scheduledFor: _optionalDate(json['scheduledFor']),
      createdAt: DateTime.parse(_string(json, 'createdAt')),
      eventDetails: _optionalMap(json['eventDetails']),
      deliveryAddress: _optionalMap(json['deliveryAddress']),
      notes: json['notes'] as String?,
      internalNotes: json['internalNotes'] as String?,
      subtotalCents: _int(json, 'subtotalCents'),
      taxCents: _int(json, 'taxCents'),
      serviceFeeCents: _int(json, 'serviceFeeCents'),
      tipCents: _int(json, 'tipCents'),
      discountCode: json['discountCode'] as String?,
      discountCents: _int(json, 'discountCents'),
      deliveryFeeCents: _int(json, 'deliveryFeeCents'),
      totalCents: _int(json, 'totalCents'),
      cardBrand: json['cardBrand'] as String?,
      cardLast4: json['cardLast4'] as String?,
      deliveredAt: _optionalDate(json['deliveredAt']),
      printedAt: _optionalDate(json['printedAt']),
      items: _list(json['items'], 'items')
          .map((dynamic item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('Invalid order item.');
            }
            return OrderItem.fromJson(item);
          })
          .toList(growable: false),
    );
  }

  final String id;
  final String orderNumber;
  final String locationId;
  final OrderType orderType;
  final OrderStatus status;
  final String rawStatus;
  final PaymentStatus paymentStatus;
  final FulfillmentType fulfillmentType;
  final String contactName;
  final String contactPhone;
  final String contactEmail;
  final Map<String, dynamic>? location;
  final DateTime? scheduledFor;
  final DateTime createdAt;
  final Map<String, dynamic>? eventDetails;
  final Map<String, dynamic>? deliveryAddress;
  final String? notes;
  final String? internalNotes;
  final int subtotalCents;
  final int taxCents;
  final int serviceFeeCents;
  final int tipCents;
  final String? discountCode;
  final int discountCents;
  final int deliveryFeeCents;
  final int totalCents;
  final String? cardBrand;
  final String? cardLast4;
  final DateTime? deliveredAt;
  final DateTime? printedAt;
  final List<OrderItem> items;
}

class OrderItem {
  const OrderItem({
    required this.id,
    required this.productName,
    required this.unitPriceCents,
    required this.quantity,
    required this.lineTotalCents,
    required this.modifiers,
    this.productId,
    this.notes,
  });
  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    id: _string(json, 'id'),
    productId: json['productId'] as String?,
    productName: _string(json, 'productName'),
    unitPriceCents: _int(json, 'unitPriceCents'),
    quantity: _int(json, 'quantity'),
    lineTotalCents: _int(json, 'lineTotalCents'),
    notes: json['notes'] as String?,
    modifiers: _list(json['modifiers'], 'modifiers')
        .map((dynamic value) {
          if (value is! Map<String, dynamic>) {
            throw const FormatException('Invalid order modifier.');
          }
          return OrderModifier.fromJson(value);
        })
        .toList(growable: false),
  );
  final String id;
  final String? productId;
  final String productName;
  final int unitPriceCents;
  final int quantity;
  final int lineTotalCents;
  final String? notes;
  final List<OrderModifier> modifiers;
}

class OrderModifier {
  const OrderModifier({
    required this.id,
    required this.groupName,
    required this.optionName,
    required this.priceDeltaCents,
  });
  factory OrderModifier.fromJson(Map<String, dynamic> json) => OrderModifier(
    id: _string(json, 'id'),
    groupName: _string(json, 'groupName'),
    optionName: _string(json, 'optionName'),
    priceDeltaCents: _int(json, 'priceDeltaCents'),
  );
  final String id;
  final String groupName;
  final String optionName;
  final int priceDeltaCents;
}

String _string(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is String) return value;
  throw FormatException('Invalid $key.');
}

int _int(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is int) return value;
  throw FormatException('Invalid $key.');
}

DateTime? _optionalDate(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

Map<String, dynamic>? _optionalMap(Object? value) =>
    value is Map<String, dynamic> ? value : null;

List<dynamic> _list(Object? value, String key) {
  if (value is List<dynamic>) return value;
  throw FormatException('Invalid $key.');
}
