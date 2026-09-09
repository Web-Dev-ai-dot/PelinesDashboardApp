enum MenuKind {
  store,
  catering,
  unknown;

  static MenuKind fromJson(Object? value) => switch (value) {
    'store' => store,
    'catering' => catering,
    _ => unknown,
  };

  String get label => switch (this) {
    store => 'Regular Menu',
    catering => 'Catering Menu',
    unknown => 'Unknown Menu',
  };
}

class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.locationId,
    required this.name,
    required this.slug,
    required this.sortOrder,
    required this.isActive,
    required this.kind,
    required this.rawKind,
    required this.createdAt,
    required this.updatedAt,
    this.subcategorySchedules,
  });

  factory MenuCategory.fromJson(Map<String, dynamic> json) => MenuCategory(
    id: _string(json, 'id'),
    locationId: _string(json, 'locationId'),
    name: _string(json, 'name'),
    slug: _string(json, 'slug'),
    sortOrder: _int(json, 'sortOrder'),
    isActive: _bool(json, 'isActive'),
    kind: MenuKind.fromJson(json['kind']),
    rawKind: json['kind']?.toString() ?? 'unknown',
    subcategorySchedules:
        json['subcategorySchedulesJson'] is Map<String, dynamic>
        ? json['subcategorySchedulesJson'] as Map<String, dynamic>
        : null,
    createdAt: _date(json, 'createdAt'),
    updatedAt: _date(json, 'updatedAt'),
  );

  final String id;
  final String locationId;
  final String name;
  final String slug;
  final int sortOrder;
  final bool isActive;
  final MenuKind kind;
  final String rawKind;
  final Map<String, dynamic>? subcategorySchedules;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class MenuProduct {
  const MenuProduct({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.slug,
    required this.priceCents,
    required this.isAvailable,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    required this.modifierGroups,
    this.description,
    this.imageUrl,
    this.subcategory,
    this.servesCount,
    this.disclaimer,
  });

  factory MenuProduct.fromJson(Map<String, dynamic> json) => MenuProduct(
    id: _string(json, 'id'),
    categoryId: _string(json, 'categoryId'),
    name: _string(json, 'name'),
    slug: _string(json, 'slug'),
    description: json['description'] as String?,
    priceCents: _int(json, 'priceCents'),
    imageUrl: json['imageUrl'] as String?,
    isAvailable: _bool(json, 'isAvailable'),
    sortOrder: _int(json, 'sortOrder'),
    subcategory: json['subcategory'] as String?,
    servesCount: json['servesCount'] as int?,
    disclaimer: json['disclaimer'] as String?,
    createdAt: _date(json, 'createdAt'),
    updatedAt: _date(json, 'updatedAt'),
    modifierGroups: _list(json['modifierGroups'])
        .map(
          (value) => MenuModifierGroup.fromJson(
            value as Map<String, dynamic>,
            containingProductId: _string(json, 'id'),
          ),
        )
        .toList(growable: false),
  );

  final String id;
  final String categoryId;
  final String name;
  final String slug;
  final String? description;
  final int priceCents;
  final String? imageUrl;
  final bool isAvailable;
  final int sortOrder;
  final String? subcategory;
  final int? servesCount;
  final String? disclaimer;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<MenuModifierGroup> modifierGroups;
}

class MenuModifierGroup {
  const MenuModifierGroup({
    required this.id,
    required this.productId,
    required this.name,
    required this.sortOrder,
    required this.options,
    this.optionsLoaded = true,
    this.isRequired,
    this.minSelect,
    this.maxSelect,
  });
  factory MenuModifierGroup.fromJson(
    Map<String, dynamic> json, {
    String? containingProductId,
  }) => MenuModifierGroup(
    id: _string(json, 'id'),
    productId: _modifierProductId(json, containingProductId),
    name: _string(json, 'name'),
    sortOrder: _int(json, 'sortOrder'),
    isRequired: json['isRequired'] as bool?,
    minSelect: json['minSelect'] as int?,
    maxSelect: json['maxSelect'] as int?,
    optionsLoaded: json['options'] is List,
    options: _list(json['options'])
        .map(
          (value) => MenuModifierOption.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
  );
  final String id;
  final String productId;
  final String name;
  final int sortOrder;
  final bool? isRequired;
  final int? minSelect;
  final int? maxSelect;
  final List<MenuModifierOption> options;
  final bool optionsLoaded;

  bool get isFullyLoaded =>
      optionsLoaded &&
      isRequired != null &&
      minSelect != null &&
      maxSelect != null;
}

String _modifierProductId(
  Map<String, dynamic> json,
  String? containingProductId,
) {
  final value = json.containsKey('productId')
      ? json['productId']
      : containingProductId;
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid productId.');
  }
  return value;
}

class MenuModifierOption {
  const MenuModifierOption({
    required this.id,
    required this.groupId,
    required this.name,
    required this.priceDeltaCents,
    required this.isDefault,
    required this.sortOrder,
  });
  factory MenuModifierOption.fromJson(Map<String, dynamic> json) =>
      MenuModifierOption(
        id: _string(json, 'id'),
        groupId: _string(json, 'groupId'),
        name: _string(json, 'name'),
        priceDeltaCents: _int(json, 'priceDeltaCents'),
        isDefault: _bool(json, 'isDefault'),
        sortOrder: _int(json, 'sortOrder'),
      );
  final String id;
  final String groupId;
  final String name;
  final int priceDeltaCents;
  final bool isDefault;
  final int sortOrder;
}

String _string(Map<String, dynamic> json, String key) => json[key] is String
    ? json[key] as String
    : throw FormatException('Invalid $key.');
int _int(Map<String, dynamic> json, String key) => json[key] is int
    ? json[key] as int
    : throw FormatException('Invalid $key.');
bool _bool(Map<String, dynamic> json, String key) => json[key] is bool
    ? json[key] as bool
    : throw FormatException('Invalid $key.');
DateTime _date(Map<String, dynamic> json, String key) =>
    DateTime.parse(_string(json, key));
List<dynamic> _list(Object? value) => value == null
    ? const <dynamic>[]
    : value is List<dynamic>
    ? value
    : throw const FormatException('Invalid list.');
