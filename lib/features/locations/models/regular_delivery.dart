class UnsupportedRegularDeliveryFormat implements Exception {
  const UnsupportedRegularDeliveryFormat();
  @override
  String toString() =>
      'These delivery settings contain an unsupported format and cannot be edited safely from mobile.';
}

class RegularDeliverySettings {
  RegularDeliverySettings({
    required this.enabled,
    required this.feeCents,
    required this.minimumCents,
    Map<String, dynamic>? preserved,
  }) : preserved = Map<String, dynamic>.from(preserved ?? const {});

  factory RegularDeliverySettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return RegularDeliverySettings(
        enabled: false,
        feeCents: 0,
        minimumCents: 0,
      );
    }
    final Object? enabled = json['enabled'];
    final Object? fee = json['feeCents'];
    final Object? minimum = json['minimumCents'];
    if ((enabled != null && enabled is! bool) ||
        (fee != null && (fee is! int || fee < 0)) ||
        (minimum != null && (minimum is! int || minimum < 0))) {
      throw const UnsupportedRegularDeliveryFormat();
    }
    return RegularDeliverySettings(
      enabled: enabled as bool? ?? false,
      feeCents: fee as int? ?? 0,
      minimumCents: minimum as int? ?? 0,
      preserved: json,
    );
  }

  final bool enabled;
  final int feeCents;
  final int minimumCents;
  final Map<String, dynamic> preserved;

  Map<String, dynamic> toJson() => <String, dynamic>{
    ...preserved,
    'enabled': enabled,
    'feeCents': feeCents,
    'minimumCents': minimumCents,
  };
}

int? parseMoneyCents(String input) {
  final RegExpMatch? match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$')
      .firstMatch(input.trim());
  if (match == null) return null;
  final int dollars = int.parse(match.group(1)!);
  final String fraction = (match.group(2) ?? '').padRight(2, '0');
  return dollars * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
}

String moneyInput(int cents) =>
    '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
