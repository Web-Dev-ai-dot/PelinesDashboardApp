import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../models/order_models.dart';
import '../models/orders_date_filter.dart';
import 'upcoming_date_range.dart';

/// Local projection over loaded history. Bounds are Pacific calendar coordinates.
List<OrderSummary> filterHistoricalDateRange(
  List<OrderSummary> orders, {
  required bool completed,
  DateTime? from,
  DateTime? to,
}) => orders.where((order) {
  final day = pacificDate(
    completed ? order.deliveredAt ?? order.operationalAt : order.operationalAt,
  );
  return (from == null || !day.isBefore(from)) &&
      (to == null || !day.isAfter(to));
}).toList();

Future<(DateTime?, DateTime?)?> showHistoricalDateRange(
  BuildContext context,
  DateTime? from,
  DateTime? to,
) => showModalBottomSheet<(DateTime?, DateTime?)>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: PelinesColors.card,
  constraints: const BoxConstraints(maxWidth: 640),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
  ),
  builder: (_) => _HistoryRangeSheet(from: from, to: to),
);

class _HistoryRangeSheet extends StatefulWidget {
  const _HistoryRangeSheet({this.from, this.to});
  final DateTime? from, to;
  @override
  State<_HistoryRangeSheet> createState() => _HistoryRangeSheetState();
}

class _HistoryRangeSheetState extends State<_HistoryRangeSheet> {
  late DateTime? _from = widget.from, _to = widget.to;
  bool _invalid = false;
  String? _preset;

  @override
  void initState() {
    super.initState();
    _preset = _from == null && _to == null ? null : 'Custom range';
    for (final days in [1, 7, 30, 90]) {
      final range = historicalPresetRange(days);
      if (_from == range.$1 && _to == range.$2) {
        _preset = days == 1 ? 'Today' : 'Last $days days';
      }
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDialog<(DateTime?, DateTime?)>(
      context: context,
      builder: (_) => _HistoryRangeCalendar(from: _from, to: _to),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = picked.$1;
      _to = picked.$2;
      _invalid = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final format = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          key: const Key('history-range-sheet'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  tr(context, 'Date range'),
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 16),
              RadioGroup<String>(
                groupValue: _preset,
                onChanged: (value) => setState(() {
                  _preset = value;
                  _invalid = false;
                  final days = switch (value) {
                    'Today' => 1,
                    'Last 7 days' => 7,
                    'Last 30 days' => 30,
                    'Last 90 days' => 90,
                    _ => 0,
                  };
                  if (days > 0) {
                    final range = historicalPresetRange(days);
                    _from = range.$1;
                    _to = range.$2;
                  }
                }),
                child: Column(
                  children: [
                    for (final label in [
                      'Today',
                      'Last 7 days',
                      'Last 30 days',
                      'Last 90 days',
                      'Custom range',
                    ])
                      RadioListTile<String>(
                        key: Key('history-preset-$label'),
                        value: label,
                        title: Text(tr(context, label)),
                        activeColor: PelinesColors.brandPrimary,
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
              if (_preset == null) Text(tr(context, 'All loaded')),
              if (_preset == 'Custom range')
                OutlinedButton(
                  key: const Key('history-custom-range'),
                  onPressed: _pickRange,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    backgroundColor: PelinesColors.card,
                    foregroundColor: PelinesColors.textPrimary,
                    side: const BorderSide(color: PelinesColors.border),
                    shape: const StadiumBorder(),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _from == null && _to == null
                              ? tr(context, 'Select date range')
                              : '${_from == null ? tr(context, 'No start date') : format.format(_from!)} – ${_to == null ? tr(context, 'No end date') : format.format(_to!)}',
                        ),
                      ),
                    ],
                  ),
                ),
              if (_invalid)
                Text(
                  tr(context, 'From must be on or before To.'),
                  style: const TextStyle(color: PelinesColors.destructive),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    key: const Key('history-range-reset'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: () => setState(() {
                      _from = null;
                      _to = null;
                      _preset = null;
                      _invalid = false;
                    }),
                    child: Text(tr(context, 'Reset')),
                  ),
                  TextButton(
                    key: const Key('history-range-cancel'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr(context, 'Cancel')),
                  ),
                  FilledButton(
                    key: const Key('history-range-apply'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      backgroundColor: PelinesColors.brandPrimary,
                      foregroundColor: PelinesColors.card,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: () {
                      if (_from != null &&
                          _to != null &&
                          _from!.isAfter(_to!)) {
                        setState(() => _invalid = true);
                        return;
                      }
                      Navigator.pop(context, (_from, _to));
                    },
                    child: Text(tr(context, 'Apply')),
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

/// Local draft and bounds for history; the calendar drawing/gestures are shared.
class _HistoryRangeCalendar extends StatefulWidget {
  const _HistoryRangeCalendar({this.from, this.to});
  final DateTime? from, to;
  @override
  State<_HistoryRangeCalendar> createState() => _HistoryRangeCalendarState();
}

class _HistoryRangeCalendarState extends State<_HistoryRangeCalendar> {
  final _today = pacificDate(PelinesTime.now());
  late DateTime? _from = widget.from ?? _today;
  late DateTime? _to = widget.to;
  late bool _noStart = widget.from == null && widget.to != null;
  late bool _noEnd = widget.from != null && widget.to == null;
  bool _awaitingEnd = false;

  @override
  void initState() {
    super.initState();
    if (_noStart) _from = null;
  }

  void _select(DateTime value) => setState(() {
    final day = DateTime.utc(value.year, value.month, value.day);
    if (_noStart) {
      _to = day;
    } else if (_noEnd ||
        !_awaitingEnd ||
        _from == null ||
        day.isBefore(_from!)) {
      _from = day;
      _to = null;
      _awaitingEnd = !_noEnd;
    } else {
      _to = day;
      _awaitingEnd = false;
    }
  });

  @override
  Widget build(BuildContext context) {
    final format = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final start = _noStart ? null : _from;
    final end = _noEnd ? null : _to;
    final valid =
        (_noStart || start != null) &&
        (_noEnd || end != null) &&
        (start == null || end == null || !start.isAfter(end));
    return Dialog(
      key: const Key('history-range-calendar'),
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
                  '${start == null ? tr(context, 'No start date') : format.format(start)} – ${end == null ? tr(context, _noEnd ? 'No end date' : 'Select end date') : format.format(end)}',
                ),
              ),
              SwitchListTile(
                key: const Key('history-calendar-no-start'),
                contentPadding: EdgeInsets.zero,
                title: Text(tr(context, 'No start date')),
                value: _noStart,
                onChanged: (value) => setState(() {
                  _noStart = value;
                  _from = value ? null : (_to ?? _today);
                  _awaitingEnd = false;
                }),
              ),
              SwitchListTile(
                key: const Key('history-calendar-no-end'),
                contentPadding: EdgeInsets.zero,
                title: Text(tr(context, 'No end date')),
                value: _noEnd,
                onChanged: (value) => setState(() {
                  _noEnd = value;
                  _to = null;
                  _awaitingEnd = false;
                }),
              ),
              if (!(_noStart && _noEnd))
                UpcomingRangeCalendar(
                  initialDate: start ?? end ?? _today,
                  currentDate: _today,
                  firstDate: DateTime(1),
                  lastDate: DateTime(9999, 12, 31),
                  from: start ?? end ?? _today,
                  to: end,
                  onDateChanged: _select,
                ),
              if (start != null && end != null && start.isAfter(end))
                Text(
                  tr(context, 'From must be on or before To.'),
                  style: const TextStyle(color: PelinesColors.destructive),
                ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    key: const Key('history-calendar-cancel'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr(context, 'Cancel')),
                  ),
                  FilledButton(
                    key: const Key('history-calendar-confirm'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: valid
                        ? () => Navigator.pop(context, (start, end))
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

/// Inclusive Pacific calendar coordinates, independent of device timezone and
/// the 23/25-hour days at DST boundaries.
(DateTime, DateTime) historicalPresetRange(int days, {DateTime? now}) {
  assert(days > 0);
  final today = pacificDate(now ?? PelinesTime.now());
  return (DateTime.utc(today.year, today.month, today.day - days + 1), today);
}
