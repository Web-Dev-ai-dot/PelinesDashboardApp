import 'package:timezone/timezone.dart' as tz;

import '../../../core/time/pelines_time.dart';
import 'discount.dart';

class PromotionDraft {
  const PromotionDraft({
    required this.code,
    required this.type,
    required this.valueText,
    required this.appliesTo,
    required this.minimumText,
    required this.startDate,
    required this.endDate,
    required this.usageLimitText,
    required this.unlimited,
    required this.isActive,
  });

  factory PromotionDraft.create() => const PromotionDraft(
    code: '',
    type: 'percent',
    valueText: '',
    appliesTo: 'both',
    minimumText: '0',
    startDate: null,
    endDate: null,
    usageLimitText: '',
    unlimited: true,
    isActive: true,
  );

  factory PromotionDraft.fromDiscount(Discount value) => PromotionDraft(
    code: value.code,
    type: value.type,
    valueText: value.type == 'percent'
        ? value.value.toString()
        : moneyInput(value.value),
    appliesTo: value.appliesTo,
    minimumText: moneyInput(value.minSubtotalCents),
    startDate: value.startsAt == null
        ? null
        : pacificCalendarDate(value.startsAt!),
    endDate: value.endsAt == null ? null : pacificCalendarDate(value.endsAt!),
    usageLimitText: value.usageLimit?.toString() ?? '',
    unlimited: value.usageLimit == null,
    isActive: value.isActive,
  );

  final String code;
  final String type;
  final String valueText;
  final String appliesTo;
  final String minimumText;
  final DateTime? startDate;
  final DateTime? endDate;
  final String usageLimitText;
  final bool unlimited;
  final bool isActive;

  PromotionWriteResult validate(String locationId) {
    final String normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) {
      return const PromotionWriteResult.error('Enter a promotion code.');
    }
    if (normalizedCode.length > 40) {
      return const PromotionWriteResult.error(
        'Promotion code must be 40 characters or fewer.',
      );
    }
    if (!RegExp(r'^[A-Z0-9_-]+$').hasMatch(normalizedCode)) {
      return const PromotionWriteResult.error(
        'Use only letters, numbers, hyphens, and underscores in the code.',
      );
    }
    if (locationId.isEmpty) {
      return const PromotionWriteResult.error(
        'Reopen this form from a valid location.',
      );
    }
    final int? parsedValue = type == 'percent'
        ? parseWholeNumber(valueText, minimum: 1, maximum: 100)
        : parseMoneyCents(valueText, allowZero: false);
    if (parsedValue == null) {
      return PromotionWriteResult.error(
        type == 'percent'
            ? 'Percentage must be a whole number from 1 to 100.'
            : 'Enter a fixed amount greater than zero with up to 2 decimals.',
      );
    }
    final int? minimum = parseMoneyCents(minimumText, allowZero: true);
    if (minimum == null) {
      return const PromotionWriteResult.error(
        'Enter a valid minimum subtotal with up to 2 decimals.',
      );
    }
    if (startDate != null &&
        endDate != null &&
        _dateOnly(startDate!).isAfter(_dateOnly(endDate!))) {
      return const PromotionWriteResult.error(
        'Start date must be on or before end date.',
      );
    }
    final int? usage = unlimited
        ? null
        : parseWholeNumber(usageLimitText, minimum: 1);
    if (!unlimited && usage == null) {
      return const PromotionWriteResult.error(
        'Usage limit must be a whole number of at least 1.',
      );
    }
    return PromotionWriteResult.valid(<String, dynamic>{
      'code': normalizedCode,
      'type': type,
      'value': parsedValue,
      'minSubtotalCents': minimum,
      'startsAt': startDate == null
          ? null
          : pacificStartOfDayUtc(startDate!).toIso8601String(),
      'endsAt': endDate == null
          ? null
          : pacificEndOfDayUtc(endDate!).toIso8601String(),
      'usageLimit': usage,
      'locationId': locationId,
      'appliesTo': appliesTo,
      'isActive': isActive,
    });
  }
}

class PromotionWriteResult {
  const PromotionWriteResult.valid(this.body) : message = null;
  const PromotionWriteResult.error(this.message) : body = null;
  final Map<String, dynamic>? body;
  final String? message;
  bool get isValid => body != null;
}

int? parseMoneyCents(String input, {required bool allowZero}) {
  final RegExpMatch? match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$')
      .firstMatch(input.trim());
  if (match == null) return null;
  final int? dollars = int.tryParse(match.group(1)!);
  if (dollars == null) return null;
  final String fraction = (match.group(2) ?? '').padRight(2, '0');
  final int cents =
      dollars * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
  if (cents < 0 || (!allowZero && cents == 0)) return null;
  return cents;
}

int? parseWholeNumber(String input, {required int minimum, int? maximum}) {
  final String value = input.trim();
  if (!RegExp(r'^\d+$').hasMatch(value)) return null;
  final int? parsed = int.tryParse(value);
  if (parsed == null ||
      parsed < minimum ||
      (maximum != null && parsed > maximum)) {
    return null;
  }
  return parsed;
}

String moneyInput(int cents) =>
    '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

DateTime pacificCalendarDate(DateTime instant) {
  final tz.TZDateTime local = PelinesTime.inPacific(instant);
  return DateTime(local.year, local.month, local.day);
}

DateTime pacificStartOfDayUtc(DateTime date) {
  PelinesTime.initialize();
  final tz.Location zone = tz.getLocation(PelinesTime.zoneName);
  return tz.TZDateTime(zone, date.year, date.month, date.day).toUtc();
}

DateTime pacificEndOfDayUtc(DateTime date) {
  PelinesTime.initialize();
  final tz.Location zone = tz.getLocation(PelinesTime.zoneName);
  return tz.TZDateTime(
    zone,
    date.year,
    date.month,
    date.day,
    23,
    59,
    59,
    999,
  ).toUtc();
}

Map<String, dynamic> partialPromotionPatch(
  Map<String, dynamic> canonical,
  Map<String, dynamic> desired,
) {
  const Set<String> editable = <String>{
    'code',
    'type',
    'value',
    'minSubtotalCents',
    'startsAt',
    'endsAt',
    'usageLimit',
    'appliesTo',
    'isActive',
  };
  return <String, dynamic>{
    for (final String key in editable)
      if (!_sameValue(key, canonical[key], desired[key])) key: desired[key],
  };
}

Map<String, dynamic> discountEditableBody(Discount value) => <String, dynamic>{
  'code': value.code,
  'type': value.type,
  'value': value.value,
  'minSubtotalCents': value.minSubtotalCents,
  'startsAt': value.startsAt?.toUtc().toIso8601String(),
  'endsAt': value.endsAt?.toUtc().toIso8601String(),
  'usageLimit': value.usageLimit,
  'appliesTo': value.appliesTo,
  'isActive': value.isActive,
};

bool _sameValue(String key, Object? a, Object? b) {
  if ((key == 'startsAt' || key == 'endsAt') && a != null && b != null) {
    return DateTime.parse(a as String).toUtc() ==
        DateTime.parse(b as String).toUtc();
  }
  return a == b;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
