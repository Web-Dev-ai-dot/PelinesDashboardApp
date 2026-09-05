export 'regular_delivery.dart' show moneyInput, parseMoneyCents;

class UnsupportedCateringDeliveryFormat implements Exception {
  const UnsupportedCateringDeliveryFormat();

  @override
  String toString() =>
      'These catering delivery settings contain an unsupported format and cannot be edited safely from mobile.';
}

enum CateringDeliveryEnabledState {
  defaultEnabled,
  explicitEnabled,
  explicitDisabled,
}

class CateringDeliverySettings {
  CateringDeliverySettings({
    required this.enabledState,
    Map<String, dynamic>? preserved,
  }) : preserved = Map<String, dynamic>.from(preserved ?? const {});

  factory CateringDeliverySettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return CateringDeliverySettings(
        enabledState: CateringDeliveryEnabledState.defaultEnabled,
      );
    }
    final Object? enabled = json['enabled'];
    if (enabled != null && enabled is! bool) {
      throw const UnsupportedCateringDeliveryFormat();
    }
    return CateringDeliverySettings(
      enabledState: enabled == false
          ? CateringDeliveryEnabledState.explicitDisabled
          : enabled == true
          ? CateringDeliveryEnabledState.explicitEnabled
          : CateringDeliveryEnabledState.defaultEnabled,
      preserved: json,
    );
  }

  final CateringDeliveryEnabledState enabledState;
  final Map<String, dynamic> preserved;

  bool get enabled =>
      enabledState != CateringDeliveryEnabledState.explicitDisabled;
  bool get usesDefault =>
      enabledState == CateringDeliveryEnabledState.defaultEnabled;

  Map<String, dynamic> withExplicitEnabled(bool value) => <String, dynamic>{
    ...preserved,
    'enabled': value,
  };
}
