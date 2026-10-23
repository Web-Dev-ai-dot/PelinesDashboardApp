import 'package:flutter/material.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_settings_content.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../models/holiday.dart';
import '../models/location.dart';
import '../models/temporary_closure.dart';
import '../providers/holidays_controller.dart';

/// Save returns only after the existing repository flow confirms persistence.
Future<String?> showHolidayEditor(
  BuildContext context, {
  required Location location,
  required List<Holiday> holidays,
  Holiday? holiday,
  required Future<HolidaysSaveState> Function(List<Holiday>) onSave,
}) {
  final sheet = MediaQuery.sizeOf(context).width < PelinesLayout.compactWidth;
  Widget editor(BuildContext context) => _HolidayEditor(
    location: location,
    holidays: holidays,
    holiday: holiday,
    onSave: onSave,
  );
  if (sheet) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      barrierColor: Colors.black.withValues(alpha: .28),
      backgroundColor: PelinesColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PelinesRadius.dialog),
        ),
      ),
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .92,
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: editor(context),
        ),
      ),
    );
  }
  return showDialog<String>(
    context: context,
    useRootNavigator: false,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: .28),
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: editor(context),
      ),
    ),
  );
}

class _HolidayEditor extends StatefulWidget {
  const _HolidayEditor({
    required this.location,
    required this.holidays,
    this.holiday,
    required this.onSave,
  });
  final Location location;
  final List<Holiday> holidays;
  final Holiday? holiday;
  final Future<HolidaysSaveState> Function(List<Holiday>) onSave;
  @override
  State<_HolidayEditor> createState() => _HolidayEditorState();
}

class _HolidayEditorState extends State<_HolidayEditor> {
  late final Holiday _initial;
  late Holiday _draft;
  bool _busy = false, _blocked = false, _allowPop = false;
  String? _error;
  Future<bool>? _leaving;
  bool get _dirty => !sameHolidays([_initial], [_draft]);
  @override
  void initState() {
    super.initState();
    _initial =
        widget.holiday ??
        Holiday(
          id: newClosureId(),
          name: '',
          date: '',
          status: 'closed',
          customOpen: '',
          customClose: '',
          notes: '',
        );
    _draft = _initial;
  }

  Future<bool> _leave() =>
      _leaving ??= _confirmLeave().whenComplete(() => _leaving = null);
  Future<bool> _confirmLeave() async {
    if (_busy) return false;
    if (!_dirty) return true;
    final discard =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr(context, 'Discard changes?')),
            content: Text(
              tr(context, 'Your unsaved holiday changes will be lost.'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr(context, 'Keep editing')),
              ),
              FilledButton(
                style: PelinesControlStyles.button(
                  PelinesButtonVariant.primary,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr(context, 'Discard')),
              ),
            ],
          ),
        ) ??
        false;
    if (!discard || !mounted) return false;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    return true;
  }

  Future<void> _close([String? result]) async {
    if (await _leave() && mounted) Navigator.pop(context, result);
  }

  Future<void> _save() async {
    if (_busy || _blocked) return;
    final next = widget.holiday == null
        ? [...widget.holidays, _draft]
        : [
            for (final h in widget.holidays)
              if (h.id == _draft.id) _draft else h,
          ];
    final validation = validateHolidays(next);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.onSave(List.unmodifiable(next));
      if (!mounted) return;
      if (result.success) {
        setState(() {
          _allowPop = true;
          _busy = false;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context, 'saved');
      } else {
        setState(() {
          _error = result.message;
          _blocked = result.reloadRequired;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdminPopScope<String>(
    canPop: _allowPop || (!_dirty && !_busy),
    onRequestLeave: _leave,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Padding(
      padding: const EdgeInsets.all(PelinesSpacing.lg),
      child: Column(
        key: const Key('holiday-editor'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(
                    context,
                    widget.holiday == null ? 'Add holiday' : 'Edit holiday',
                  ),
                  style: PelinesTypography.sectionTitle(
                    Theme.of(context).textTheme,
                  ),
                ),
              ),
              IconButton(
                key: const Key('holiday-editor-close'),
                tooltip: tr(context, 'Close'),
                onPressed: _busy ? null : () => _close(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Flexible(
            child: SingleChildScrollView(
              key: const Key('holiday-editor-scroll'),
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.location.name,
                    style: PelinesTypography.smallLabel,
                  ),
                  const SizedBox(height: 12),
                  _HolidayForm(
                    holiday: _draft,
                    index: 0,
                    enabled: !_busy && !_blocked,
                    onChanged: (value) => setState(() {
                      _draft = value;
                      _error = null;
                    }),
                  ),
                  if (_dirty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        tr(context, 'Unsaved changes'),
                        key: const Key('holidays-unsaved'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: PelinesColors.brandPrimary,
                        ),
                      ),
                    ),
                  if (widget.location.hoursJson == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        tr(
                          context,
                          'Configure Standard Hours before saving holidays.',
                        ),
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          tr(context, _error!),
                          key: const Key('holidays-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  if (_blocked)
                    OutlinedButton(
                      key: const Key('holiday-editor-reload'),
                      onPressed: _busy ? null : () => _close('reload'),
                      child: Text(tr(context, 'Reload')),
                    ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton(
                        key: const Key('holiday-editor-cancel'),
                        style: PelinesControlStyles.button(
                          PelinesButtonVariant.secondary,
                        ),
                        onPressed: _busy ? null : () => _close(),
                        child: Text(tr(context, 'Cancel')),
                      ),
                      FilledButton(
                        key: const Key('holidays-save'),
                        style: PelinesControlStyles.button(
                          PelinesButtonVariant.primary,
                        ),
                        onPressed:
                            _busy ||
                                _blocked ||
                                widget.location.hoursJson == null ||
                                (widget.holiday != null && !_dirty)
                            ? null
                            : _save,
                        child: Text(
                          tr(context, _busy ? 'Saving…' : 'Save changes'),
                        ),
                      ),
                    ],
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _HolidayForm extends StatelessWidget {
  const _HolidayForm({
    required this.holiday,
    required this.index,
    required this.enabled,
    required this.onChanged,
  });
  final Holiday holiday;
  final int index;
  final bool enabled;
  final ValueChanged<Holiday> onChanged;
  Future<void> _date(BuildContext context) async {
    final result = await showDatePicker(
      context: context,
      initialDate: (parseCalendarDate(holiday.date)?.year ?? 0) >= 1
          ? parseCalendarDate(holiday.date)!
          : DateTime.now(),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (result != null && context.mounted) {
      onChanged(holiday.copyWith(date: formatCalendarDate(result)));
    }
  }

  Future<void> _time(BuildContext context, bool opening) async {
    final value = opening ? holiday.customOpen : holiday.customClose;
    final parts = value.split(':');
    final hour = parts.length == 2 ? int.tryParse(parts[0]) : null;
    final minute = parts.length == 2 ? int.tryParse(parts[1]) : null;
    final initial =
        hour != null &&
            minute != null &&
            hour >= 0 &&
            hour < 24 &&
            minute >= 0 &&
            minute < 60
        ? TimeOfDay(hour: hour, minute: minute)
        : TimeOfDay.now();
    final result = await showTimePicker(context: context, initialTime: initial);
    if (result == null || !context.mounted) return;
    final time =
        '${result.hour.toString().padLeft(2, '0')}:${result.minute.toString().padLeft(2, '0')}';
    onChanged(
      opening
          ? holiday.copyWith(customOpen: time)
          : holiday.copyWith(customClose: time),
    );
  }

  InputDecoration _decoration({String? hint, bool muted = true}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(PelinesRadius.prominentCard),
      borderSide: const BorderSide(color: PelinesColors.border),
    );
    return PelinesControlStyles.input(hint: hint).copyWith(
      fillColor: muted ? PelinesColors.mutedSurface : PelinesColors.card,
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(
          color: PelinesColors.brandPrimary,
          width: 2,
        ),
      ),
    );
  }

  ButtonStyle get _fieldButtonStyle =>
      PelinesControlStyles.button(PelinesButtonVariant.secondary).copyWith(
        backgroundColor: const WidgetStatePropertyAll(
          PelinesColors.mutedSurface,
        ),
        alignment: AlignmentDirectional.centerStart,
        minimumSize: const WidgetStatePropertyAll(Size(0, 56)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PelinesRadius.prominentCard),
          ),
        ),
      );

  Widget _timeButton(BuildContext context, bool opening) {
    final value = opening ? holiday.customOpen : holiday.customClose;
    return Semantics(
      label: tr(context, opening ? 'Opening time' : 'Closing time'),
      child: OutlinedButton(
        key: Key('holiday-$index-${opening ? 'open-time' : 'close-time'}'),
        style: _fieldButtonStyle,
        onPressed: enabled && holiday.status == 'open'
            ? () => _time(context, opening)
            : null,
        child: Text(value.isEmpty ? '--:--' : value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(PelinesSpacing.md),
    decoration: BoxDecoration(
      border: Border.all(color: PelinesColors.border),
      borderRadius: BorderRadius.circular(PelinesRadius.prominentCard),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PelinesSettingsFields(
          children: [
            Semantics(
              label: tr(context, 'Holiday name'),
              child: TextFormField(
                key: Key('holiday-$index-name'),
                initialValue: holiday.name,
                enabled: enabled,
                decoration: _decoration(hint: tr(context, 'Holiday name')),
                onChanged: (value) => onChanged(holiday.copyWith(name: value)),
              ),
            ),
            Semantics(
              label: tr(context, 'Date'),
              child: OutlinedButton(
                key: Key('holiday-$index-date'),
                style: _fieldButtonStyle,
                onPressed: enabled ? () => _date(context) : null,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        parseCalendarDate(holiday.date) == null
                            ? 'dd/mm/yyyy'
                            : MaterialLocalizations.of(context)
                                  .formatCompactDate(
                                    parseCalendarDate(holiday.date)!,
                                  ),
                      ),
                    ),
                    const SizedBox(width: PelinesSpacing.xs),
                    const Icon(Icons.calendar_today_outlined, size: 20),
                  ],
                ),
              ),
            ),
            Semantics(
              label: tr(context, 'Status'),
              child: DropdownButtonFormField<String>(
                key: Key('holiday-$index-status'),
                initialValue: holiday.status,
                isExpanded: true,
                decoration: _decoration(muted: false),
                items: [
                  for (final value in ['open', 'closed'])
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        tr(context, value == 'open' ? 'Open' : 'Closed'),
                      ),
                    ),
                ],
                onChanged: enabled
                    ? (value) => onChanged(holiday.copyWith(status: value))
                    : null,
              ),
            ),
            if (holiday.status == 'open') ...[
              _timeButton(context, true),
              _timeButton(context, false),
            ],
            Semantics(
              label: tr(context, 'Notes (optional)'),
              child: TextFormField(
                key: Key('holiday-$index-notes'),
                initialValue: holiday.notes,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                decoration: _decoration(hint: tr(context, 'Notes (optional)')),
                onChanged: (value) => onChanged(holiday.copyWith(notes: value)),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
