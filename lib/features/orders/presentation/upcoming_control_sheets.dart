import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../models/order_models.dart';
import '../models/orders_date_filter.dart';
import '../models/upcoming_filters.dart';

// A wrapper distinguishes Apply All Types (null) from dismiss (null result).
class UpcomingTypeSelection {
  const UpcomingTypeSelection(this.type);
  final OrderType? type;
}

Future<T?> _show<T>(BuildContext context, Widget child) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => child,
  );
}

Future<UpcomingTypeSelection?> showUpcomingSort(
  BuildContext context,
  OrderType? applied,
) => _show(context, _SortSheet(applied: applied));

Future<UpcomingFilters?> showUpcomingFilters(
  BuildContext context,
  UpcomingFilters applied,
) => _show(context, _FiltersSheet(applied: applied));

// Calendar already selects dates in its Today/Week/Month views and admits only
// active statuses. Reuse draft/Apply/Reset without Upcoming's future range.
Future<UpcomingFilters?> showCalendarFilters(
  BuildContext context,
  UpcomingFilters applied,
) => _show(context, _FiltersSheet(applied: applied, calendar: true));

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.title,
    required this.children,
    required this.apply,
    this.reset,
  });
  final String title;
  final List<Widget> children;
  final VoidCallback apply;
  final VoidCallback? reset;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (reset != null)
                    TextButton(
                      key: const Key('upcoming-filter-reset'),
                      onPressed: reset,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      child: Text(tr(context, 'Reset')),
                    ),
                  Semantics(
                    header: true,
                    child: Text(
                      tr(context, title),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                key: const Key('upcoming-sheet-scroll'),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                key: const Key('upcoming-sheet-apply'),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: apply,
                child: Text(tr(context, 'Apply')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SortSheet extends StatefulWidget {
  const _SortSheet({required this.applied});
  final OrderType? applied;
  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  late OrderType? _draft = widget.applied;
  @override
  Widget build(BuildContext context) => _Sheet(
    title: 'Sort',
    apply: () => Navigator.pop(context, UpcomingTypeSelection(_draft)),
    children: [
      RadioGroup<OrderType?>(
        groupValue: _draft,
        onChanged: (value) => setState(() => _draft = value),
        child: Column(
          children: [
            for (final entry in <OrderType?, String>{
              null: 'All Types',
              OrderType.online: 'Regular',
              OrderType.catering: 'Catering',
            }.entries)
              RadioListTile<OrderType?>(
                key: Key('upcoming-type-${entry.key?.name ?? 'all'}'),
                value: entry.key,
                activeColor: PelinesColors.brandPrimary,
                title: Text(tr(context, entry.value)),
              ),
          ],
        ),
      ),
    ],
  );
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.applied, this.calendar = false});
  final UpcomingFilters applied;
  final bool calendar;
  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late DateTime? _from = widget.applied.from, _to = widget.applied.to;
  late OrderStatus? _status = widget.applied.status;
  bool _invalid = false;

  Future<void> _pick(bool from) async {
    final today = pacificDate(PelinesTime.now());
    final tomorrow = DateTime.utc(today.year, today.month, today.day + 1);
    final current = (from ? _from : _to) ?? _from ?? tomorrow;
    final picked = await showDatePicker(
      context: context,
      currentDate: today,
      initialDate: current.isBefore(tomorrow) ? tomorrow : current,
      firstDate: tomorrow,
      lastDate: DateTime(2100, 12, 31),
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
    return _Sheet(
      title: 'Filters',
      reset: () => setState(() {
        _from = null;
        _to = null;
        _status = null;
        _invalid = false;
      }),
      apply: () {
        final result = UpcomingFilters(from: _from, to: _to, status: _status);
        if (!result.isValid) {
          setState(() => _invalid = true);
          return;
        }
        Navigator.pop(context, result);
      },
      children: [
        if (!widget.calendar) ...[
          Semantics(
            header: true,
            child: Text(
              tr(context, 'Date range'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          for (final from in [true, false])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton.icon(
                key: Key(from ? 'upcoming-from' : 'upcoming-to'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                onPressed: () => _pick(from),
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  '${tr(context, from ? 'From' : 'To')}: ${(from ? _from : _to) == null ? tr(context, from ? 'Tomorrow' : 'No end date') : format.format((from ? _from : _to)!)}',
                ),
              ),
            ),
          Text(
            tr(context, 'From tomorrow · Pacific time · Available orders only'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_invalid)
            Semantics(
              liveRegion: true,
              child: Text(
                tr(context, 'From must be on or before To.'),
                style: const TextStyle(color: PelinesColors.brandPrimary),
              ),
            ),
          const SizedBox(height: 16),
        ],
        Semantics(
          header: true,
          child: Text(
            tr(context, 'Status'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        RadioGroup<OrderStatus?>(
          groupValue: _status,
          onChanged: (value) => setState(() => _status = value),
          child: Column(
            children: [
              for (final entry in <OrderStatus?, String>{
                null: 'All statuses',
                OrderStatus.pending: 'Waiting for approval',
                OrderStatus.confirmed: 'Confirmed',
                OrderStatus.preparing: 'Preparing',
                OrderStatus.ready: 'Ready',
                // Both fulfillment types persist delivered. Upcoming's active
                // provider excludes terminal orders, so this selection is empty.
                if (!widget.calendar)
                  OrderStatus.delivered: 'Picked up / Delivered',
              }.entries)
                RadioListTile<OrderStatus?>(
                  key: Key('upcoming-status-${entry.key?.name ?? 'all'}'),
                  value: entry.key,
                  activeColor: PelinesColors.brandPrimary,
                  title: Text(tr(context, entry.value)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
