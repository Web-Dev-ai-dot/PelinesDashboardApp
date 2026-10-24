import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../models/orders_date_filter.dart';

Future<(DateTime?, DateTime?)?> showUpcomingDateRange(
  BuildContext context,
  DateTime? from,
  DateTime? to,
) => showDialog<(DateTime?, DateTime?)>(
  context: context,
  builder: (_) => _UpcomingRangeDialog(from: from, to: to),
);

class _UpcomingRangeDialog extends StatefulWidget {
  const _UpcomingRangeDialog({this.from, this.to});
  final DateTime? from, to;

  @override
  State<_UpcomingRangeDialog> createState() => _UpcomingRangeDialogState();
}

/// Local to Upcoming: draws a continuous range without changing other pickers.
class UpcomingRangeCalendar extends StatefulWidget {
  const UpcomingRangeCalendar({
    super.key,
    required this.initialDate,
    required this.currentDate,
    required this.firstDate,
    required this.lastDate,
    required this.from,
    required this.to,
    required this.onDateChanged,
  });
  final DateTime initialDate, currentDate, firstDate, lastDate, from;
  final DateTime? to;
  final ValueChanged<DateTime> onDateChanged;

  @override
  State<UpcomingRangeCalendar> createState() => _UpcomingRangeCalendarState();
}

class _UpcomingRangeCalendarState extends State<UpcomingRangeCalendar> {
  // Bounds are calendar coordinates, independent of the device's UTC offset.
  DateTime _dayCoordinate(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
  late DateTime _month = DateTime.utc(
    widget.initialDate.year,
    widget.initialDate.month,
  );

  Future<void> _pickYear() async {
    final year = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        content: SizedBox(
          width: 300,
          height: 300,
          child: YearPicker(
            firstDate: widget.firstDate,
            lastDate: widget.lastDate,
            selectedDate: _month,
            onChanged: (date) => Navigator.pop(context, date.year),
          ),
        ),
      ),
    );
    if (year == null || !mounted) return;
    setState(() {
      var month = DateTime.utc(year, _month.month);
      final first = DateTime.utc(widget.firstDate.year, widget.firstDate.month);
      final last = DateTime.utc(widget.lastDate.year, widget.lastDate.month);
      if (month.isBefore(first)) month = first;
      if (month.isAfter(last)) month = last;
      _month = month;
    });
  }

  @override
  Widget build(BuildContext context) {
    final local = MaterialLocalizations.of(context);
    final offset = (_month.weekday % 7 - local.firstDayOfWeekIndex + 7) % 7;
    final count = DateTime.utc(_month.year, _month.month + 1, 0).day;
    final rows = ((offset + count) / 7).ceil();
    final previous = DateTime.utc(_month.year, _month.month - 1);
    final next = DateTime.utc(_month.year, _month.month + 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                key: const Key('upcoming-range-month'),
                onPressed: _pickYear,
                child: Text(local.formatMonthYear(_month)),
              ),
            ),
            IconButton(
              key: const Key('upcoming-range-previous'),
              tooltip: local.previousMonthTooltip,
              onPressed:
                  previous.year < widget.firstDate.year ||
                      (previous.year == widget.firstDate.year &&
                          previous.month < widget.firstDate.month)
                  ? null
                  : () => setState(() => _month = previous),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              key: const Key('upcoming-range-next'),
              tooltip: local.nextMonthTooltip,
              onPressed: next.isAfter(_dayCoordinate(widget.lastDate))
                  ? null
                  : () => setState(() => _month = next),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: ExcludeSemantics(
                  child: Center(
                    child: Text(
                      local.narrowWeekdays[(local.firstDayOfWeekIndex + i) % 7],
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (var column = 0; column < 7; column++)
                Expanded(
                  child: _day(row * 7 + column - offset + 1, count, local),
                ),
            ],
          ),
      ],
    );
  }

  Widget _day(int day, int count, MaterialLocalizations local) {
    if (day < 1 || day > count) return const SizedBox(height: 48);
    final date = DateTime.utc(_month.year, _month.month, day);
    final enabled =
        !date.isBefore(_dayCoordinate(widget.firstDate)) &&
        !date.isAfter(_dayCoordinate(widget.lastDate));
    final start = DateUtils.isSameDay(date, widget.from);
    final end = DateUtils.isSameDay(date, widget.to);
    final inside =
        widget.to != null &&
        !date.isBefore(_dayCoordinate(widget.from)) &&
        !date.isAfter(_dayCoordinate(widget.to!));
    final endpoint = start || end;
    final today = DateUtils.isSameDay(date, widget.currentDate);
    return Semantics(
      key: ValueKey('upcoming-range-day-${date.year}-${date.month}-$day'),
      button: true,
      enabled: enabled,
      selected: endpoint || inside,
      label:
          '${local.formatFullDate(date)}${start ? ', ${tr(context, 'Start date')}' : ''}${end ? ', ${tr(context, 'End date')}' : ''}${inside && !endpoint ? ', ${tr(context, 'Date range')}' : ''}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: enabled ? () => widget.onDateChanged(date) : null,
          child: SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (inside && !(start && end))
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (start) const Spacer(),
                        Expanded(
                          child: ColoredBox(
                            key: ValueKey('upcoming-range-band-$day'),
                            color: PelinesColors.brandPrimarySoft,
                          ),
                        ),
                        if (end) const Spacer(),
                      ],
                    ),
                  ),
                Container(
                  key: ValueKey('upcoming-range-marker-$day'),
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: endpoint ? PelinesColors.brandPrimary : null,
                    border: today && !endpoint
                        ? Border.all(color: PelinesColors.brandPrimary)
                        : null,
                  ),
                  child: Text(
                    local.formatDecimal(day),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: !enabled
                          ? PelinesColors.textSecondary
                          : endpoint
                          ? PelinesColors.card
                          : PelinesColors.textPrimary,
                      fontWeight: endpoint ? FontWeight.w700 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpcomingRangeDialogState extends State<_UpcomingRangeDialog> {
  late DateTime? _from = widget.from, _to = widget.to;
  late bool _openEnded = widget.to == null;
  bool _awaitingEnd = false;
  final _today = pacificDate(PelinesTime.now());
  late final _tomorrow = DateTime.utc(
    _today.year,
    _today.month,
    _today.day + 1,
  );

  @override
  Widget build(BuildContext context) {
    final format = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final start = _from ?? _tomorrow;
    final end = _openEnded ? null : _to;
    final valid = _openEnded || (end != null && !start.isAfter(end));

    return Dialog(
      key: const Key('upcoming-range-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      backgroundColor: PelinesColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PelinesRadius.dialog),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  tr(context, 'Date range'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  '${_from == null ? tr(context, 'Tomorrow') : format.format(_from!)} — ${end == null ? tr(context, _openEnded ? 'No end date' : 'Select end date') : format.format(end)}',
                ),
              ),
              SwitchListTile(
                key: const Key('upcoming-range-no-end'),
                contentPadding: EdgeInsets.zero,
                title: Text(tr(context, 'No end date')),
                value: _openEnded,
                onChanged: (value) => setState(() {
                  _openEnded = value;
                  _to = null;
                  _awaitingEnd = !value;
                }),
              ),
              UpcomingRangeCalendar(
                currentDate: _today,
                initialDate: start.isBefore(_tomorrow) ? _tomorrow : start,
                firstDate: _tomorrow,
                lastDate: DateTime(2100, 12, 31),
                from: start,
                to: end,
                onDateChanged: (value) => setState(() {
                  final day = DateTime.utc(value.year, value.month, value.day);
                  if (_openEnded || !_awaitingEnd || day.isBefore(start)) {
                    _from = day;
                    _to = null;
                    _awaitingEnd = !_openEnded;
                  } else {
                    _to = day;
                    _awaitingEnd = false;
                  }
                }),
              ),
              if (!valid && end != null)
                Text(
                  tr(context, 'From must be on or before To.'),
                  style: const TextStyle(color: PelinesColors.destructive),
                ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    key: const Key('upcoming-range-cancel'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr(context, 'Cancel')),
                  ),
                  FilledButton(
                    key: const Key('upcoming-range-confirm'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: valid
                        ? () => Navigator.pop(context, (_from, end))
                        : null,
                    child: Text(tr(context, 'Confirm')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
