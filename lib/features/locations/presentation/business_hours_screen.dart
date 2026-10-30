import 'business_time_selector.dart';
import '../../../app/theme/app_theme.dart';
import 'operations_parity_widgets.dart';

import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../models/business_hours.dart';
import '../models/location.dart';
import '../providers/business_hours_controller.dart';
import '../providers/locations_providers.dart';

class BusinessHoursScreen extends ConsumerStatefulWidget {
  const BusinessHoursScreen({
    super.key,
    required this.location,
    this.locationsLayout = false,
  });
  final bool locationsLayout;
  final Location location;

  @override
  ConsumerState<BusinessHoursScreen> createState() =>
      _BusinessHoursScreenState();
}

class _BusinessHoursScreenState extends ConsumerState<BusinessHoursScreen> {
  late BusinessHoursSchedule _initial;
  late BusinessHoursSchedule _draft;
  bool _dirty = false;
  late DateTime _baselineUpdatedAt;

  @override
  void initState() {
    super.initState();
    _initial = widget.location.hoursJson == null
        ? BusinessHoursSchedule.dashboardDefault()
        : BusinessHoursSchedule.fromJson(widget.location.hoursJson!);
    _draft = _initial;
    _baselineUpdatedAt = widget.location.updatedAt;
  }

  @override
  void didUpdateWidget(covariant BusinessHoursScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.locationsLayout &&
        !_dirty &&
        !ref.read(businessHoursSaveProvider).isBusy &&
        oldWidget.location.updatedAt != widget.location.updatedAt) {
      _initial = widget.location.hoursJson == null
          ? BusinessHoursSchedule.dashboardDefault()
          : BusinessHoursSchedule.fromJson(widget.location.hoursJson!);
      _draft = _initial;
      _baselineUpdatedAt = widget.location.updatedAt;
    }
  }

  @override
  Widget build(BuildContext context) {
    final BusinessHoursSaveState operation = ref.watch(
      businessHoursSaveProvider,
    );
    if (widget.locationsLayout) return _locationsEditor(operation);
    return AdminPopScope<void>(
      canPop: !_dirty || operation.isBusy,
      onPopInvokedWithResult: (bool didPop, void result) async {
        if (didPop || operation.isBusy) return;
        if (await _confirmDiscard() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AdminAppBar(
          title: Text(
            tr(context, 'Business Hours'),
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
              Text(
                tr(
                  context,
                  'Times are recurring business times in Pacific Time.',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  context,
                  'Business hours affect regular online ordering. Catering availability is handled separately.',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr(
                  context,
                  'Temporary closures can override regular business hours.',
                ),
              ),
              const SizedBox(height: 20),
              for (int index = 0; index < 7; index++)
                _dayEditor(index, operation.isBusy),
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
                style: PelinesControlStyles.button(
                  PelinesButtonVariant.primary,
                ),
                key: const Key('business-hours-save'),
                onPressed: operation.isBusy ? null : _save,
                child: Text(
                  operation.isBusy
                      ? tr(context, 'Saving…')
                      : tr(context, 'Save business hours'),
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

  Future<bool>? _leavePending;
  Future<bool> _requestLocationsLeave() => _leavePending ??= _leaveLocations()
      .whenComplete(() => _leavePending = null);
  Future<bool> _leaveLocations() async {
    if (ref.read(businessHoursSaveProvider).isBusy) return false;
    if (!_dirty) return true;
    if (!await _confirmDiscard() || !mounted) return false;
    setState(() {
      _draft = _initial;
      _dirty = false;
    });
    return true;
  }

  Widget _locationsEditor(
    BusinessHoursSaveState operation,
  ) => AdminPopScope<void>(
    canPop: !_dirty && !operation.isBusy,
    onRequestLeave: _requestLocationsLeave,
    onPopInvokedWithResult: (popped, result) async {
      if (!popped) await _requestLocationsLeave();
    },
    child: OperationsCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PelinesSectionHeading(tr(context, 'Standard Hours')),
            const SizedBox(height: 12),
            if (widget.location.hoursJson == null) ...[
              Text(tr(context, 'Business hours are not configured.')),
              OutlinedButton(
                key: const Key('edit-business-hours'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        BusinessHoursScreen(location: widget.location),
                  ),
                ),
                child: Text(tr(context, 'Edit business hours')),
              ),
            ] else ...[
              for (var index = 0; index < 7; index++) ...[
                if (index > 0) const Divider(height: 1),
                Padding(
                  key: ValueKey('location-hours-${businessDayKeys[index]}'),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final day = _draft.days[index];
                      final info = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr(context, businessDayLabels[index]),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            day.closed
                                ? tr(context, 'Closed')
                                : '${_displayTime(day.open)} – ${_displayTime(day.close)}',
                            style: const TextStyle(
                              color: PelinesColors.textSecondary,
                            ),
                          ),
                        ],
                      );
                      final controls = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            key: Key('location-closed-$index'),
                            value: day.closed,
                            semanticLabel:
                                '${tr(context, businessDayLabels[index])}: ${tr(context, 'Closed')}',
                            onChanged: operation.isBusy
                                ? null
                                : (v) =>
                                      _replace(index, day.copyWith(closed: v)),
                          ),
                          Flexible(child: Text(tr(context, 'Closed'))),
                          IconButton(
                            key: Key('location-edit-time-$index'),
                            tooltip:
                                '${tr(context, 'Edit')}: ${tr(context, businessDayLabels[index])}',
                            onPressed: operation.isBusy || day.closed
                                ? null
                                : () async {
                                    final next = await showBusinessTimeSelector(
                                      context,
                                      day,
                                    );
                                    if (next != null && mounted) {
                                      _replace(index, next);
                                    }
                                  },
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      );
                      return c.maxWidth <
                              260 * MediaQuery.textScalerOf(context).scale(1)
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                info,
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: controls,
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(child: info),
                                controls,
                              ],
                            );
                    },
                  ),
                ),
              ],
              if (_dirty)
                Text(
                  tr(context, 'Unsaved changes'),
                  key: const Key('business-hours-unsaved'),
                ),
              FilledButton(
                key: const Key('business-hours-save'),
                onPressed: !_dirty || operation.isBusy ? null : _save,
                child: Text(
                  tr(context, operation.isBusy ? 'Saving…' : 'Save changes'),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _dayEditor(int index, bool busy) {
    final BusinessDayHours day = _draft.days[index];
    return OperationsCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            SwitchListTile(
              key: Key('business-day-$index'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, businessDayLabels[index])),
              subtitle: Text(tr(context, day.closed ? 'Closed' : 'Open')),
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
      style: PelinesControlStyles.button(PelinesButtonVariant.secondary),
      key: Key('business-${opening ? 'open' : 'close'}-$index'),
      onPressed: busy ? null : () => _pickTime(index, opening, value),
      child: Column(
        children: <Widget>[
          Text(tr(context, opening ? 'Opens' : 'Closes')),
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
          content: Text(tr(context, validation)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    await ref
        .read(businessHoursSaveProvider.notifier)
        .save(
          locationId: widget.location.id,
          originalUpdatedAt: widget.locationsLayout
              ? _baselineUpdatedAt
              : widget.location.updatedAt,
          schedule: _draft,
        );
    if (!mounted) return;
    final BusinessHoursSaveState result = ref.read(businessHoursSaveProvider);
    if (result.phase == BusinessHoursSavePhase.success) {
      if (widget.locationsLayout) {
        setState(() {
          _initial = _draft;
          _baselineUpdatedAt =
              ref.read(currentLocationProvider).value?.updatedAt ??
              _baselineUpdatedAt;
          _dirty = false;
        });
      } else {
        _dirty = false;
        Navigator.pop(context);
      }
    } else if (result.phase == BusinessHoursSavePhase.conflict) {
      final bool? reload = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(tr(context, 'Store settings were changed elsewhere.')),
          content: Text(
            tr(
              context,
              'Reload before saving to avoid overwriting those changes.',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr(context, 'Cancel')),
            ),
            FilledButton(
              style: PelinesControlStyles.button(PelinesButtonVariant.primary),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr(context, 'Reload')),
            ),
          ],
        ),
      );
      if (reload == true && mounted) {
        if (widget.locationsLayout) {
          final current = ref.read(currentLocationProvider).value;
          if (current?.hoursJson != null) {
            setState(() {
              _initial = BusinessHoursSchedule.fromJson(current!.hoursJson!);
              _draft = _initial;
              _baselineUpdatedAt = current.updatedAt;
              _dirty = false;
            });
          }
        } else {
          _dirty = false;
          Navigator.pop(context);
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(context, result.message ?? 'Business hours could not be saved.'),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(tr(context, 'Discard changes?')),
          content: Text(
            tr(context, 'Your unsaved business hours changes will be lost.'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr(context, 'Keep editing')),
            ),
            FilledButton(
              style: PelinesControlStyles.button(PelinesButtonVariant.primary),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr(context, 'Discard')),
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
