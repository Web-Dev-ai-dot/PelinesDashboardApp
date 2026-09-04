class Location {
  const Location({
    required this.id,
    required this.name,
    required this.slug,
    required this.isActive,
    required this.deliveryFeeCents,
    required this.deliveryMinimumCents,
    required this.isAcceptingOrders,
    required this.createdAt,
    required this.updatedAt,
    this.address,
    this.phone,
    this.hoursJson,
    this.servicePrefsJson,
    this.hoursExtrasJson,
    this.cateringDeliveryJson,
    this.regularDeliveryJson,
  });

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      hoursJson: _optionalMap(json['hoursJson'], 'hoursJson'),
      isActive: json['isActive'] as bool,
      deliveryFeeCents: json['deliveryFeeCents'] as int,
      deliveryMinimumCents: json['deliveryMinimumCents'] as int,
      isAcceptingOrders: json['isAcceptingOrders'] as bool,
      servicePrefsJson: _optionalMap(
        json['servicePrefsJson'],
        'servicePrefsJson',
      ),
      hoursExtrasJson: _optionalMap(json['hoursExtrasJson'], 'hoursExtrasJson'),
      cateringDeliveryJson: _optionalMap(
        json['cateringDeliveryJson'],
        'cateringDeliveryJson',
      ),
      regularDeliveryJson: _optionalMap(
        json['regularDeliveryJson'],
        'regularDeliveryJson',
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  final String id;
  final String name;
  final String slug;
  final String? address;
  final String? phone;
  final Map<String, dynamic>? hoursJson;
  final bool isActive;
  final int deliveryFeeCents;
  final int deliveryMinimumCents;
  final bool isAcceptingOrders;
  final Map<String, dynamic>? servicePrefsJson;
  final Map<String, dynamic>? hoursExtrasJson;
  final Map<String, dynamic>? cateringDeliveryJson;
  final Map<String, dynamic>? regularDeliveryJson;
  final DateTime createdAt;
  final DateTime updatedAt;

  static Map<String, dynamic>? _optionalMap(Object? value, String field) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    throw FormatException('Invalid $field.');
  }
}
