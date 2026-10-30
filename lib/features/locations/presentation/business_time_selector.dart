import '../../../app/theme/app_theme.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../models/business_hours.dart';

/// Edits one day's local draft only. The weekly editor owns persistence.
Future<BusinessDayHours?> showBusinessTimeSelector(
  BuildContext context,
  BusinessDayHours day,
) => showDialog<BusinessDayHours>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _BusinessTimeSelector(day: day),
);

class _BusinessTimeSelector extends StatefulWidget {
  const _BusinessTimeSelector({required this.day});
  final BusinessDayHours day;
  @override
  State<_BusinessTimeSelector> createState() => _BusinessTimeSelectorState();
}

class _BusinessTimeSelectorState extends State<_BusinessTimeSelector> {
  late TimeOfDay opens = parse(widget.day.open),
      closes = parse(widget.day.close);
  bool opening = true, minutes = false, numeric = false;
  int? numericHour, numericMinute;
  String? error;
  TimeOfDay get value => opening ? opens : closes;
  static TimeOfDay parse(String text) {
    final parts = text.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String format(TimeOfDay t) =>
      MaterialLocalizations.of(context)
          .formatTimeOfDay(t, alwaysUse24HourFormat: false);
  String stored(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  void update(TimeOfDay t) => setState(() {
    if (opening) {
      opens = t;
    } else {
      closes = t;
    }
    error = null;
  });
  void choose(int number, {bool advance = true}) {
    if (minutes) {
      update(TimeOfDay(hour: value.hour, minute: number));
    } else {
      update(
        TimeOfDay(
          hour: number % 12 + (value.period == DayPeriod.pm ? 12 : 0),
          minute: value.minute,
        ),
      );
      if (advance) setState(() => minutes = true);
    }
  }

  void pointer(Offset position, double size, {bool advance = false}) {
    final angle =
        (math.atan2(position.dy - size / 2, position.dx - size / 2) +
            math.pi / 2 +
            math.pi * 2) %
        (math.pi * 2);
    final count = minutes ? 60 : 12;
    choose((angle / (math.pi * 2) * count).round() % count, advance: advance);
  }

  Widget _numericField(bool minute) => SizedBox(
    width: 128,
    child: TextFormField(
      key: ValueKey(
        minute ? 'business-time-number-minute' : 'business-time-number-hour',
      ),
      initialValue: minute
          ? '${value.minute}'
          : '${value.hourOfPeriod == 0 ? 12 : value.hourOfPeriod}',
      keyboardType: TextInputType.number,
      decoration: PelinesControlStyles.input(
        label: tr(context, minute ? 'Minutes' : 'Hours'),
      ),
      onChanged: (text) {
        final number = int.tryParse(text);
        if (minute) {
          numericMinute = number;
        } else {
          numericHour = number;
        }
        if (number == null ||
            (minute
                ? (number < 0 || number > 59)
                : (number < 1 || number > 12))) {
          return;
        }
        update(
          minute
              ? TimeOfDay(hour: value.hour, minute: number)
              : TimeOfDay(
                  hour: number % 12 + (value.period == DayPeriod.pm ? 12 : 0),
                  minute: value.minute,
                ),
        );
      },
    ),
  );

  Widget _rangeSegments() => Container(
    key: const ValueKey('time-range-segments'),
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: PelinesColors.mutedSurface,
      borderRadius: BorderRadius.circular(PelinesRadius.control),
    ),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final isOpen in [true, false])
            Expanded(
              child: Semantics(
                selected: opening == isOpen,
                button: true,
                child: Material(
                  color: opening == isOpen
                      ? PelinesColors.card
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(PelinesRadius.control),
                  child: InkWell(
                    key: ValueKey(isOpen ? 'time-opens' : 'time-closes'),
                    borderRadius: BorderRadius.circular(PelinesRadius.control),
                    onTap: () => setState(() {
                      opening = isOpen;
                      minutes = false;
                      numeric = false;
                    }),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Text(
                        '${tr(context, isOpen ? 'Opens' : 'Closes')}: ${format(isOpen ? opens : closes)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: opening == isOpen
                              ? PelinesColors.brandPrimary
                              : PelinesColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _periodControl() => ClipRRect(
    borderRadius: BorderRadius.circular(PelinesRadius.control),
    child: Container(
      key: const ValueKey('time-period-segments'),
      decoration: BoxDecoration(
        border: Border.all(color: PelinesColors.border),
        borderRadius: BorderRadius.circular(PelinesRadius.control),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final period in DayPeriod.values)
            Semantics(
              selected: value.period == period,
              button: true,
              child: Material(
                color: value.period == period
                    ? PelinesColors.brandPrimary
                    : PelinesColors.card,
                child: InkWell(
                  key: ValueKey('time-${period.name}'),
                  onTap: () => update(
                    TimeOfDay(
                      hour: value.hour % 12 + (period == DayPeriod.pm ? 12 : 0),
                      minute: value.minute,
                    ),
                  ),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Text(
                      period.name.toUpperCase(),
                      style: TextStyle(
                        color: value.period == period
                            ? Colors.white
                            : PelinesColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _clockNumber(bool minute) => SizedBox(
    height: 100,
    child: OutlinedButton(
      key: ValueKey(minute ? 'time-minutes' : 'time-hour'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(8),
        backgroundColor: minutes == minute
            ? PelinesColors.brandPrimarySoft
            : PelinesColors.mutedSurface,
        foregroundColor: minutes == minute
            ? PelinesColors.brandPrimary
            : PelinesColors.textPrimary,
        side: BorderSide(
          color: minutes == minute
              ? PelinesColors.brandPrimarySoft
              : PelinesColors.border,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PelinesRadius.prominentCard),
        ),
      ),
      onPressed: () => setState(() => minutes = minute),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          minute
              ? value.minute.toString().padLeft(2, '0')
              : '${value.hourOfPeriod == 0 ? 12 : value.hourOfPeriod}',
          style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold),
        ),
      ),
    ),
  );

  Widget _timeControls() => LayoutBuilder(
    builder: (context, c) {
      final periodWidth = MediaQuery.textScalerOf(context).scale(64);
      final numbers = Row(
        children: [
          Expanded(child: _clockNumber(false)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              ':',
              key: ValueKey('time-colon'),
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: _clockNumber(true)),
        ],
      );
      if (numeric) {
        return Wrap(
          spacing: 8,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _numericField(false),
            _numericField(true),
            SizedBox(width: periodWidth, child: _periodControl()),
          ],
        );
      }
      if (MediaQuery.textScalerOf(context).scale(1) > 1.4 || c.maxWidth < 240) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            numbers,
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(width: periodWidth, child: _periodControl()),
            ),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: numbers),
          const SizedBox(width: 14),
          SizedBox(width: periodWidth, child: _periodControl()),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: PelinesColors.card,
    insetPadding: const EdgeInsets.all(16),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(PelinesRadius.dialog),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr(context, 'Select time'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: tr(context, 'Close'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _rangeSegments(),
            const SizedBox(height: 20),
            _timeControls(),
            const SizedBox(height: 16),
            if (!numeric)
              LayoutBuilder(
                builder: (context, constraints) {
                  final size = math.min(280.0, constraints.maxWidth);
                  final labels = minutes
                      ? List.generate(12, (i) => i * 5)
                      : List.generate(12, (i) => i == 0 ? 12 : i);
                  return Center(
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: GestureDetector(
                        key: const ValueKey('business-time-dial'),
                        onTapUp: (d) =>
                            pointer(d.localPosition, size, advance: true),
                        onPanStart: (d) => pointer(d.localPosition, size),
                        onPanUpdate: (d) => pointer(d.localPosition, size),
                        onPanEnd: (_) {
                          if (!minutes) setState(() => minutes = true);
                        },
                        child: CustomPaint(
                          painter: _DialHand(
                            (minutes
                                    ? value.minute / 60
                                    : value.hour % 12 / 12) *
                                math.pi *
                                2,
                          ),
                          child: Stack(
                            children: [
                              for (var i = 0; i < labels.length; i++)
                                Positioned(
                                  left:
                                      size / 2 +
                                      math.sin(i * math.pi / 6) *
                                          (size / 2 - 28) -
                                      24,
                                  top:
                                      size / 2 -
                                      math.cos(i * math.pi / 6) *
                                          (size / 2 - 28) -
                                      24,
                                  width: 48,
                                  height: 48,
                                  child: Semantics(
                                    label:
                                        '${tr(context, minutes ? 'Minutes' : 'Hours')}: ${labels[i]}',
                                    button: true,
                                    child: TextButton(
                                      key: ValueKey(
                                        'dial-${minutes ? 'minute' : 'hour'}-${labels[i]}',
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        backgroundColor:
                                            (minutes
                                                ? value.minute == labels[i]
                                                : value.hour % 12 ==
                                                      labels[i] % 12)
                                            ? PelinesColors.brandPrimary
                                            : null,
                                        foregroundColor:
                                            (minutes
                                                ? value.minute == labels[i]
                                                : value.hour % 12 ==
                                                      labels[i] % 12)
                                            ? Colors.white
                                            : PelinesColors.textPrimary,
                                        shape: const CircleBorder(),
                                      ),
                                      onPressed: () => choose(labels[i]),
                                      child: Text('${labels[i]}'),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            TextButton.icon(
              key: const ValueKey('business-time-keyboard'),
              style: TextButton.styleFrom(
                foregroundColor: PelinesColors.textSecondary,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
              ),
              icon: const Icon(Icons.keyboard_outlined),
              label: Text(tr(context, 'Pelines Time Control')),
              onPressed: () => setState(() {
                numeric = !numeric;
                numericHour = value.hourOfPeriod == 0 ? 12 : value.hourOfPeriod;
                numericMinute = value.minute;
                error = null;
              }),
            ),
            if (error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  tr(context, error!),
                  style: const TextStyle(color: PelinesColors.destructive),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('business-time-save'),
              style: FilledButton.styleFrom(
                backgroundColor: PelinesColors.brandPrimary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: const StadiumBorder(),
              ),
              onPressed: () {
                if (numeric &&
                    (numericHour == null ||
                        numericMinute == null ||
                        numericHour! < 1 ||
                        numericHour! > 12 ||
                        numericMinute! < 0 ||
                        numericMinute! > 59)) {
                  setState(
                    () => error =
                        'Enter an hour from 1 to 12 and minutes from 0 to 59.',
                  );
                  return;
                }
                final day = widget.day.copyWith(
                  open: stored(opens),
                  close: stored(closes),
                );
                final validation = BusinessHoursSchedule(List.filled(7, day))
                    .validate();
                if (validation != null) {
                  setState(() => error = validation);
                  return;
                }
                Navigator.pop(context, day);
              },
              child: Text(tr(context, 'Save')),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DialHand extends CustomPainter {
  _DialHand(this.angle);
  final double angle;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      center,
      size.width / 2,
      Paint()..color = PelinesColors.card,
    );
    canvas.drawCircle(
      center,
      size.width / 2 - .5,
      Paint()
        ..color = PelinesColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      center,
      center +
          Offset(math.sin(angle), -math.cos(angle)) * (size.width / 2 - 28),
      Paint()
        ..color = PelinesColors.brandPrimary
        ..strokeWidth = 3,
    );
    canvas.drawCircle(center, 5, Paint()..color = PelinesColors.brandPrimary);
  }

  @override
  bool shouldRepaint(_DialHand old) => angle != old.angle;
}
