import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_settings_content.dart';

import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/admin_navigation.dart';
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
        appBar: AdminAppBar(
          title: Text(
            tr(context, 'Regular Delivery'),
            style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
          ),
        ),
        body: PelinesSettingsForm(
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
            Text(
              tr(
                context,
                'Regular delivery settings affect online delivery orders for the regular menu.',
              ),
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              key: const Key('regular-delivery-enabled'),
              title: Text(tr(context, 'Enabled')),
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
              decoration: PelinesControlStyles.input(
                label: tr(context, 'Delivery fee'),
              ).copyWith(prefixText: r'$ '),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(tr(context, 'Flat delivery fee added to regular orders.')),
            const Divider(height: 32),
            Text(
              tr(context, 'Delivery Minimum'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text(
              money(_initial.minimumCents),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              tr(
                context,
                'This value is currently managed outside the mobile app.',
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              key: const Key('regular-delivery-cancel'),
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
              key: const Key('regular-delivery-save'),
              onPressed: operation.isBusy ? null : _save,
              child: Text(
                operation.isBusy
                    ? tr(context, 'Saving…')
                    : tr(context, 'Save regular delivery'),
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
              style: PelinesControlStyles.button(PelinesButtonVariant.primary),
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
              style: PelinesControlStyles.button(PelinesButtonVariant.primary),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      ) ??
      false;
}
