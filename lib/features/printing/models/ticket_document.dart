import '../../orders/models/order_models.dart';

class TicketModifier {
  const TicketModifier({
    required this.groupName,
    required this.optionName,
    required this.priceAdjustmentCents,
  });
  final String groupName, optionName;
  final int priceAdjustmentCents;
  Map<String, dynamic> toJson() => {
    'groupName': groupName,
    'optionName': optionName,
    'priceAdjustmentCents': priceAdjustmentCents,
  };
  factory TicketModifier.fromJson(Map<String, dynamic> j) => TicketModifier(
    groupName: j['groupName'] as String,
    optionName: j['optionName'] as String,
    priceAdjustmentCents: j['priceAdjustmentCents'] as int,
  );
}

class TicketItem {
  TicketItem({
    required this.quantity,
    required this.name,
    required this.baseUnitPriceCents,
    required this.lineTotalCents,
    required List<TicketModifier> modifiers,
    this.instructions,
  }) : modifiers = List.unmodifiable(modifiers);
  final int quantity, baseUnitPriceCents, lineTotalCents;
  final String name;
  final String? instructions;
  final List<TicketModifier> modifiers;
  Map<String, dynamic> toJson() => {
    'quantity': quantity,
    'name': name,
    'baseUnitPriceCents': baseUnitPriceCents,
    'lineTotalCents': lineTotalCents,
    'instructions': instructions,
    'modifiers': modifiers.map((m) => m.toJson()).toList(),
  };
  factory TicketItem.fromJson(Map<String, dynamic> j) => TicketItem(
    quantity: j['quantity'] as int,
    name: j['name'] as String,
    baseUnitPriceCents: j['baseUnitPriceCents'] as int,
    lineTotalCents: j['lineTotalCents'] as int,
    instructions: j['instructions'] as String?,
    modifiers: (j['modifiers'] as List)
        .map(
          (m) => TicketModifier.fromJson(Map<String, dynamic>.from(m as Map)),
        )
        .toList(),
  );
}

class TicketTotals {
  const TicketTotals({
    required this.subtotalCents,
    required this.serviceFeeCents,
    required this.tipCents,
    required this.deliveryFeeCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    this.amountPaidCents,
  });
  final int subtotalCents,
      serviceFeeCents,
      tipCents,
      deliveryFeeCents,
      discountCents,
      taxCents,
      totalCents;

  /// Unknown for non-paid orders: total is not evidence of a payment.
  final int? amountPaidCents;
  Map<String, dynamic> toJson() => {
    'subtotalCents': subtotalCents,
    'serviceFeeCents': serviceFeeCents,
    'tipCents': tipCents,
    'deliveryFeeCents': deliveryFeeCents,
    'discountCents': discountCents,
    'taxCents': taxCents,
    'totalCents': totalCents,
    'amountPaidCents': amountPaidCents,
  };
  factory TicketTotals.fromJson(Map<String, dynamic> j) => TicketTotals(
    subtotalCents: j['subtotalCents'] as int,
    serviceFeeCents: j['serviceFeeCents'] as int,
    tipCents: j['tipCents'] as int,
    deliveryFeeCents: j['deliveryFeeCents'] as int,
    discountCents: j['discountCents'] as int,
    taxCents: j['taxCents'] as int,
    totalCents: j['totalCents'] as int,
    amountPaidCents: j['amountPaidCents'] as int?,
  );
}

class TicketDocument {
  TicketDocument({
    required this.orderId,
    required this.orderNumber,
    required this.orderType,
    required this.fulfillmentType,
    required this.customerName,
    required this.phone,
    required this.placedAt,
    required List<TicketItem> items,
    required this.totals,
    required this.payment,
    this.locationName,
    this.scheduledFor,
    this.notes,
    this.discountCode,
    this.cardBrand,
    this.cardLast4,
    Map<String, dynamic>? deliveryAddress,
    Map<String, dynamic>? eventDetails,
  }) : items = List.unmodifiable(items),
       deliveryAddress = deliveryAddress == null
           ? null
           : _freeze(deliveryAddress) as Map<String, dynamic>,
       eventDetails = eventDetails == null
           ? null
           : _freeze(eventDetails) as Map<String, dynamic>;
  final String orderId, orderNumber, customerName, phone;
  final String? locationName, notes, discountCode, cardBrand, cardLast4;
  final OrderType orderType;
  final FulfillmentType fulfillmentType;
  final PaymentStatus payment;
  final DateTime placedAt;
  final DateTime? scheduledFor;
  final List<TicketItem> items;
  final TicketTotals totals;
  final Map<String, dynamic>? deliveryAddress, eventDetails;
  bool get isAsap => scheduledFor == null;
  Map<String, dynamic> toJson() => {
    'orderId': orderId,
    'orderNumber': orderNumber,
    'orderType': orderType.name,
    'fulfillmentType': fulfillmentType.name,
    'customerName': customerName,
    'phone': phone,
    'locationName': locationName,
    'placedAt': placedAt.toUtc().toIso8601String(),
    'scheduledFor': scheduledFor?.toUtc().toIso8601String(),
    'items': items.map((i) => i.toJson()).toList(),
    'totals': totals.toJson(),
    'payment': payment.name,
    'notes': notes,
    'discountCode': discountCode,
    'cardBrand': cardBrand,
    'cardLast4': cardLast4,
    'deliveryAddress': deliveryAddress,
    'eventDetails': eventDetails,
  };
  factory TicketDocument.fromJson(Map<String, dynamic> j) => TicketDocument(
    orderId: j['orderId'] as String,
    orderNumber: j['orderNumber'] as String,
    orderType: OrderType.fromJson(j['orderType']),
    fulfillmentType: FulfillmentType.fromJson(j['fulfillmentType']),
    customerName: j['customerName'] as String,
    phone: j['phone'] as String,
    locationName: j['locationName'] as String?,
    placedAt: DateTime.parse(j['placedAt'] as String),
    scheduledFor: j['scheduledFor'] == null
        ? null
        : DateTime.parse(j['scheduledFor'] as String),
    items: (j['items'] as List)
        .map((i) => TicketItem.fromJson(Map<String, dynamic>.from(i as Map)))
        .toList(),
    totals: TicketTotals.fromJson(
      Map<String, dynamic>.from(j['totals'] as Map),
    ),
    payment: PaymentStatus.fromJson(j['payment']),
    notes: j['notes'] as String?,
    discountCode: j['discountCode'] as String?,
    cardBrand: j['cardBrand'] as String?,
    cardLast4: j['cardLast4'] as String?,
    deliveryAddress: j['deliveryAddress'] as Map<String, dynamic>?,
    eventDetails: j['eventDetails'] as Map<String, dynamic>?,
  );
}

dynamic _freeze(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map((k, v) => MapEntry(k as String, _freeze(v))),
    );
  }
  if (value is List) return List<dynamic>.unmodifiable(value.map(_freeze));
  return value;
}
