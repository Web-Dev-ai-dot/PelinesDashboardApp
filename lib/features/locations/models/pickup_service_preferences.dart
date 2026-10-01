import 'dart:convert';

import 'auto_cancellation.dart';

class UnsupportedPickupPreferencesFormat implements Exception {
  const UnsupportedPickupPreferencesFormat();

  @override
  String toString() =>
      'These service preferences have an unsupported format. Reload before editing.';
}

/// One order-type section of servicePrefsJson. Minimum is always in dollars.
/// Missing/null values use backend defaults; malformed values block editing,
/// matching the existing Flutter Auto Accept/Auto Cancel policy.
class PickupServicePreferences {
  const PickupServicePreferences({
    required this.accept,
    required this.minimum,
    required this.capacity,
  });

  final bool accept;
  final num minimum;
  final int capacity;

  // Keep integers exact across Dart native, Dart web and JSON/JavaScript.
  static const maxSafeInteger = 9007199254740991;
  static const minimumError =
      'Enter an amount of 0 or more with up to 2 decimals.';
  static const capacityError = 'Enter a whole number of 0 or more.';

  static String suffix(PickupOrderKind kind) =>
      kind == PickupOrderKind.regular ? 'Regular' : 'Catering';

  factory PickupServicePreferences.fromJson(
    Map<String, dynamic>? json,
    PickupOrderKind kind,
  ) {
    final key = suffix(kind);
    final regular = kind == PickupOrderKind.regular;
    final accept = json?['accept$key'] ?? true;
    final minimum = json?['min$key'] ?? (regular ? 15 : 150);
    final capacity = json?['cap$key'] ?? (regular ? 80 : 6);
    if (accept is! bool ||
        minimum is! num ||
        minimumFromText(minimum.toString()) == null ||
        capacity is! num ||
        !capacity.isFinite ||
        capacity < 0 ||
        capacity > maxSafeInteger ||
        capacity != capacity.truncateToDouble()) {
      throw const UnsupportedPickupPreferencesFormat();
    }
    return PickupServicePreferences(
      accept: accept,
      minimum: minimum,
      capacity: capacity.toInt(),
    );
  }

  static num? minimumFromText(String text) {
    final input = text.trim();
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(input)) return null;
    final value = num.tryParse(input);
    if (value == null ||
        !value.isFinite ||
        value < 0 ||
        value > maxSafeInteger / 100) {
      return null;
    }
    return value;
  }

  static int? capacityFromText(String text) {
    final input = text.trim();
    if (!RegExp(r'^\d+$').hasMatch(input)) return null;
    final value = int.tryParse(input);
    if (value == null || value < 0 || value > maxSafeInteger) return null;
    return value;
  }

  String get minimumText => minimum == minimum.truncateToDouble()
      ? minimum.toInt().toString()
      : minimum.toString();

  String? validate() {
    if (minimumFromText(minimum.toString()) == null) return minimumError;
    if (capacity < 0 || capacity > maxSafeInteger) return capacityError;
    return null;
  }

  bool sameAs(PickupServicePreferences other) =>
      accept == other.accept &&
      minimum == other.minimum &&
      capacity == other.capacity;

  Map<String, dynamic> changesFrom(
    PickupServicePreferences original,
    PickupOrderKind kind,
  ) {
    final key = suffix(kind);
    return {
      if (accept != original.accept) 'accept$key': accept,
      if (minimum != original.minimum) 'min$key': minimum,
      if (capacity != original.capacity) 'cap$key': capacity,
    };
  }

  /// Preserve canonical keys, including nested unknown data and the other type.
  Map<String, dynamic> mergeInto(
    Map<String, dynamic>? canonical,
    PickupServicePreferences original,
    PickupOrderKind kind,
  ) =>
      (jsonDecode(jsonEncode(canonical ?? <String, dynamic>{}))
            as Map<String, dynamic>)
        ..addAll(changesFrom(original, kind));
}
