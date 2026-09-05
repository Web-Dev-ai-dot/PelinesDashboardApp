import 'package:intl/intl.dart';

import '../../../core/time/pelines_time.dart';

enum PromotionEffectiveStatus {
  active('Active'),
  inactive('Inactive'),
  scheduled('Scheduled'),
  expired('Expired'),
  usageLimitReached('Usage limit reached');

  const PromotionEffectiveStatus(this.label);
  final String label;
}

class Discount {
  const Discount({
    required this.id,
    required this.code,
    required this.type,
    required this.value,
    required this.minSubtotalCents,
    required this.startsAt,
    required this.endsAt,
    required this.usageLimit,
    required this.timesRedeemed,
    required this.locationId,
    required this.appliesTo,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Discount.fromJson(Map<String, dynamic> json) => Discount(
    id: _string(json, 'id'),
    code: _string(json, 'code'),
    type: _allowed(json, 'type', const <String>{'percent', 'fixed'}),
    value: _integer(json, 'value'),
    minSubtotalCents: _integer(json, 'minSubtotalCents'),
    startsAt: _optionalDate(json, 'startsAt'),
    endsAt: _optionalDate(json, 'endsAt'),
    usageLimit: _optionalInteger(json, 'usageLimit'),
    timesRedeemed: _integer(json, 'timesRedeemed'),
    locationId: _optionalString(json, 'locationId'),
    appliesTo: _allowed(json, 'appliesTo', const <String>{
      'regular',
      'catering',
      'both',
    }),
    isActive: _boolean(json, 'isActive'),
    createdAt: _date(json, 'createdAt'),
    updatedAt: _date(json, 'updatedAt'),
  );

  final String id;
  final String code;
  final String type;
  final int value;
  final int minSubtotalCents;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? usageLimit;
  final int timesRedeemed;
  final String? locationId;
  final String appliesTo;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  PromotionEffectiveStatus effectiveStatus(DateTime now) {
    final DateTime instant = now.toUtc();
    if (!isActive) return PromotionEffectiveStatus.inactive;
    if (startsAt != null && instant.isBefore(startsAt!.toUtc())) {
      return PromotionEffectiveStatus.scheduled;
    }
    if (endsAt != null && instant.isAfter(endsAt!.toUtc())) {
      return PromotionEffectiveStatus.expired;
    }
    if (usageLimit != null && timesRedeemed >= usageLimit!) {
      return PromotionEffectiveStatus.usageLimitReached;
    }
    return PromotionEffectiveStatus.active;
  }

  String get discountLabel =>
      type == 'percent' ? '$value% off' : '${_money(value)} off';

  String get appliesToLabel => switch (appliesTo) {
    'regular' => 'Regular orders',
    'catering' => 'Catering orders',
    _ => 'Regular & Catering',
  };

  String get minimumLabel => minSubtotalCents == 0
      ? 'No minimum'
      : '${_money(minSubtotalCents)} minimum subtotal';

  String get usageLabel => usageLimit == null
      ? '$timesRedeemed claimed · Unlimited'
      : '$timesRedeemed / $usageLimit';

  String? get startsLabel =>
      startsAt == null ? null : PelinesTime.formatDateTime(startsAt!);
  String? get endsLabel =>
      endsAt == null ? null : PelinesTime.formatDateTime(endsAt!);

  static String _money(int cents) =>
      NumberFormat.currency(symbol: r'$').format(cents / 100);
}

String _string(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Invalid $key.');
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value == null) return null;
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Invalid $key.');
}

String _allowed(Map<String, dynamic> json, String key, Set<String> allowed) {
  final String value = _string(json, key);
  if (allowed.contains(value)) return value;
  throw FormatException('Invalid $key.');
}

int _integer(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is int) return value;
  throw FormatException('Invalid $key.');
}

int? _optionalInteger(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value == null || value is int) return value as int?;
  throw FormatException('Invalid $key.');
}

bool _boolean(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is bool) return value;
  throw FormatException('Invalid $key.');
}

DateTime _date(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is! String) throw FormatException('Invalid $key.');
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null || !value.contains(RegExp(r'(Z|[+-]\d\d:\d\d)$'))) {
    throw FormatException('Invalid $key.');
  }
  return parsed.toUtc();
}

DateTime? _optionalDate(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _date(json, key);
