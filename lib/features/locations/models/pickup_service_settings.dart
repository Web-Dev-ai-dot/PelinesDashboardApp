import 'auto_accept.dart';
import 'auto_cancellation.dart';
import 'pickup_service_preferences.dart';

/// One card combines existing fields; no new wire fields or defaults.
class PickupServiceSettings {
  const PickupServiceSettings({
    required this.preferences,
    required this.autoAccept,
    required this.cancellation,
  });
  final PickupServicePreferences preferences;
  final bool autoAccept;
  final AutoCancellationRule cancellation;

  factory PickupServiceSettings.fromJson(
    Map<String, dynamic>? json,
    PickupOrderKind kind,
  ) {
    final auto = AutoAcceptSettings.fromJson(json);
    return PickupServiceSettings(
      preferences: PickupServicePreferences.fromJson(json, kind),
      autoAccept: kind == PickupOrderKind.regular
          ? auto.regular
          : auto.catering,
      cancellation: AutoCancellationRule.fromJson(json, kind),
    );
  }
  String? validate(PickupOrderKind kind) =>
      preferences.validate() ?? cancellation.validate(kind);
  bool sameAs(PickupServiceSettings other) =>
      preferences.sameAs(other.preferences) &&
      autoAccept == other.autoAccept &&
      cancellation.sameAs(other.cancellation);
  Map<String, dynamic> changesFrom(
    PickupServiceSettings original,
    PickupOrderKind kind,
  ) => {
    ...preferences.changesFrom(original.preferences, kind),
    ...cancellation.changesFrom(original.cancellation, kind),
    if (autoAccept != original.autoAccept)
      'autoAccept${PickupServicePreferences.suffix(kind)}': autoAccept,
  };
  Map<String, dynamic> mergeInto(
    Map<String, dynamic>? canonical,
    PickupServiceSettings original,
    PickupOrderKind kind,
  ) =>
      preferences.mergeInto(canonical, original.preferences, kind)
        ..addAll(changesFrom(original, kind));
}
