import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../models/order_models.dart';
import '../models/orders_date_filter.dart';

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

  Future<void> _pick(bool from) async {
    final today = pacificDate(PelinesTime.now());
    final picked = await showDatePicker(
      context: context,
      currentDate: today,
      initialDate: (from ? _from : _to) ?? today,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final day = DateTime.utc(picked.year, picked.month, picked.day);
      if (from) {
        _from = day;
      } else {
        _to = day;
      }
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
                for (final from in [true, false])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton.icon(
                      key: Key(from ? 'history-from' : 'history-to'),
                      onPressed: () => _pick(from),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        shape: const StadiumBorder(),
                      ),
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        '${tr(context, from ? 'From' : 'To')}: '
                        '${(from ? _from : _to) == null ? tr(context, 'All loaded') : format.format((from ? _from : _to)!)}',
                      ),
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

/// Inclusive Pacific calendar coordinates, independent of device timezone and
/// the 23/25-hour days at DST boundaries.
(DateTime, DateTime) historicalPresetRange(int days, {DateTime? now}) {
  assert(days > 0);
  final today = pacificDate(now ?? PelinesTime.now());
  return (DateTime.utc(today.year, today.month, today.day - days + 1), today);
}
