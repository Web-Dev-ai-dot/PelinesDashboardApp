import 'dart:convert';

enum PickupOrderKind { regular, catering }

enum AutoCancellationUnit { minutes, hours }

class UnsupportedAutoCancellationFormat implements Exception {
  const UnsupportedAutoCancellationFormat();
  @override
  String toString() =>
      'These auto-cancel settings have an unsupported format. Reload before editing.';
}

class AutoCancellationRule {
  const AutoCancellationRule({
    required this.enabled,
    required this.value,
    required this.unit,
  });
  final bool enabled;
  final int value;
  final AutoCancellationUnit unit;
  int get effectiveMinutes =>
      value * (unit == AutoCancellationUnit.hours ? 60 : 1);

  factory AutoCancellationRule.fromJson(
    Map<String, dynamic>? json,
    PickupOrderKind kind,
  ) {
    final prefix = keyPrefix(kind);
    final enabled = json?['${prefix}Enabled'];
    final value = json?['${prefix}Value'];
    final unit = json?['${prefix}Unit'];
    if ((enabled != null && enabled is! bool) ||
        (value != null && value is! int) ||
        (unit != null && unit != 'minutes' && unit != 'hours')) {
      throw const UnsupportedAutoCancellationFormat();
    }
    return AutoCancellationRule(
      enabled: enabled as bool? ?? true,
      value: value as int? ?? (kind == PickupOrderKind.regular ? 10 : 12),
      unit: unit == null
          ? (kind == PickupOrderKind.regular
                ? AutoCancellationUnit.minutes
                : AutoCancellationUnit.hours)
          : AutoCancellationUnit.values.byName(unit as String),
    );
  }

  static String keyPrefix(PickupOrderKind kind) =>
      kind == PickupOrderKind.regular
      ? 'autoCancelRegular'
      : 'autoCancelCatering';

  String? validate(PickupOrderKind kind) {
    if (!enabled) return null;
    final min = kind == PickupOrderKind.regular ? 1 : 10;
    final max = kind == PickupOrderKind.regular ? 1440 : 10080;
    final factor = unit == AutoCancellationUnit.hours ? 60 : 1;
    // Check the input before multiplication, including oversized native ints.
    if (value <= 0 || value > max ~/ factor || effectiveMinutes < min) {
      return kind == PickupOrderKind.regular
          ? 'Use a positive whole number totaling 1–1440 minutes.'
          : 'Use a positive whole number totaling 10–10080 minutes.';
    }
    return null;
  }

  bool sameAs(AutoCancellationRule other) =>
      enabled == other.enabled && value == other.value && unit == other.unit;
  bool requiresConfirmation(AutoCancellationRule original) =>
      enabled &&
      (!original.enabled || effectiveMinutes < original.effectiveMinutes);

  Map<String, dynamic> changesFrom(
    AutoCancellationRule original,
    PickupOrderKind kind,
  ) {
    final prefix = keyPrefix(kind);
    return {
      if (enabled != original.enabled) '${prefix}Enabled': enabled,
      if (value != original.value) '${prefix}Value': value,
      if (unit != original.unit) '${prefix}Unit': unit.name,
    };
  }

  /// JSON round-trip copies nested objects and lists, including unknown keys.
  Map<String, dynamic> mergeInto(
    Map<String, dynamic>? canonical,
    AutoCancellationRule original,
    PickupOrderKind kind,
  ) =>
      (jsonDecode(jsonEncode(canonical ?? <String, dynamic>{}))
            as Map<String, dynamic>)
        ..addAll(changesFrom(original, kind));
}
