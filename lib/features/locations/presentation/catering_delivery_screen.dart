import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../orders/presentation/order_ui_helpers.dart';
import '../models/catering_delivery.dart';
import '../models/location.dart';
import '../providers/catering_delivery_controller.dart';

class CateringDeliveryScreen extends ConsumerStatefulWidget {
  const CateringDeliveryScreen({super.key, required this.location});
  final Location location;

  @override
  ConsumerState<CateringDeliveryScreen> createState() =>
      _CateringDeliveryScreenState();
}

class _CateringDeliveryScreenState
    extends ConsumerState<CateringDeliveryScreen> {
  late final CateringDeliverySettings _initial;
  late bool _enabled;
  late final TextEditingController _fee;

  int? get _feeCents => parseMoneyCents(_fee.text);
  bool get _enabledDirty => _enabled != _initial.enabled;
  bool get _feeDirty =>
      _feeCents != null && _feeCents != widget.location.deliveryFeeCents;
  bool get _dirty => _enabledDirty || _feeDirty;

  @override
  void initState() {
    super.initState();
    _initial = CateringDeliverySettings.fromJson(
      widget.location.cateringDeliveryJson,
    );
    _enabled = _initial.enabled;
    _fee = TextEditingController(
      text: moneyInput(widget.location.deliveryFeeCents),
    );
  }

  @override
  void dispose() {
    _fee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CateringDeliveryState operation = ref.watch(cateringDeliveryProvider);
    return AdminPopScope<void>(
      canPop: !_dirty || operation.isBusy,
      onPopInvokedWithResult: (bool didPop, void result) async {
        if (!didPop &&
            !operation.isBusy &&
            await _discard() &&
            context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AdminAppBar(title: const Text('Catering Delivery')),
        body: ListView(
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
            const SizedBox(height: 8),
            const Text(
              'Catering Delivery controls delivery availability for catering orders only.',
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              key: const Key('catering-delivery-enabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              subtitle: _initial.usesDefault && !_enabledDirty
                  ? const Text('Using default setting')
                  : null,
              value: _enabled,
              onChanged: operation.isBusy
                  ? null
                  : (bool value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('catering-delivery-fee'),
              controller: _fee,
              enabled: !operation.isBusy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                prefixText: r'$ ',
                labelText: 'Delivery fee',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            Text(
              'Minimum order',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text(
              money(widget.location.deliveryMinimumCents),
              key: const Key('catering-delivery-minimum'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'This value is currently managed outside the mobile app.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('catering-delivery-save'),
              onPressed: operation.isBusy || !_dirty ? null : _save,
              child: Text(
                operation.isBusy ? 'Saving…' : 'Save catering delivery',
              ),
            ),
            if (operation.isBusy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final int? cents = parseMoneyCents(_fee.text);
    if (cents == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a valid non-negative fee with no more than two decimals.',
          ),
        ),
      );
      return;
    }
    if (_enabledDirty && !await _confirmEnabledChange()) return;
    if (!mounted) return;
    await ref
        .read(cateringDeliveryProvider.notifier)
        .save(
          locationId: widget.location.id,
          originalUpdatedAt: widget.location.updatedAt,
          originalEnabled: _initial.enabled,
          enabled: _enabled,
          originalFeeCents: widget.location.deliveryFeeCents,
          feeCents: cents,
          originalMinimumCents: widget.location.deliveryMinimumCents,
        );
    if (!mounted) return;
    final CateringDeliveryState result = ref.read(cateringDeliveryProvider);
    if (result.phase == CateringDeliveryPhase.success) {
      Navigator.pop(context);
    } else if (result.phase == CateringDeliveryPhase.conflict) {
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
      if (reload == true && mounted) Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message ?? 'Catering delivery could not be saved.',
          ),
        ),
      );
    }
  }

  Future<bool> _confirmEnabledChange() async =>
      await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(
            _enabled
                ? 'Enable catering delivery for ${widget.location.name}?'
                : 'Disable catering delivery for ${widget.location.name}?',
          ),
          content: Text(
            _enabled
                ? 'New catering delivery orders will be allowed again. Minimum-order and other backend rules still apply.'
                : 'New catering delivery orders will be blocked for this location. Existing orders are not cancelled.',
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('catering-delivery-confirm-cancel'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_enabled ? 'Keep disabled' : 'Keep enabled'),
            ),
            FilledButton(
              key: const Key('catering-delivery-confirm'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_enabled ? 'Enable delivery' : 'Disable delivery'),
            ),
          ],
        ),
      ) ??
      false;

  Future<bool> _discard() async =>
      await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text(
            'Your unsaved catering delivery changes will be lost.',
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
}
