const List<String> businessDayKeys = <String>[
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
  'sun',
];
const List<String> businessDayLabels = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

class BusinessDayHours {
  const BusinessDayHours({
    required this.open,
    required this.close,
    required this.closed,
  });
  final String open;
  final String close;
  final bool closed;

  BusinessDayHours copyWith({String? open, String? close, bool? closed}) =>
      BusinessDayHours(
        open: open ?? this.open,
        close: close ?? this.close,
        closed: closed ?? this.closed,
      );
}

class BusinessHoursSchedule {
  BusinessHoursSchedule(List<BusinessDayHours> days)
    : days = List.unmodifiable(days) {
    if (days.length != 7) throw ArgumentError('Seven days are required.');
  }

  factory BusinessHoursSchedule.fromJson(Map<String, dynamic> json) {
    return BusinessHoursSchedule(<BusinessDayHours>[
      for (final String key in businessDayKeys) _parseDay(json[key]),
    ]);
  }

  factory BusinessHoursSchedule.dashboardDefault() => BusinessHoursSchedule(
    List<BusinessDayHours>.generate(
      7,
      (_) =>
          const BusinessDayHours(open: '11:00', close: '22:00', closed: false),
    ),
  );

  final List<BusinessDayHours> days;

  Map<String, dynamic> toJson() => <String, dynamic>{
    for (int index = 0; index < 7; index++)
      businessDayKeys[index]: days[index].closed
          ? null
          : <String, String>{
              'open': days[index].open,
              'close': days[index].close,
            },
  };

  BusinessHoursSchedule replaceDay(int index, BusinessDayHours day) =>
      BusinessHoursSchedule(<BusinessDayHours>[
        for (int current = 0; current < days.length; current++)
          current == index ? day : days[current],
      ]);

  String? validate() {
    for (int index = 0; index < days.length; index++) {
      final BusinessDayHours day = days[index];
      if (day.closed) {
        continue;
      }
      final int? open = _minutes(day.open);
      final int? close = _minutes(day.close);
      if (open == null || close == null) {
        return '${businessDayLabels[index]} has an invalid time.';
      }
      if (open >= close) {
        return 'Overnight hours are not supported by the current ordering system.';
      }
    }
    return null;
  }

  bool sameAs(BusinessHoursSchedule other) {
    for (int index = 0; index < 7; index++) {
      final BusinessDayHours a = days[index];
      final BusinessDayHours b = other.days[index];
      if (a.open != b.open || a.close != b.close || a.closed != b.closed) {
        return false;
      }
    }
    return true;
  }

  static BusinessDayHours _parseDay(Object? value) {
    if (value == null) {
      return const BusinessDayHours(
        open: '11:00',
        close: '22:00',
        closed: true,
      );
    }
    if (value is! Map<String, dynamic> ||
        value['open'] is! String ||
        value['close'] is! String) {
      throw const FormatException('Unsupported business hours format.');
    }
    final BusinessDayHours day = BusinessDayHours(
      open: value['open'] as String,
      close: value['close'] as String,
      closed: false,
    );
    if (_minutes(day.open) == null || _minutes(day.close) == null) {
      throw const FormatException('Unsupported business hours format.');
    }
    return day;
  }
}

int? _minutes(String value) {
  final RegExpMatch? match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$')
      .firstMatch(value);
  if (match == null) return null;
  return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}
