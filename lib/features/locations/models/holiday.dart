import 'temporary_closure.dart';

class UnsupportedHolidayFormat implements Exception {
  const UnsupportedHolidayFormat();
  @override
  String toString() =>
      'These holidays contain an unsupported format and cannot be edited safely.';
}

class Holiday {
  Holiday({
    required this.id,
    required this.name,
    required this.date,
    required this.status,
    required this.customOpen,
    required this.customClose,
    required this.notes,
    Map<String, dynamic>? preserved,
  }) : preserved = Map.unmodifiable(preserved ?? const {});
  final String id, name, date, status, customOpen, customClose, notes;
  final Map<String, dynamic> preserved;
  factory Holiday.fromJson(Map<String, dynamic> json) {
    for (final key in ['id', 'date', 'status']) {
      if (json[key] is! String) throw const UnsupportedHolidayFormat();
    }
    for (final key in ['name', 'customOpen', 'customClose', 'notes']) {
      if (json[key] != null && json[key] is! String) {
        throw const UnsupportedHolidayFormat();
      }
    }
    if ((json['id'] as String).isEmpty ||
        !['open', 'closed'].contains(json['status'])) {
      throw const UnsupportedHolidayFormat();
    }
    return Holiday(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      date: json['date'] as String,
      status: json['status'] as String,
      customOpen: json['customOpen'] as String? ?? '',
      customClose: json['customClose'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      preserved: json,
    );
  }
  Holiday copyWith({
    String? name,
    String? date,
    String? status,
    String? customOpen,
    String? customClose,
    String? notes,
  }) => Holiday(
    id: id,
    name: name ?? this.name,
    date: date ?? this.date,
    status: status ?? this.status,
    customOpen: customOpen ?? this.customOpen,
    customClose: customClose ?? this.customClose,
    notes: notes ?? this.notes,
    preserved: preserved,
  );
  Map<String, dynamic> toJson() => {
    ...preserved,
    'id': id,
    'name': name,
    'date': date,
    'status': status,
    'customOpen': customOpen,
    'customClose': customClose,
    'notes': notes,
  };
}

List<Holiday> holidaysFromExtras(Map<String, dynamic>? extras) {
  if (extras == null || !extras.containsKey('holidays')) return [];
  final raw = extras['holidays'];
  if (raw is! List) throw const UnsupportedHolidayFormat();
  final result = <Holiday>[];
  final ids = <String>{};
  for (final value in raw) {
    if (value is! Map<String, dynamic>) throw const UnsupportedHolidayFormat();
    final holiday = Holiday.fromJson(value);
    if (!ids.add(holiday.id)) throw const UnsupportedHolidayFormat();
    result.add(holiday);
  }
  return result;
}

String? validateHolidays(List<Holiday> holidays) {
  final dates = <String>{};
  final ids = <String>{};
  for (final h in holidays) {
    if (h.id.isEmpty || !ids.add(h.id)) {
      return 'Holiday identifiers must be unique.';
    }
    if (h.name.trim().isEmpty) return 'Enter a holiday name.';
    if (parseCalendarDate(h.date) == null || h.date.startsWith('0000')) {
      return 'Choose a valid holiday date.';
    }
    if (!dates.add(h.date)) {
      return 'Each date can have only one holiday per location.';
    }
    if (!['open', 'closed'].contains(h.status)) return 'Choose Open or Closed.';
    if (h.status == 'open') {
      final pattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
      if (!pattern.hasMatch(h.customOpen) || !pattern.hasMatch(h.customClose)) {
        return 'Choose valid opening and closing times.';
      }
      if (h.customOpen.compareTo(h.customClose) >= 0) {
        return 'Closing time must be after opening time on the same date.';
      }
    }
  }
  return null;
}

bool sameHolidays(List<Holiday> a, List<Holiday> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if (x.id != y.id ||
        x.name != y.name ||
        x.date != y.date ||
        x.status != y.status ||
        x.customOpen != y.customOpen ||
        x.customClose != y.customClose ||
        x.notes != y.notes) {
      return false;
    }
  }
  return true;
}
