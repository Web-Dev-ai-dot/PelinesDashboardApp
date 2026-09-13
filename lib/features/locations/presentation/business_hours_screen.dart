import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../models/business_hours.dart';
import '../models/location.dart';
import '../providers/business_hours_controller.dart';

class BusinessHoursScreen extends ConsumerStatefulWidget {
  const BusinessHoursScreen({super.key, required this.location});
  final Location location;

  @override
  ConsumerState<BusinessHoursScreen> createState() =>
      _BusinessHoursScreenState();
}

class _BusinessHoursScreenState extends ConsumerState<BusinessHoursScreen> {
  late BusinessHoursSchedule _initial;
  late BusinessHoursSchedule _draft;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _initial = widget.location.hoursJson == null
        ? BusinessHoursSchedule.dashboardDefault()
        : BusinessHoursSchedule.fromJson(widget.location.hoursJson!);
    _draft = _initial;
  }

  @override
  Widget build(BuildContext context) {
    final BusinessHoursSaveState operation = ref.watch(
      businessHoursSaveProvider,
    );
    return PopScope<void>(
      canPop: !_dirty || operation.isBusy,
      onPopInvokedWithResult: (bool didPop, void result) async {
        if (didPop || operation.isBusy) return;
        if (await _confirmDiscard() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Business Hours')),
        body: PelinesPageBody(
          child: ListView(
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
              const Text('Times are recurring business times in Pacific Time.'),
              const SizedBox(height: 8),
              const Text(
                'Business hours affect regular online ordering. Catering availability is handled separately.',
              ),
              const SizedBox(height: 4),
              const Text(
                'Temporary closures can override regular business hours.',
              ),
              const SizedBox(height: 20),
              for (int index = 0; index < 7; index++)
                _dayEditor(index, operation.isBusy),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('business-hours-save'),
                onPressed: operation.isBusy ? null : _save,
                child: Text(
                  operation.isBusy ? 'Saving…' : 'Save business hours',
                ),
              ),
              if (operation.isBusy) ...<Widget>[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayEditor(int index, bool busy) {
    final BusinessDayHours day = _draft.days[index];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            SwitchListTile(
              key: Key('business-day-$index'),
              contentPadding: EdgeInsets.zero,
              title: Text(businessDayLabels[index]),
              subtitle: Text(day.closed ? 'Closed' : 'Open'),
              value: !day.closed,
              onChanged: busy
                  ? null
                  : (bool open) => _replace(index, day.copyWith(closed: !open)),
            ),
            if (!day.closed)
              PelinesActionBar(
                children: <Widget>[
                  _timeButton(index, true, day.open, busy),
                  _timeButton(index, false, day.close, busy),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _timeButton(int index, bool opening, String value, bool busy) {
    return OutlinedButton(
      key: Key('business-${opening ? 'open' : 'close'}-$index'),
      onPressed: busy ? null : () => _pickTime(index, opening, value),
      child: Column(
        children: <Widget>[
          Text(opening ? 'Opens' : 'Closes'),
          Text(_displayTime(value)),
        ],
      ),
    );
  }

  Future<void> _pickTime(int index, bool opening, String value) async {
    final List<String> parts = value.split(':');
    final TimeOfDay? selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
    );
    if (selected == null) return;
    final String formatted =
        '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
    final BusinessDayHours day = _draft.days[index];
    _replace(
      index,
      opening ? day.copyWith(open: formatted) : day.copyWith(close: formatted),
    );
  }

  void _replace(int index, BusinessDayHours day) {
    setState(() {
      _draft = _draft.replaceDay(index, day);
      _dirty = !_draft.sameAs(_initial);
    });
  }

  Future<void> _save() async {
    final String? validation = _draft.validate();
    if (validation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validation),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    await ref
        .read(businessHoursSaveProvider.notifier)
        .save(
          locationId: widget.location.id,
          originalUpdatedAt: widget.location.updatedAt,
          schedule: _draft,
        );
    if (!mounted) return;
    final BusinessHoursSaveState result = ref.read(businessHoursSaveProvider);
    if (result.phase == BusinessHoursSavePhase.success) {
      _dirty = false;
      Navigator.pop(context);
    } else if (result.phase == BusinessHoursSavePhase.conflict) {
      final bool? reload = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Store settings were changed elsewhere.'),
          content: const Text(
            'Reload before saving to avoid overwriting those changes.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reload'),
            ),
          ],
        ),
      );
      if (reload == true && mounted) {
        _dirty = false;
        Navigator.pop(context);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Business hours could not be saved.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text(
            'Your unsaved business hours changes will be lost.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      ) ??
      false;

  String _displayTime(String value) {
    final List<String> parts = value.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    ).format(context);
  }
}
