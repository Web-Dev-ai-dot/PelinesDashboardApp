import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../../orders/presentation/upcoming_date_range.dart';
import '../models/analytics_date_range.dart';

/// Presentation shared only by Analytics' two range entry points.
class AnalyticsDateRangeField extends StatelessWidget {
  const AnalyticsDateRangeField({
    super.key,
    required this.label,
    required this.dates,
    required this.buttonKey,
    required this.onPressed,
    this.chevron = false,
  });
  final String label, dates;
  final Key buttonKey;
  final VoidCallback onPressed;
  final bool chevron;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Semantics(
        label: label,
        child: OutlinedButton(
          key: buttonKey,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            backgroundColor: PelinesColors.card,
            foregroundColor: PelinesColors.textPrimary,
            side: const BorderSide(color: PelinesColors.border),
            shape: const StadiumBorder(),
          ),
          onPressed: onPressed,
          child: Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  dates,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (chevron) ...[
                const SizedBox(width: 12),
                const Icon(Icons.expand_more, size: 20),
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

Future<AnalyticsDateRange?> showAnalyticsDateRange(
  BuildContext context,
  AnalyticsDateRange applied,
) => showModalBottomSheet<AnalyticsDateRange>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: PelinesColors.card,
  constraints: const BoxConstraints(maxWidth: 640),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
  ),
  builder: (_) => _RangeSheet(applied: applied),
);

class _RangeSheet extends StatefulWidget {
  const _RangeSheet({required this.applied});
  final AnalyticsDateRange applied;
  @override
  State<_RangeSheet> createState() => _RangeSheetState();
}

class _RangeSheetState extends State<_RangeSheet> {
  late AnalyticsDateRange _draft = widget.applied;
  late bool _custom = widget.applied.preset == null;

  Future<void> _pick() async {
    // Preserve Analytics' existing bounds, including an already-applied range.
    final now = PelinesTime.now();
    final first = widget.applied.startDate.isBefore(DateTime.utc(2000))
        ? widget.applied.startDate
        : DateTime.utc(2000);
    final today = DateTime.utc(now.year, now.month, now.day);
    final last = widget.applied.endDate.isAfter(today)
        ? widget.applied.endDate
        : today;
    final picked = await showDialog<AnalyticsDateRange>(
      context: context,
      builder: (_) => _CalendarDialog(
        initial: _draft,
        first: first,
        last: last,
        today: today,
      ),
    );
    if (picked != null && mounted) setState(() => _draft = picked);
  }

  @override
  Widget build(BuildContext context) {
    final format = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    );
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const Key('analytics-range-sheet'),
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
              groupValue: _custom ? 'custom' : _draft.preset!.name,
              onChanged: (value) => setState(() {
                _custom = value == 'custom';
                if (!_custom) {
                  _draft = AnalyticsDateRange.preset(
                    AnalyticsDatePreset.values.byName(value!),
                  );
                }
              }),
              child: Column(
                children: [
                  for (final entry in {
                    'today': 'Today',
                    'last7Days': 'Last 7 days',
                    'last30Days': 'Last 30 days',
                    'last90Days': 'Last 90 days',
                    'custom': 'Custom range',
                  }.entries)
                    RadioListTile<String>(
                      key: Key('analytics-${entry.key}'),
                      value: entry.key,
                      title: Text(tr(context, entry.value)),
                      activeColor: PelinesColors.brandPrimary,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            if (_custom)
              AnalyticsDateRangeField(
                buttonKey: const Key('analytics-select-range'),
                label: tr(context, 'Select date range'),
                dates:
                    '${format.format(_draft.startDate)} – ${format.format(_draft.endDate)}',
                onPressed: _pick,
              ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  key: const Key('analytics-range-reset'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => setState(() {
                    _draft = AnalyticsDateRange.preset(
                      AnalyticsDatePreset.last30Days,
                    );
                    _custom = false;
                  }),
                  child: Text(tr(context, 'Reset')),
                ),
                TextButton(
                  key: const Key('analytics-range-cancel'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr(context, 'Cancel')),
                ),
                FilledButton(
                  key: const Key('analytics-range-apply'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    backgroundColor: PelinesColors.brandPrimary,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => Navigator.pop(
                    context,
                    _custom
                        ? AnalyticsDateRange.custom(
                            _draft.startDate,
                            _draft.endDate,
                          )
                        : _draft,
                  ),
                  child: Text(tr(context, 'Apply')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDialog extends StatefulWidget {
  const _CalendarDialog({
    required this.initial,
    required this.first,
    required this.last,
    required this.today,
  });
  final AnalyticsDateRange initial;
  final DateTime first, last, today;
  @override
  State<_CalendarDialog> createState() => _CalendarDialogState();
}

class _CalendarDialogState extends State<_CalendarDialog> {
  late DateTime _from = widget.initial.startDate;
  late DateTime? _to = widget.initial.endDate;
  bool _awaitingEnd = false;
  @override
  Widget build(BuildContext context) {
    final format = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    );
    return Dialog(
      key: const Key('analytics-range-calendar'),
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
              Semantics(
                liveRegion: true,
                child: Text(
                  '${format.format(_from)} – ${_to == null ? tr(context, 'Select end date') : format.format(_to!)}',
                ),
              ),
              UpcomingRangeCalendar(
                initialDate: _from,
                currentDate: widget.today,
                firstDate: widget.first,
                lastDate: widget.last,
                from: _from,
                to: _to,
                onDateChanged: (date) => setState(() {
                  if (!_awaitingEnd || date.isBefore(_from)) {
                    _from = date;
                    _to = null;
                    _awaitingEnd = true;
                  } else {
                    _to = date;
                    _awaitingEnd = false;
                  }
                }),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    key: const Key('analytics-calendar-cancel'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr(context, 'Cancel')),
                  ),
                  FilledButton(
                    key: const Key('analytics-calendar-confirm'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: _to == null
                        ? null
                        : () => Navigator.pop(
                            context,
                            AnalyticsDateRange.custom(_from, _to!),
                          ),
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
