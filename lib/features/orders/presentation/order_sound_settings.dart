import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_settings_content.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../data/order_alert_sound.dart';
import '../providers/order_alert_coordinator.dart';

class OrderSoundSettings extends ConsumerStatefulWidget {
  const OrderSoundSettings({super.key});

  @override
  ConsumerState<OrderSoundSettings> createState() => _OrderSoundSettingsState();
}

class _OrderSoundSettingsState extends ConsumerState<OrderSoundSettings> {
  bool _busy = false;
  OrderSoundResult? _result;

  Future<void> _test() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    final result = await ref.read(orderAlertCoordinatorProvider).testSound();
    if (!mounted) return;
    setState(() {
      _result = result;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final message = switch ((_result?.status, _result?.reason)) {
      (OrderSoundStatus.started, _) =>
        'Sound started. Check that you can hear it.',
      (_, 'busy') =>
        'Wait for the current order alert or sound test to finish.',
      (_, 'devicePolicy') => 'Sound is muted by device settings.',
      (_, 'inactive' || 'interrupted') =>
        'Keep the app active and try again after the interruption.',
      (_, 'asset') => 'The order sound file could not be loaded.',
      (OrderSoundStatus.failed, _) =>
        'Could not start the order sound. Try again.',
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PelinesSectionHeading(tr(context, 'Order alerts')),
        const SizedBox(height: PelinesSpacing.md),
        PelinesSettingsCard(
          children: [
            Text(
              tr(
                context,
                'Keep the app open with audible device volume to hear order alerts.',
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton(
                onPressed: _busy ? null : _test,
                child: Text(tr(context, 'Test sound')),
              ),
            ),
            if (message != null)
              Semantics(liveRegion: true, child: Text(tr(context, message))),
          ],
        ),
      ],
    );
  }
}
