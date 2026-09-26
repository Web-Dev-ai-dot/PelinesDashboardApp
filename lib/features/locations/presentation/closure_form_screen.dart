import '../../../app/theme/app_theme.dart';
import 'operations_parity_widgets.dart';

import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../models/location.dart';
import '../models/temporary_closure.dart';
import '../providers/closures_controller.dart';

class ClosureFormScreen extends ConsumerStatefulWidget {
  const ClosureFormScreen({super.key, required this.location, this.closure});

  final Location location;
  final TemporaryClosure? closure;

  @override
  ConsumerState<ClosureFormScreen> createState() => _ClosureFormScreenState();
}

class _ClosureFormScreenState extends ConsumerState<ClosureFormScreen> {
  late final TextEditingController _reason;
  late final TextEditingController _notes;
  DateTime? _start;
  DateTime? _end;
  late bool _active;
  String? _dateError;

  @override
  void initState() {
    super.initState();
    final TemporaryClosure? closure = widget.closure;
    _reason = TextEditingController(text: closure?.reason ?? '');
    _notes = TextEditingController(text: closure?.notes ?? '');
    _start = closure == null ? null : parseCalendarDate(closure.start);
    _end = closure == null ? null : parseCalendarDate(closure.end);
    _active = closure?.active ?? true;
  }

  @override
  void dispose() {
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ClosureSaveState operation = ref.watch(closureSaveProvider);
    return Scaffold(
      appBar: AdminAppBar(
        title: Text(
          widget.closure == null
              ? tr(context, 'Add Closure')
              : tr(context, 'Edit Closure'),
          style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
        ),
      ),
      body: PelinesPageBody(
        child: OperationsFormList(
          padding: const EdgeInsets.all(PelinesSpacing.lg),
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: PelinesStateBadge(
                label: widget.location.name,
                foreground: PelinesColors.brandPrimary,
                background: PelinesColors.brandPrimarySoft,
                icon: Icons.storefront_outlined,
              ),
            ),
            const SizedBox(height: 4),
            Text(tr(context, 'Temporary closure for regular online orders')),
            const SizedBox(height: 24),
            TextField(
              key: const Key('closure-reason'),
              controller: _reason,
              enabled: !operation.isBusy,
              decoration: PelinesControlStyles.input(
                label: tr(context, 'Reason (optional)'),
              ),
            ),
            const SizedBox(height: 16),
            _DateField(
              key: const Key('closure-start'),
              label: tr(context, 'Start date'),
              value: _start,
              enabled: !operation.isBusy,
              onPick: (DateTime value) => setState(() => _start = value),
            ),
            const SizedBox(height: 12),
            _DateField(
              key: const Key('closure-end'),
              label: tr(context, 'End date'),
              value: _end,
              enabled: !operation.isBusy,
              onPick: (DateTime value) => setState(() => _end = value),
            ),
            if (_dateError != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _dateError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const Key('closure-notes'),
              controller: _notes,
              enabled: !operation.isBusy,
              maxLines: 3,
              decoration: PelinesControlStyles.input(
                label: tr(context, 'Notes'),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('closure-active'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Active')),
              subtitle: Text(
                tr(
                  context,
                  'Inactive closures remain saved but do not block regular orders.',
                ),
              ),
              value: _active,
              onChanged: operation.isBusy
                  ? null
                  : (bool value) => setState(() => _active = value),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              style: PelinesControlStyles.button(
                PelinesButtonVariant.secondary,
              ),
              onPressed: operation.isBusy
                  ? null
                  : () => Navigator.maybePop(context),
              child: Text(tr(context, 'Cancel')),
            ),
            const SizedBox(height: 12),

            FilledButton(
              style: PelinesControlStyles.button(PelinesButtonVariant.primary),
              key: const Key('closure-save'),
              onPressed: operation.isBusy ? null : _save,
              child: Text(
                operation.isBusy
                    ? tr(context, 'Saving…')
                    : tr(context, 'Save closure'),
              ),
            ),
            if (operation.isBusy) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_start == null || _end == null) {
      setState(() => _dateError = 'Choose both a start and end date.');
      return;
    }
    if (!isValidClosureRange(
      formatCalendarDate(_start!),
      formatCalendarDate(_end!),
    )) {
      setState(() => _dateError = 'Start date must be on or before end date.');
      return;
    }
    setState(() => _dateError = null);
    final TemporaryClosure closure = widget.closure == null
        ? TemporaryClosure(
            id: newClosureId(),
            reason: _reason.text.trim(),
            start: formatCalendarDate(_start!),
            end: formatCalendarDate(_end!),
            notes: _notes.text.trim(),
            active: _active,
          )
        : widget.closure!.copyWith(
            reason: _reason.text.trim(),
            start: formatCalendarDate(_start!),
            end: formatCalendarDate(_end!),
            notes: _notes.text.trim(),
            active: _active,
          );
    await ref
        .read(closureSaveProvider.notifier)
        .save(
          locationId: widget.location.id,
          originalUpdatedAt: widget.location.updatedAt,
          closure: closure,
          isNew: widget.closure == null,
        );
    if (!mounted) return;
    final ClosureSaveState result = ref.read(closureSaveProvider);
    if (result.phase == ClosureSavePhase.success) {
      Navigator.pop(context);
      return;
    }
    if (result.phase == ClosureSavePhase.conflict) {
      final bool? reload = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Store settings were changed elsewhere.'),
          content: const Text(
            'Reload before saving to avoid overwriting those changes.',
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('closure-conflict-cancel'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: PelinesControlStyles.button(PelinesButtonVariant.primary),
              key: const Key('closure-conflict-reload'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reload'),
            ),
          ],
        ),
      );
      if (reload == true && mounted) Navigator.pop(context);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message ?? 'The closure could not be saved.'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onPick,
  });
  final String label;
  final DateTime? value;
  final bool enabled;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: PelinesControlStyles.button(PelinesButtonVariant.secondary),
    onPressed: enabled
        ? () async {
            final DateTime now = DateTime.now();
            final DateTime? selected = await showDatePicker(
              context: context,
              initialDate: value ?? now,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 10),
            );
            if (selected != null) onPick(selected);
          }
        : null,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Expanded(
          child: Text(
            value == null
                ? label
                : '$label: ${DateFormat.yMMMd().format(value!)}',
          ),
        ),
        const SizedBox(width: PelinesSpacing.sm),
        const Icon(Icons.calendar_today_outlined),
      ],
    ),
  );
}
