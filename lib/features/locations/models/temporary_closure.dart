import 'dart:math';

class UnsupportedClosureFormat implements Exception {
  const UnsupportedClosureFormat();

  @override
  String toString() =>
      'These store settings contain an unsupported format and cannot be edited safely from mobile.';
}

class TemporaryClosure {
  TemporaryClosure({
    required this.id,
    required this.reason,
    required this.start,
    required this.end,
    required this.notes,
    required this.active,
    Map<String, dynamic>? preserved,
  }) : preserved = Map<String, dynamic>.from(preserved ?? const {});

  factory TemporaryClosure.fromJson(Map<String, dynamic> json) {
    final Object? id = json['id'];
    final Object? reason = json['reason'];
    final Object? start = json['start'];
    final Object? end = json['end'];
    final Object? notes = json['notes'];
    final Object? active = json['active'];
    if (id is! String ||
        reason is! String ||
        start is! String ||
        end is! String ||
        notes is! String ||
        active is! bool ||
        parseCalendarDate(start) == null ||
        parseCalendarDate(end) == null) {
      throw const UnsupportedClosureFormat();
    }
    return TemporaryClosure(
      id: id,
      reason: reason,
      start: start,
      end: end,
      notes: notes,
      active: active,
      preserved: json,
    );
  }

  final String id;
  final String reason;
  final String start;
  final String end;
  final String notes;
  final bool active;
  final Map<String, dynamic> preserved;

  Map<String, dynamic> toJson() => <String, dynamic>{
    ...preserved,
    'id': id,
    'reason': reason,
    'start': start,
    'end': end,
    'notes': notes,
    'active': active,
  };

  TemporaryClosure copyWith({
    String? reason,
    String? start,
    String? end,
    String? notes,
    bool? active,
  }) => TemporaryClosure(
    id: id,
    reason: reason ?? this.reason,
    start: start ?? this.start,
    end: end ?? this.end,
    notes: notes ?? this.notes,
    active: active ?? this.active,
    preserved: preserved,
  );
}

List<TemporaryClosure> closuresFromExtras(Map<String, dynamic>? extras) {
  if (extras == null || !extras.containsKey('closures')) {
    return <TemporaryClosure>[];
  }
  final Object? raw = extras['closures'];
  if (raw is! List<dynamic>) throw const UnsupportedClosureFormat();
  return raw
      .map((Object? item) {
        if (item is! Map<String, dynamic>) {
          throw const UnsupportedClosureFormat();
        }
        return TemporaryClosure.fromJson(item);
      })
      .toList(growable: false);
}

DateTime? parseCalendarDate(String value) {
  final RegExpMatch? match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$')
      .firstMatch(value);
  if (match == null) return null;
  final int year = int.parse(match.group(1)!);
  final int month = int.parse(match.group(2)!);
  final int day = int.parse(match.group(3)!);
  final DateTime parsed = DateTime(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day
      ? parsed
      : null;
}

String formatCalendarDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

bool isValidClosureRange(String start, String end) {
  final DateTime? startDate = parseCalendarDate(start);
  final DateTime? endDate = parseCalendarDate(end);
  return startDate != null && endDate != null && !startDate.isAfter(endDate);
}

String newClosureId([Random? random]) {
  final Random source = random ?? Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final String hex = bytes
      .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
