import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../orders/presentation/order_ui_helpers.dart';
import '../models/location.dart';
import '../models/regular_delivery.dart';
import '../providers/regular_delivery_controller.dart';

class RegularDeliveryScreen extends ConsumerStatefulWidget {
  const RegularDeliveryScreen({super.key, required this.location});
  final Location location;
  @override
  ConsumerState<RegularDeliveryScreen> createState() =>
      _RegularDeliveryScreenState();
}

class _RegularDeliveryScreenState extends ConsumerState<RegularDeliveryScreen> {
  late final RegularDeliverySettings _initial;
  late bool _enabled;
  late final TextEditingController _fee;

  bool get _dirty =>
      _enabled != _initial.enabled ||
      _fee.text != moneyInput(_initial.feeCents);

  @override
  void initState() {
    super.initState();
    _initial = RegularDeliverySettings.fromJson(
      widget.location.regularDeliveryJson,
    );
    _enabled = _initial.enabled;
    _fee = TextEditingController(text: moneyInput(_initial.feeCents));
  }

  @override
  void dispose() {
    _fee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final RegularDeliveryState operation = ref.watch(regularDeliveryProvider);
    return PopScope<void>(
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
        appBar: AppBar(title: const Text('Regular Delivery')),
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
              'Regular delivery settings affect online delivery orders for the regular menu.',
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              key: const Key('regular-delivery-enabled'),
              title: const Text('Enabled'),
              value: _enabled,
              onChanged: operation.isBusy
                  ? null
                  : (bool value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('regular-delivery-fee'),
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
              money(_initial.minimumCents),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'This value is currently managed outside the mobile app.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('regular-delivery-save'),
              onPressed: operation.isBusy ? null : _save,
              child: Text(
                operation.isBusy ? 'Saving…' : 'Save regular delivery',
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
    await ref
        .read(regularDeliveryProvider.notifier)
        .save(
          locationId: widget.location.id,
          originalUpdatedAt: widget.location.updatedAt,
          enabled: _enabled,
          feeCents: cents,
        );
    if (!mounted) return;
    final RegularDeliveryState result = ref.read(regularDeliveryProvider);
    if (result.phase == RegularDeliveryPhase.success) {
      Navigator.pop(context);
    } else if (result.phase == RegularDeliveryPhase.conflict) {
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
            result.message ?? 'Regular delivery could not be saved.',
          ),
        ),
      );
    }
  }

  Future<bool> _discard() async =>
      await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text(
            'Your unsaved regular delivery changes will be lost.',
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
