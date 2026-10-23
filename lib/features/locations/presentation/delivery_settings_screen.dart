import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_settings_content.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../orders/presentation/order_ui_helpers.dart';
import '../models/catering_delivery.dart';
import '../models/location.dart';
import '../models/regular_delivery.dart';
import '../providers/catering_delivery_controller.dart';
import '../providers/locations_providers.dart';
import '../providers/regular_delivery_controller.dart';

class DeliverySettingsScreen extends ConsumerStatefulWidget {
  const DeliverySettingsScreen({super.key});
  @override
  ConsumerState<DeliverySettingsScreen> createState() =>
      _DeliverySettingsState();
}

class _DeliverySettingsState extends ConsumerState<DeliverySettingsScreen> {
  final _dirty = <String, bool>{};
  int _revision = 0;
  bool _saving = false;
  String? _locationId;
  bool get _hasChanges => _dirty.values.any((v) => v);

  Future<bool> _leave() async {
    if (_saving) return false;
    if (!_hasChanges) return true;
    final discard =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr(context, 'Discard changes?')),
            content: Text(
              tr(context, 'Your unsaved delivery settings will be lost.'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr(context, 'Keep editing')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr(context, 'Discard')),
              ),
            ],
          ),
        ) ??
        false;
    if (!discard || !mounted) return false;
    setState(() {
      _dirty.clear();
      _revision++;
    });
    await WidgetsBinding.instance.endOfFrame;
    return true;
  }

  @override
  Widget build(BuildContext context) => AdminPopScope<void>(
    canPop: !_hasChanges && !_saving,
    onRequestLeave: _leave,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop && await _leave() && context.mounted) {
        Navigator.maybePop(context);
      }
    },
    child: AdminSectionScaffold(
      key: const Key('delivery-settings-screen'),
      appBar: AdminAppBar(
        title: Text(
          tr(context, 'Delivery Settings'),
          style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
        ),
      ),
      body: ref
          .watch(currentLocationProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr(context, error.toString())),
                    OutlinedButton(
                      onPressed: () {
                        ref.invalidate(locationsProvider);
                        ref.invalidate(currentLocationProvider);
                      },
                      child: Text(tr(context, 'Try again')),
                    ),
                  ],
                ),
              ),
            ),
            data: (location) {
              if (location == null) {
                return Center(
                  child: Text(tr(context, 'Choose a location to continue.')),
                );
              }
              if (_locationId != location.id) {
                _locationId = location.id;
                _dirty.clear();
              }
              return PelinesPageBody(
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(PelinesSpacing.lg),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              tr(
                                context,
                                'Configure flat-fee delivery per location.',
                              ),
                              style: const TextStyle(
                                color: PelinesColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            for (final catering in [false, true]) ...[
                              _DeliveryCard(
                                key: ValueKey(
                                  '${location.id}-$catering-$_revision',
                                ),
                                location: location,
                                catering: catering,
                                busy: _saving,
                                onBusy: (value) =>
                                    setState(() => _saving = value),
                                onDirty: (value) =>
                                    setState(() => _dirty['$catering'] = value),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
    ),
  );
}

class _DeliveryCard extends ConsumerStatefulWidget {
  const _DeliveryCard({
    super.key,
    required this.location,
    required this.catering,
    required this.busy,
    required this.onBusy,
    required this.onDirty,
  });
  final Location location;
  final bool catering, busy;
  final ValueChanged<bool> onBusy, onDirty;
  @override
  ConsumerState<_DeliveryCard> createState() => _DeliveryCardState();
}

class _DeliveryCardState extends ConsumerState<_DeliveryCard> {
  late Location _baseline;
  final _fee = TextEditingController();
  bool _enabled = false;
  String? _error;
  bool _blocked = false;
  bool _submitting = false;
  String get _kind => widget.catering ? 'catering' : 'regular';
  bool _initialEnabled(Location l) => widget.catering
      ? CateringDeliverySettings.fromJson(l.cateringDeliveryJson).enabled
      : RegularDeliverySettings.fromJson(l.regularDeliveryJson).enabled;
  int _initialFee(Location l) => widget.catering
      ? l.deliveryFeeCents
      : RegularDeliverySettings.fromJson(l.regularDeliveryJson).feeCents;
  bool get _dirty =>
      _enabled != _initialEnabled(_baseline) ||
      _fee.text != moneyInput(_initialFee(_baseline));
  @override
  void initState() {
    super.initState();
    _reset(widget.location);
  }

  void _reset(Location location) {
    _baseline = location;
    try {
      _enabled = _initialEnabled(location);
      _fee.text = moneyInput(_initialFee(location));
      _error = null;
    } catch (e) {
      _error = e.toString();
      _blocked = true;
    }
  }

  @override
  void didUpdateWidget(covariant _DeliveryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A save in the other card may advance updatedAt, but must not replace this draft.
    if (!_blocked && oldWidget.location != widget.location) {
      if (!_dirty) {
        _reset(widget.location);
      } else {
        final unchanged = widget.catering
            ? mapEquals(
                    _baseline.cateringDeliveryJson,
                    widget.location.cateringDeliveryJson,
                  ) &&
                  _baseline.deliveryFeeCents ==
                      widget.location.deliveryFeeCents &&
                  _baseline.deliveryMinimumCents ==
                      widget.location.deliveryMinimumCents
            : mapEquals(
                _baseline.regularDeliveryJson,
                widget.location.regularDeliveryJson,
              );
        if (unchanged) _baseline = widget.location;
      }
    }
  }

  @override
  void dispose() {
    _fee.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() => _error = null);
    widget.onDirty(_dirty);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.catering
        ? 'Catering Orders — Delivery'
        : 'Regular Orders — Delivery';
    if (_blocked) {
      return PelinesSettingsCard(
        title: tr(context, title),
        children: [
          Text(
            tr(
              context,
              _error ??
                  'Reload before saving to avoid overwriting those changes.',
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _blocked = false;
                _reset(widget.location);
              });
              widget.onDirty(false);
            },
            child: Text(tr(context, 'Reload')),
          ),
        ],
      );
    }
    return PelinesSettingsCard(
      key: Key('$_kind-delivery-card'),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              backgroundColor: PelinesColors.brandPrimarySoft,
              foregroundColor: PelinesColors.brandPrimary,
              child: Icon(Icons.local_shipping_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, title),
                    style: PelinesTypography.sectionTitle(
                      Theme.of(context).textTheme,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      context,
                      widget.catering
                          ? 'Offer delivery on catering orders for this location.'
                          : 'Offer flat-fee delivery on regular (non-catering) orders for this location.',
                    ),
                    style: const TextStyle(color: PelinesColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 40),
        SwitchListTile(
          key: Key('$_kind-delivery-enabled'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            tr(context, 'Enable delivery'),
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            tr(
              context,
              widget.catering
                  ? 'When off, customers can only choose pickup for catering orders.'
                  : 'When off, customers can only choose pickup for regular orders.',
            ),
          ),
          value: _enabled,
          onChanged: widget.busy
              ? null
              : (v) {
                  _enabled = v;
                  _changed();
                },
        ),
        const Divider(height: 40),
        Text(
          tr(context, 'Delivery cost'),
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: tr(context, 'Delivery cost'),
          child: TextField(
            key: Key('$_kind-delivery-fee'),
            controller: _fee,
            enabled: _enabled && !widget.busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: PelinesControlStyles.input().copyWith(
              prefixText: r'$ ',
              errorText: _error == null ? null : tr(context, _error!),
            ),
            onChanged: (_) => _changed(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            context,
            widget.catering
                ? 'Flat delivery cost added to the catering order total at checkout.'
                : 'Flat delivery cost added to the order total at checkout.',
          ),
          style: const TextStyle(color: PelinesColors.textSecondary),
        ),
        const SizedBox(height: 16),
        Text(
          '${tr(context, 'Delivery Minimum')}: ${money(widget.catering ? widget.location.deliveryMinimumCents : RegularDeliverySettings.fromJson(widget.location.regularDeliveryJson).minimumCents)}',
        ),
        Text(
          tr(
            context,
            'This value is currently managed outside the mobile app.',
          ),
          style: const TextStyle(color: PelinesColors.textSecondary),
        ),
        const Divider(height: 40),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            key: Key('$_kind-delivery-save'),
            style: PelinesControlStyles.button(PelinesButtonVariant.primary),
            onPressed: widget.busy || !_dirty ? null : _save,
            child: Text(
              tr(context, widget.busy ? 'Saving…' : 'Save changes'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (widget.busy || _submitting) return;
    final cents = parseMoneyCents(_fee.text);
    if (cents == null) {
      setState(
        () => _error =
            'Enter a valid non-negative fee with no more than two decimals.',
      );
      return;
    }
    _submitting = true;
    widget.onBusy(true);
    try {
      if (widget.catering && _enabled != _initialEnabled(_baseline)) {
        final confirmed =
            await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(
                  tr(
                    context,
                    _enabled
                        ? 'Enable catering delivery for {location}?'
                        : 'Disable catering delivery for {location}?',
                  ).replaceAll('{location}', widget.location.name),
                ),
                content: Text(
                  tr(
                    context,
                    _enabled
                        ? 'New catering delivery orders will be allowed again. Minimum-order and other backend rules still apply.'
                        : 'New catering delivery orders will be blocked for this location. Existing orders are not cancelled.',
                  ),
                ),
                actions: [
                  TextButton(
                    key: const Key('catering-delivery-confirm-cancel'),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(tr(context, 'Cancel')),
                  ),
                  FilledButton(
                    key: const Key('catering-delivery-confirm'),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      tr(
                        context,
                        _enabled ? 'Enable delivery' : 'Disable delivery',
                      ),
                    ),
                  ),
                ],
              ),
            ) ??
            false;
        if (!confirmed || !mounted) return;
      }
      bool success, conflict;
      String? message;
      if (widget.catering) {
        await ref
            .read(cateringDeliveryProvider.notifier)
            .save(
              locationId: _baseline.id,
              originalUpdatedAt: _baseline.updatedAt,
              originalEnabled: _initialEnabled(_baseline),
              enabled: _enabled,
              originalFeeCents: _initialFee(_baseline),
              feeCents: cents,
              originalMinimumCents: _baseline.deliveryMinimumCents,
            );
        final result = ref.read(cateringDeliveryProvider);
        success = result.phase == CateringDeliveryPhase.success;
        conflict = result.phase == CateringDeliveryPhase.conflict;
        message = result.message;
      } else {
        await ref
            .read(regularDeliveryProvider.notifier)
            .save(
              locationId: _baseline.id,
              originalUpdatedAt: _baseline.updatedAt,
              enabled: _enabled,
              feeCents: cents,
            );
        final result = ref.read(regularDeliveryProvider);
        success = result.phase == RegularDeliveryPhase.success;
        conflict = result.phase == RegularDeliveryPhase.conflict;
        message = result.message;
      }
      if (!mounted) return;
      if (success) {
        final canonical = ref.read(currentLocationProvider).value;
        if (canonical?.id == _baseline.id) {
          setState(() => _reset(canonical!));
          widget.onDirty(false);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'Delivery settings saved.'))),
        );
      } else {
        setState(() {
          _error =
              message ??
              'Reload before saving to avoid overwriting those changes.';
          _blocked = conflict;
        });
      }
    } finally {
      _submitting = false;
      if (mounted) widget.onBusy(false);
    }
  }
}
