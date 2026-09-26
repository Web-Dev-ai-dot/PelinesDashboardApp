import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_settings_content.dart';
import '../models/auto_accept.dart';
import '../models/auto_cancellation.dart';
import '../models/location.dart';
import '../providers/auto_cancellation_controller.dart';
import '../providers/locations_providers.dart';
import '../providers/service_preferences_write_lock.dart';
import 'auto_accept_screen.dart';
import 'operations_parity_widgets.dart';
import 'pickup_preferences_preview.dart';

class PickupServiceCard extends ConsumerStatefulWidget {
  const PickupServiceCard({
    required this.location,
    required this.kind,
    super.key,
  });
  final Location location;
  final PickupOrderKind kind;
  @override
  ConsumerState<PickupServiceCard> createState() => _PickupServiceCardState();
}

class _PickupServiceCardState extends ConsumerState<PickupServiceCard> {
  final _value = TextEditingController();
  AutoCancellationRule? _initial;
  late Location _baseline;
  bool _enabled = true, _saving = false, _confirming = false;
  AutoCancellationUnit _unit = AutoCancellationUnit.minutes;
  String? _formatError, _message;
  bool _failed = false;
  String get _kind => widget.kind.name;
  bool get _dirty =>
      _initial != null &&
      (_enabled != _initial!.enabled ||
          _value.text != _initial!.value.toString() ||
          _unit != _initial!.unit);
  @override
  void initState() {
    super.initState();
    _load(widget.location);
  }

  @override
  void didUpdateWidget(covariant PickupServiceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && !_saving) _load(widget.location);
  }

  void _load(Location location) {
    _baseline = location;
    _formatError = null;
    try {
      _initial = AutoCancellationRule.fromJson(
        location.servicePrefsJson,
        widget.kind,
      );
      _enabled = _initial!.enabled;
      _unit = _initial!.unit;
      _value.text = _initial!.value.toString();
    } on UnsupportedAutoCancellationFormat catch (error) {
      _initial = null;
      _formatError = error.toString();
    }
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || ref.watch(servicePreferencesWriteProvider);
    final title = widget.kind == PickupOrderKind.regular
        ? 'Regular Orders'
        : 'Catering Orders';
    return PelinesSettingsCard(
      key: Key('pickup-$_kind-card'),
      title: tr(context, title),
      children: [
        PickupPreferencesPreview(
          regular: widget.kind == PickupOrderKind.regular,
          preferences: widget.location.servicePrefsJson,
          autoAccept: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr(context, 'Auto Accept'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _autoAccept(context, busy),
            ],
          ),
        ),
        const Divider(height: 32),
        Text(
          tr(context, 'Auto Cancel'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            context,
            'The scheduler checks every minute. Changes may automatically cancel existing pending orders.',
          ),
        ),
        if (widget.kind == PickupOrderKind.catering) ...[
          const SizedBox(height: 12),
          Text(
            tr(
              context,
              'The cancellation window starts when the order was created, not at the scheduled event time.',
            ),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_formatError != null) ...[
          const SizedBox(height: 16),
          Text(
            tr(context, _formatError!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ] else ...[
          SwitchListTile(
            key: Key('auto-cancel-$_kind-enabled'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr(context, 'Auto-cancel enabled')),
            value: _enabled,
            onChanged: busy
                ? null
                : (value) => setState(() => _enabled = value),
          ),
          TextField(
            key: Key('auto-cancel-$_kind-value'),
            controller: _value,
            enabled: !busy && _enabled,
            keyboardType: TextInputType.number,
            decoration: PelinesControlStyles.input(
              label: tr(context, 'Cancel orders after'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AutoCancellationUnit>(
            key: Key('auto-cancel-$_kind-unit-${_unit.name}'),
            initialValue: _unit,
            isExpanded: true,
            decoration: PelinesControlStyles.input(
              label: tr(context, 'Time unit'),
            ),
            items: [
              for (final unit in AutoCancellationUnit.values)
                DropdownMenuItem(
                  value: unit,
                  child: Text(
                    tr(
                      context,
                      unit == AutoCancellationUnit.minutes
                          ? 'Minutes'
                          : 'Hours',
                    ),
                  ),
                ),
            ],
            onChanged: busy || !_enabled
                ? null
                : (value) {
                    if (value != null) setState(() => _unit = value);
                  },
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: Key('auto-cancel-$_kind-cancel'),
            style: PelinesControlStyles.button(PelinesButtonVariant.secondary),
            onPressed: busy || !_dirty
                ? null
                : () => setState(() {
                    _load(widget.location);
                    _message = null;
                  }),
            child: Text(tr(context, 'Cancel')),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: Key('auto-cancel-$_kind-save'),
            style: PelinesControlStyles.button(PelinesButtonVariant.primary),
            onPressed: busy || !_dirty ? null : _save,
            child: Text(
              tr(context, _saving && !_confirming ? 'Saving…' : 'Save'),
            ),
          ),
        ],
        if (_saving && !_confirming)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(
            tr(context, _message!),
            key: Key('auto-cancel-$_kind-message'),
            style: TextStyle(
              color: _failed ? Theme.of(context).colorScheme.error : null,
            ),
          ),
          if (_failed)
            OutlinedButton(
              key: Key('auto-cancel-$_kind-reload'),
              style: PelinesControlStyles.button(
                PelinesButtonVariant.secondary,
              ),
              onPressed: busy ? null : _reload,
              child: Text(tr(context, 'Reload')),
            ),
        ],
      ],
    );
  }

  Widget _autoAccept(BuildContext context, bool busy) {
    try {
      final settings = AutoAcceptSettings.fromJson(
        widget.location.servicePrefsJson,
      );
      final regular = widget.kind == PickupOrderKind.regular;
      final enabled = regular ? settings.regular : settings.catering;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OperationsStatus(enabled: enabled),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              enabled
                  ? 'Automatically accepted after payment'
                  : 'Manual acceptance',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: Key('edit-auto-accept-$_kind'),
            style: PelinesControlStyles.button(PelinesButtonVariant.secondary),
            onPressed: busy
                ? null
                : () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => AutoAcceptScreen(
                        location: widget.location,
                        scope: regular
                            ? AutoAcceptScope.regular
                            : AutoAcceptScope.catering,
                      ),
                    ),
                  ),
            child: Text(tr(context, 'Edit auto-accept')),
          ),
        ],
      );
    } on UnsupportedAutoAcceptFormat catch (error) {
      return Text(
        tr(context, error.toString()),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
  }

  Future<void> _reload() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final canonical = await ref
          .read(locationsRepositoryProvider)
          .getLocation(widget.location.id);
      if (!mounted) return;
      if (ref.read(currentLocationProvider).value?.id != canonical.id) return;
      ref.read(locationsProvider.notifier).adoptCanonical(canonical);
      ref.read(currentLocationProvider.notifier).adoptCanonical(canonical);
      setState(() {
        _load(canonical);
        _message = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'The auto-cancel change could not be confirmed. Reload before retrying.';
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_saving ||
        ref.read(servicePreferencesWriteProvider) ||
        _initial == null) {
      return;
    }
    final value = RegExp(r'^-?\d+$').hasMatch(_value.text.trim())
        ? int.tryParse(_value.text.trim())
        : null;
    if (value == null) {
      setState(() {
        _message = 'Enter a whole number.';
        _failed = true;
      });
      return;
    }
    final rule = AutoCancellationRule(
      enabled: _enabled,
      value: value,
      unit: _unit,
    );
    final validation = rule.validate(widget.kind);
    if (validation != null) {
      setState(() {
        _message = validation;
        _failed = true;
      });
      return;
    }
    setState(() {
      _saving = true;
      _confirming = rule.requiresConfirmation(_initial!);
      _message = null;
    });
    try {
      if (rule.requiresConfirmation(_initial!)) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            scrollable: true,
            title: Text(tr(context, 'Apply auto-cancellation changes?')),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.location.name),
                Text(
                  tr(
                    context,
                    widget.kind == PickupOrderKind.regular
                        ? 'Regular Orders'
                        : 'Catering Orders',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(
                    context,
                    'Existing pending orders may be automatically cancelled after this change. Paid orders may be refunded.',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                key: Key('auto-cancel-$_kind-confirm-cancel'),
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(tr(context, 'Cancel')),
              ),
              FilledButton(
                key: Key('auto-cancel-$_kind-confirm'),
                style: PelinesControlStyles.button(
                  PelinesButtonVariant.primary,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(tr(context, 'Apply changes')),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        setState(() => _confirming = false);
      }
      final result = await ref
          .read(autoCancellationProvider(widget.kind).notifier)
          .save(
            locationId: _baseline.id,
            originalUpdatedAt: _baseline.updatedAt,
            original: _initial!,
            rule: rule,
          );
      if (!mounted) return;
      setState(() {
        _message = result.message;
        _failed = result.phase != AutoCancellationPhase.success;
        if (!_failed) {
          final canonical = ref.read(currentLocationProvider).value;
          if (canonical?.id == _baseline.id) _load(canonical!);
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _confirming = false;
        });
      }
    }
  }
}
