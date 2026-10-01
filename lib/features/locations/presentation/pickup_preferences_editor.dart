import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../models/auto_cancellation.dart';
import '../models/location.dart';
import '../models/pickup_service_preferences.dart';
import '../providers/locations_providers.dart';
import '../providers/pickup_preferences_controller.dart';
import '../providers/service_preferences_write_lock.dart';

class PickupPreferencesEditor extends ConsumerStatefulWidget {
  const PickupPreferencesEditor({
    required this.kind,
    required this.location,
    required this.autoAccept,
    super.key,
  });

  final PickupOrderKind kind;
  final Location location;
  final Widget autoAccept;

  @override
  ConsumerState<PickupPreferencesEditor> createState() =>
      _PickupPreferencesEditorState();
}

class _PickupPreferencesEditorState
    extends ConsumerState<PickupPreferencesEditor> {
  final _minimum = TextEditingController();
  final _capacity = TextEditingController();
  late Location _baseline;
  PickupServicePreferences? _initial;
  bool _accept = true, _saving = false, _failed = false;
  String? _formatError, _message;
  String get _prefix => 'pickup-${widget.kind.name}';
  bool get _dirty =>
      _initial != null &&
      (_accept != _initial!.accept ||
          _minimum.text != _initial!.minimumText ||
          _capacity.text != _initial!.capacity.toString());
  PickupServicePreferences? get _draft {
    final minimum = PickupServicePreferences.minimumFromText(_minimum.text);
    final capacity = PickupServicePreferences.capacityFromText(_capacity.text);
    if (minimum == null || capacity == null) return null;
    return PickupServicePreferences(
      accept: _accept,
      minimum: minimum,
      capacity: capacity,
    );
  }

  @override
  void initState() {
    super.initState();
    _load(widget.location);
  }

  @override
  void didUpdateWidget(covariant PickupPreferencesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location.id != widget.location.id ||
        oldWidget.kind != widget.kind) {
      _load(widget.location);
      _failed = false;
      _message = null;
    } else if (!_dirty && !_saving && !_failed) {
      _load(widget.location);
    }
  }

  void _load(Location location) {
    _baseline = location;
    _formatError = null;
    try {
      _initial = PickupServicePreferences.fromJson(
        location.servicePrefsJson,
        widget.kind,
      );
      _accept = _initial!.accept;
      _minimum.text = _initial!.minimumText;
      _capacity.text = _initial!.capacity.toString();
    } on UnsupportedPickupPreferencesFormat catch (error) {
      _initial = null;
      _formatError = error.toString();
    }
  }

  @override
  void dispose() {
    _minimum.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Widget _input(bool money, bool busy) {
    final valid = money
        ? PickupServicePreferences.minimumFromText(_minimum.text) != null
        : PickupServicePreferences.capacityFromText(_capacity.text) != null;
    return TextField(
      key: Key('$_prefix-${money ? 'minimum' : 'capacity'}'),
      controller: money ? _minimum : _capacity,
      enabled: !busy && !_failed,
      keyboardType: TextInputType.numberWithOptions(decimal: money),
      onChanged: (_) => setState(() => _message = null),
      decoration:
          PelinesControlStyles.input(
            label: tr(context, money ? 'Minimum purchase' : 'Daily capacity'),
          ).copyWith(
            prefixText: money ? '\$ ' : null,
            helperText: tr(
              context,
              money ? '0 = No minimum' : '0 = No daily limit',
            ),
            helperMaxLines: 3,
            errorMaxLines: 4,
            errorText: valid
                ? null
                : tr(
                    context,
                    money
                        ? PickupServicePreferences.minimumError
                        : PickupServicePreferences.capacityError,
                  ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || ref.watch(servicePreferencesWriteProvider);
    final regular = widget.kind == PickupOrderKind.regular;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_formatError == null)
          SwitchListTile(
            key: Key('$_prefix-accept'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              tr(
                context,
                regular ? 'Accept regular orders' : 'Accept catering orders',
              ),
            ),
            value: _accept,
            onChanged: busy || _failed
                ? null
                : (value) => setState(() {
                    _accept = value;
                    _message = null;
                  }),
          )
        else
          Text(
            tr(context, _formatError!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
        widget.autoAccept,
        const SizedBox(height: 16),
        if (_formatError == null) ...[
          _input(true, busy),
          const SizedBox(height: 16),
          _input(false, busy),
          const SizedBox(height: 16),
          OutlinedButton(
            key: Key('$_prefix-cancel'),
            style: PelinesControlStyles.button(PelinesButtonVariant.secondary),
            onPressed: busy || !_dirty || _failed
                ? null
                : () => setState(() {
                    _load(widget.location);
                    _message = null;
                  }),
            child: Text(tr(context, 'Cancel')),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: Key('$_prefix-save'),
            style: PelinesControlStyles.button(PelinesButtonVariant.primary),
            onPressed: busy || _failed || !_dirty || _draft == null
                ? null
                : _save,
            child: Text(
              tr(
                context,
                _saving
                    ? 'Saving…'
                    : regular
                    ? 'Save Regular'
                    : 'Save Catering',
              ),
            ),
          ),
        ],
        if (_saving)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(
            tr(context, _message!),
            key: Key('$_prefix-message'),
            style: TextStyle(
              color: _failed ? Theme.of(context).colorScheme.error : null,
            ),
          ),
        ],
        if (_failed || _formatError != null)
          OutlinedButton(
            key: Key('$_prefix-reload'),
            style: PelinesControlStyles.button(PelinesButtonVariant.secondary),
            onPressed: busy ? null : _reload,
            child: Text(tr(context, 'Reload')),
          ),
      ],
    );
  }

  Future<void> _save() async {
    final draft = _draft;
    if (_saving ||
        _failed ||
        ref.read(servicePreferencesWriteProvider) ||
        _initial == null ||
        draft == null) {
      return;
    }
    final id = _baseline.id;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final result = await ref
          .read(pickupPreferencesProvider(widget.kind).notifier)
          .save(
            locationId: id,
            originalUpdatedAt: _baseline.updatedAt,
            original: _initial!,
            preferences: draft,
          );
      if (!mounted || widget.location.id != id) return;
      setState(() {
        _message = result.message;
        _failed = result.phase != PickupPreferencesPhase.success;
        if (!_failed) {
          final canonical = ref.read(currentLocationProvider).value;
          if (canonical?.id == id) _load(canonical!);
        }
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reload() async {
    if (_saving || ref.read(servicePreferencesWriteProvider)) return;
    final id = widget.location.id;
    setState(() => _saving = true);
    try {
      final canonical = await ref
          .read(locationsRepositoryProvider)
          .getLocation(id);
      if (!mounted ||
          widget.location.id != id ||
          ref.read(currentLocationProvider).value?.id != id) {
        return;
      }
      ref.read(locationsProvider.notifier).adoptCanonical(canonical);
      ref.read(currentLocationProvider.notifier).adoptCanonical(canonical);
      setState(() {
        _load(canonical);
        _failed = false;
        _message = null;
      });
    } catch (_) {
      if (mounted && widget.location.id == id) {
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
