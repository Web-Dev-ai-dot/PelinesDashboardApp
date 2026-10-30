import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_settings_content.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../models/holiday.dart';
import '../models/location.dart';
import '../models/temporary_closure.dart';
import '../providers/holidays_controller.dart';
import '../providers/locations_providers.dart';
import 'holiday_editor.dart';

/// Saved records are read-only; Add/Edit persist through a separate editor.
class HolidaysSection extends ConsumerStatefulWidget {
  const HolidaysSection({
    super.key,
    required this.location,
    this.locationsLayout = false,
  });
  final bool locationsLayout;
  final Location location;
  @override
  ConsumerState<HolidaysSection> createState() => _HolidaysSectionState();
}

class _HolidaysSectionState extends ConsumerState<HolidaysSection>
    with AutomaticKeepAliveClientMixin {
  bool _busy = false,
      _editorOpen = false,
      _confirming = false,
      _blocked = false;
  String? _error;
  @override
  bool get wantKeepAlive => true;

  Future<HolidaysSaveState> _persist(
    Location original,
    List<Holiday> next,
  ) async {
    if (_busy) return const HolidaysSaveState(message: 'Saving…');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(holidaysSaveProvider.notifier)
          .save(original: original, holidays: next);
      if (!mounted) return const HolidaysSaveState(reloadRequired: true);
      final result = ref.read(holidaysSaveProvider);
      setState(() {
        _blocked = result.reloadRequired;
        if (result.reloadRequired) _error = result.message;
      });
      return result;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(List<Holiday> holidays, [Holiday? holiday]) async {
    if (_busy || _editorOpen || _blocked) return;
    final original = widget.location;
    setState(() {
      _editorOpen = true;
      _error = null;
    });
    try {
      final result = await showHolidayEditor(
        context,
        location: original,
        holidays: List.unmodifiable(holidays),
        holiday: holiday,
        onSave: (next) => _persist(original, next),
      );
      if (!mounted) return;
      if (result == 'reload') {
        await _reload();
      } else if (result == 'saved') {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr(context, 'Holidays saved.'))));
      }
    } finally {
      if (mounted) setState(() => _editorOpen = false);
    }
  }

  Future<void> _delete(List<Holiday> holidays, Holiday holiday) async {
    if (_busy || _confirming || _blocked) return;
    final original = widget.location;
    setState(() => _confirming = true);
    try {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr(context, 'Delete holiday?')),
              content: Text(
                '${holiday.name}\n\n${tr(context, 'This deletion will be saved immediately.')}',
              ),
              actions: [
                TextButton(
                  key: const Key('holiday-delete-cancel'),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(tr(context, 'Cancel')),
                ),
                FilledButton(
                  key: const Key('holiday-delete-confirm'),
                  style: PelinesControlStyles.button(
                    PelinesButtonVariant.primary,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(tr(context, 'Delete')),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;
      final result = await _persist(original, [
        for (final h in holidays)
          if (h.id != holiday.id) h,
      ]);
      if (!mounted) return;
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'Holiday deleted.'))),
        );
      } else {
        setState(() => _error = result.message);
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _reload() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final canonical = await ref
          .read(locationsRepositoryProvider)
          .getLocation(widget.location.id);
      if (!mounted || canonical.id != widget.location.id) return;
      ref.read(locationsProvider.notifier).adoptCanonical(canonical);
      ref.read(currentLocationProvider.notifier).adoptCanonical(canonical);
      setState(() {
        _blocked = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Holidays could not be loaded. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    List<Holiday> saved = [];
    String? unsupported;
    try {
      saved = holidaysFromExtras(widget.location.hoursExtrasJson);
    } on UnsupportedHolidayFormat catch (error) {
      unsupported = error.toString();
    }
    final sorted = [...saved]
      ..sort((a, b) {
        final date = a.date.compareTo(b.date);
        return date == 0 ? a.id.compareTo(b.id) : date;
      });
    final editable =
        !_busy &&
        !_editorOpen &&
        !_confirming &&
        !_blocked &&
        unsupported == null;
    return _HolidayNavigationGuard(
      locationsLayout: widget.locationsLayout,
      busy: _busy,
      child: PelinesSettingsCard(
        key: const Key('holidays-section'),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              PelinesSectionHeading(
                tr(
                  context,
                  widget.locationsLayout ? 'Holiday Schedules' : 'Holidays',
                ),
              ),
              if (!widget.locationsLayout)
                OutlinedButton.icon(
                  key: const Key('add-holiday'),
                  style: PelinesControlStyles.button(
                    PelinesButtonVariant.secondary,
                  ),
                  onPressed: editable ? () => _edit(saved) : null,
                  icon: const Icon(Icons.add),
                  label: Text(
                    tr(
                      context,
                      widget.locationsLayout
                          ? 'Add holiday schedule'
                          : 'Add holiday',
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            tr(
              context,
              'Special hours apply to regular orders on the selected date, in Pacific Time. Temporary closures take priority. Catering is unchanged.',
            ),
            style: const TextStyle(color: PelinesColors.textSecondary),
          ),
          if (widget.location.hoursJson == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                tr(context, 'Configure Standard Hours before saving holidays.'),
              ),
            ),
          if (unsupported == null && saved.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(tr(context, 'No holidays configured.')),
            ),
          for (final h in sorted)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: _HolidayCard(
                holiday: h,
                enabled: editable,
                onEdit: () => _edit(saved, h),
                onDelete: () => _delete(saved, h),
              ),
            ),
          if (widget.locationsLayout)
            OutlinedButton.icon(
              key: const Key('add-holiday'),
              style: PelinesControlStyles.button(
                PelinesButtonVariant.secondary,
              ),
              onPressed: editable ? () => _edit(saved) : null,
              icon: const Icon(Icons.add),
              label: Text(
                tr(
                  context,
                  widget.locationsLayout
                      ? 'Add holiday schedule'
                      : 'Add holiday',
                ),
              ),
            ),
          if (unsupported != null || _error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  tr(context, unsupported ?? _error!),
                  key: const Key('holidays-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          if (_blocked || unsupported != null)
            OutlinedButton(
              key: const Key('holidays-reload'),
              onPressed: _busy ? null : _reload,
              child: Text(tr(context, 'Reload')),
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

class _HolidayCard extends StatelessWidget {
  const _HolidayCard({
    required this.holiday,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
  });
  final Holiday holiday;
  final bool enabled;
  final VoidCallback onEdit, onDelete;
  String _time(BuildContext context, String value) {
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) return '—';
    return TimeOfDay(
      hour: int.parse(value.substring(0, 2)),
      minute: int.parse(value.substring(3)),
    ).format(context);
  }

  @override
  Widget build(BuildContext context) {
    final date = parseCalendarDate(holiday.date);
    final closed = holiday.status == 'closed';
    return Container(
      key: ValueKey('holiday-card-${holiday.id}'),
      padding: const EdgeInsets.all(PelinesSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: PelinesColors.border),
        borderRadius: BorderRadius.circular(PelinesRadius.prominentCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  holiday.name,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                key: Key('holiday-edit-${holiday.id}'),
                tooltip: tr(context, 'Edit holiday'),
                onPressed: enabled ? onEdit : null,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                key: Key('holiday-delete-${holiday.id}'),
                tooltip: tr(context, 'Delete holiday'),
                onPressed: enabled ? onDelete : null,
                icon: const Icon(
                  Icons.delete_outline,
                  color: PelinesColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            date == null
                ? holiday.date
                : MaterialLocalizations.of(context).formatFullDate(date),
            style: const TextStyle(color: PelinesColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PelinesStateBadge(
              label: tr(context, closed ? 'Closed' : 'Open'),
              foreground: closed
                  ? PelinesColors.textSecondary
                  : PelinesColors.successForeground,
              background: closed
                  ? PelinesColors.mutedSurface
                  : PelinesColors.successBackground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            closed
                ? tr(context, 'Closed all day')
                : '${_time(context, holiday.customOpen)} – ${_time(context, holiday.customClose)}',
          ),
          if (holiday.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(holiday.notes),
          ],
        ],
      ),
    );
  }
}

/// Locations' weekly draft owns the route guard. Keep the holiday busy PopScope
/// without replacing that guard; standalone Holidays keeps its existing guard.
class _HolidayNavigationGuard extends StatelessWidget {
  const _HolidayNavigationGuard({
    required this.locationsLayout,
    required this.busy,
    required this.child,
  });
  final bool locationsLayout, busy;
  final Widget child;
  @override
  Widget build(BuildContext context) => locationsLayout
      ? PopScope<void>(canPop: !busy, child: child)
      : AdminPopScope<void>(
          canPop: !busy,
          onRequestLeave: () async => !busy,
          onPopInvokedWithResult: (_, _) {},
          child: child,
        );
}
