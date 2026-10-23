import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_settings_content.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../models/auto_cancellation.dart';
import '../models/location.dart';
import '../models/pickup_service_preferences.dart';
import '../models/pickup_service_settings.dart';
import '../providers/locations_providers.dart';
import '../providers/pickup_preferences_controller.dart'
    show PickupPreferencesPhase;
import '../providers/pickup_service_controller.dart';
import '../providers/service_preferences_write_lock.dart';

class PickupServiceCard extends ConsumerStatefulWidget {
  const PickupServiceCard({
    required this.location,
    required this.kind,
    this.onDirtyChanged,
    super.key,
  });
  final Location location;
  final PickupOrderKind kind;
  final ValueChanged<bool>? onDirtyChanged;
  @override
  ConsumerState<PickupServiceCard> createState() => _PickupServiceCardState();
}

class _PickupServiceCardState extends ConsumerState<PickupServiceCard> {
  final _minimum = TextEditingController(),
      _capacity = TextEditingController(),
      _duration = TextEditingController();
  PickupServiceSettings? _initial;
  bool _accept = true, _autoAccept = false, _cancel = false;
  bool _saving = false, _failed = false, _confirming = false;
  AutoCancellationUnit _unit = AutoCancellationUnit.minutes;
  String? _message, _formatError;
  bool get _regular => widget.kind == PickupOrderKind.regular;
  String get _prefix => 'pickup-${widget.kind.name}';
  bool get _busy => _saving || ref.read(servicePreferencesWriteProvider);
  bool get _dirty =>
      _initial != null && (_draft == null || !_draft!.sameAs(_initial!));
  PickupServiceSettings? get _draft {
    final minimum = PickupServicePreferences.minimumFromText(_minimum.text);
    final capacity = PickupServicePreferences.capacityFromText(_capacity.text);
    final duration = RegExp(r'^-?\d+$').hasMatch(_duration.text.trim())
        ? int.tryParse(_duration.text.trim())
        : null;
    if (minimum == null || capacity == null || duration == null) return null;
    return PickupServiceSettings(
      preferences: PickupServicePreferences(
        accept: _accept,
        minimum: minimum,
        capacity: capacity,
      ),
      autoAccept: _autoAccept,
      cancellation: AutoCancellationRule(
        enabled: _cancel,
        value: duration,
        unit: _unit,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load(widget.location);
  }

  @override
  void didUpdateWidget(covariant PickupServiceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location.id != widget.location.id ||
        (!_dirty && !_saving && !_failed)) {
      _load(widget.location);
    }
  }

  void _load(Location location) {
    _formatError = null;
    try {
      _initial = PickupServiceSettings.fromJson(
        location.servicePrefsJson,
        widget.kind,
      );
      _accept = _initial!.preferences.accept;
      _minimum.text = _initial!.preferences.minimumText;
      _capacity.text = _initial!.preferences.capacity.toString();
      _autoAccept = _initial!.autoAccept;
      _cancel = _initial!.cancellation.enabled;
      _duration.text = _initial!.cancellation.value.toString();
      _unit = _initial!.cancellation.unit;
    } catch (error) {
      _initial = null;
      _formatError = error.toString();
    }
  }

  void _changed(VoidCallback change) {
    setState(() {
      change();
      _message = null;
    });
    widget.onDirtyChanged?.call(_dirty);
  }

  @override
  void dispose() {
    _minimum.dispose();
    _capacity.dispose();
    _duration.dispose();
    super.dispose();
  }

  Widget _toggle(
    String key,
    String title,
    String description,
    bool value,
    ValueChanged<bool> change,
  ) => SwitchListTile(
    key: Key(key),
    contentPadding: EdgeInsets.zero,
    title: Text(tr(context, title)),
    subtitle: Text(tr(context, description)),
    value: value,
    onChanged: _busy || _failed ? null : change,
  );
  Widget _input(
    String key,
    String label,
    TextEditingController controller, {
    bool money = false,
    bool enabled = true,
    String? helper,
    String? error,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(tr(context, label), style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: PelinesSpacing.xs),
      Semantics(
        label: tr(context, label),
        child: TextField(
          key: Key(key),
          controller: controller,
          enabled: !_busy && !_failed && enabled,
          keyboardType: TextInputType.numberWithOptions(decimal: money),
          onChanged: (_) => _changed(() {}),
          decoration: PelinesControlStyles.input().copyWith(
            prefixText: money ? '\$ ' : null,
            helperText: helper == null ? null : tr(context, helper),
            helperMaxLines: 4,
            errorText: error == null ? null : tr(context, error),
            errorMaxLines: 4,
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    ref.watch(servicePreferencesWriteProvider);
    final suffix = widget.kind.name;
    final kind = _regular ? 'regular' : 'catering';
    return PelinesSettingsCard(
      key: Key('pickup-$suffix-card'),
      title: tr(context, _regular ? 'Regular Orders' : 'Catering Orders'),
      children: [
        const Divider(height: 24),
        if (_formatError != null)
          Text(
            tr(context, _formatError!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          )
        else ...[
          _toggle(
            '$_prefix-accept',
            _regular ? 'Accept regular orders' : 'Accept catering orders',
            _regular
                ? 'When off, customers will not be able to place regular pickup orders.'
                : 'When off, customers will not be able to place catering orders.',
            _accept,
            (value) => _changed(() => _accept = value),
          ),
          const Divider(height: 32),
          _toggle(
            'auto-accept-$kind-switch',
            _regular
                ? 'Auto-accept regular orders'
                : 'Auto-accept catering orders',
            'When on, paid orders are automatically confirmed. When off, orders must be manually accepted by the restaurant.',
            _autoAccept,
            (value) => _changed(() => _autoAccept = value),
          ),
          const SizedBox(height: 20),
          _input(
            '$_prefix-minimum',
            _regular
                ? 'Minimum purchase — regular orders (\$)'
                : 'Minimum purchase — catering orders (\$)',
            _minimum,
            money: true,
            helper: '0 = No minimum',
            error:
                PickupServicePreferences.minimumFromText(_minimum.text) == null
                ? PickupServicePreferences.minimumError
                : null,
          ),
          const SizedBox(height: 20),
          _input(
            '$_prefix-capacity',
            _regular
                ? 'Daily capacity — regular orders per day'
                : 'Daily capacity — catering orders per delivery date',
            _capacity,
            helper: '0 = No daily limit',
            error:
                PickupServicePreferences.capacityFromText(_capacity.text) ==
                    null
                ? PickupServicePreferences.capacityError
                : null,
          ),
          if (!_regular) ...[
            const SizedBox(height: 8),
            Text(
              tr(
                context,
                'Counted by the delivery date, not by the date the order was placed.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const Divider(height: 40),
          _toggle(
            'auto-cancel-$kind-enabled',
            _regular
                ? 'Enable auto-cancel for regular orders'
                : 'Enable auto-cancel for catering orders',
            'The scheduler checks every minute. Changes may automatically cancel existing pending orders.',
            _cancel,
            (value) => _changed(() => _cancel = value),
          ),
          const SizedBox(height: 16),
          _input(
            'auto-cancel-$kind-value',
            _regular
                ? 'Cancel regular orders after'
                : 'Cancel catering orders after',
            _duration,
            enabled: _cancel,
            error: !_cancel
                ? null
                : int.tryParse(_duration.text.trim()) == null
                ? 'Enter a whole number.'
                : _draft?.cancellation.validate(widget.kind),
          ),
          const SizedBox(height: 12),
          Text(
            tr(
              context,
              'If an order is not accepted within this time, it will be automatically cancelled.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<AutoCancellationUnit>(
            key: Key('auto-cancel-$kind-unit-${_unit.name}'),
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
            onChanged: _busy || _failed || !_cancel
                ? null
                : (value) {
                    if (value != null) _changed(() => _unit = value);
                  },
          ),
          if (!_regular) ...[
            const SizedBox(height: 12),
            Text(
              tr(
                context,
                'The cancellation window starts when the order was created, not at the scheduled event time.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const Divider(height: 40),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              key: Key('$_prefix-save'),
              style: PelinesControlStyles.button(PelinesButtonVariant.primary),
              onPressed:
                  _busy ||
                      _failed ||
                      !_dirty ||
                      _draft == null ||
                      _draft!.validate(widget.kind) != null
                  ? null
                  : _save,
              child: Text(
                tr(context, _saving ? 'Saving…' : 'Save changes'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          if (_dirty && !_failed)
            TextButton(
              key: Key('$_prefix-cancel'),
              onPressed: _busy
                  ? null
                  : () {
                      _changed(() => _load(widget.location));
                    },
              child: Text(tr(context, 'Cancel')),
            ),
        ],
        if (_saving && !_confirming)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                tr(context, _message!),
                key: Key('$_prefix-message'),
                style: TextStyle(
                  color: _failed ? Theme.of(context).colorScheme.error : null,
                ),
              ),
            ),
          ),
        if (_failed || _formatError != null)
          OutlinedButton(
            key: Key('$_prefix-reload'),
            style: PelinesControlStyles.button(PelinesButtonVariant.secondary),
            onPressed: _busy ? null : _reload,
            child: Text(tr(context, 'Reload')),
          ),
      ],
    );
  }

  Future<bool> _confirm(String title, String message, String key) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text(tr(context, title)),
          content: Text(tr(context, message)),
          actions: [
            TextButton(
              key: Key('$key-cancel'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr(context, 'Cancel')),
            ),
            FilledButton(
              key: Key(key),
              style: PelinesControlStyles.button(PelinesButtonVariant.primary),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr(context, 'Apply changes')),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _save() async {
    final draft = _draft;
    if (_busy || _failed || draft == null || _initial == null) return;
    final id = widget.location.id;
    setState(() {
      _saving = true;
      _confirming =
          draft.autoAccept != _initial!.autoAccept ||
          draft.cancellation.requiresConfirmation(_initial!.cancellation);
    });
    try {
      if (draft.autoAccept != _initial!.autoAccept) {
        final ok = await _confirm(
          draft.autoAccept
              ? 'Enable automatic acceptance?'
              : 'Use manual acceptance?',
          draft.autoAccept
              ? (_regular
                    ? 'Paid regular orders can move directly to Confirmed without manual review.'
                    : 'Paid catering orders can move directly to Confirmed without manual review. This may commit the restaurant to new catering orders before staff reviews them.')
              : 'Paid orders processed after this change will remain Pending until staff accepts them.',
          'auto-accept-${widget.kind.name}-confirm',
        );
        if (!ok || !mounted) return;
      }
      if (draft.cancellation.requiresConfirmation(_initial!.cancellation)) {
        final ok = await _confirm(
          'Apply auto-cancellation changes?',
          'Existing pending orders may be automatically cancelled after this change. Paid orders may be refunded.',
          'auto-cancel-${widget.kind.name}-confirm',
        );
        if (!ok || !mounted) return;
      }
      setState(() => _confirming = false);
      final result = await ref
          .read(pickupServiceProvider(widget.kind).notifier)
          .save(locationId: id, original: _initial!, settings: draft);
      if (!mounted || widget.location.id != id) return;
      setState(() {
        _message = result.message;
        _failed = result.phase != PickupPreferencesPhase.success;
        if (!_failed) {
          _load(ref.read(currentLocationProvider).value ?? widget.location);
        }
      });
      widget.onDirtyChanged?.call(_dirty);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _confirming = false;
        });
      }
    }
  }

  Future<void> _reload() async {
    if (_busy) return;
    if (_dirty &&
        !await _confirm(
          'Discard changes?',
          'Your unsaved changes will be lost.',
          '$_prefix-discard',
        )) {
      return;
    }
    if (!mounted) return;
    final id = widget.location.id;
    setState(() => _saving = true);
    try {
      final canonical = await ref
          .read(locationsRepositoryProvider)
          .getLocation(id);
      if (!mounted || ref.read(currentLocationProvider).value?.id != id) return;
      ref.read(locationsProvider.notifier).adoptCanonical(canonical);
      ref.read(currentLocationProvider.notifier).adoptCanonical(canonical);
      setState(() {
        _load(canonical);
        _failed = false;
        _message = null;
      });
      widget.onDirtyChanged?.call(false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = 'The service preference change could not be confirmed. Reload before retrying.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
