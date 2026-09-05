class UnsupportedAutoAcceptFormat implements Exception {
  const UnsupportedAutoAcceptFormat();

  @override
  String toString() =>
      'These auto-accept settings contain an unsupported format and cannot be edited safely from mobile.';
}

class AutoAcceptSettings {
  AutoAcceptSettings({
    required this.regular,
    required this.catering,
    Map<String, dynamic>? preserved,
  }) : preserved = _deepCopyObject(preserved ?? const <String, dynamic>{});

  factory AutoAcceptSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return AutoAcceptSettings(regular: false, catering: false);
    }
    final Object? regular = json['autoAcceptRegular'];
    final Object? catering = json['autoAcceptCatering'];
    if ((regular != null && regular is! bool) ||
        (catering != null && catering is! bool)) {
      throw const UnsupportedAutoAcceptFormat();
    }
    return AutoAcceptSettings(
      regular: regular as bool? ?? false,
      catering: catering as bool? ?? false,
      preserved: json,
    );
  }

  final bool regular;
  final bool catering;
  final Map<String, dynamic> preserved;

  Map<String, dynamic> withChanges({
    required bool regularChanged,
    required bool regular,
    required bool cateringChanged,
    required bool catering,
  }) => <String, dynamic>{
    ..._deepCopyObject(preserved),
    if (regularChanged) 'autoAcceptRegular': regular,
    if (cateringChanged) 'autoAcceptCatering': catering,
  };
}

Map<String, dynamic> _deepCopyObject(Map<String, dynamic> source) => source.map(
  (String key, dynamic value) =>
      MapEntry<String, dynamic>(key, _deepCopyValue(value)),
);

dynamic _deepCopyValue(dynamic value) {
  if (value is Map<String, dynamic>) return _deepCopyObject(value);
  if (value is List<dynamic>) {
    return value.map<dynamic>(_deepCopyValue).toList();
  }
  return value;
}
