import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../models/auto_accept.dart';
import '../models/location.dart';
import '../providers/auto_accept_controller.dart';

class AutoAcceptScreen extends ConsumerStatefulWidget {
  const AutoAcceptScreen({super.key, required this.location});
  final Location location;

  @override
  ConsumerState<AutoAcceptScreen> createState() => _AutoAcceptScreenState();
}

class _AutoAcceptScreenState extends ConsumerState<AutoAcceptScreen> {
  late final AutoAcceptSettings _initial;
  late bool _regular;
  late bool _catering;

  bool get _dirty =>
      _regular != _initial.regular || _catering != _initial.catering;

  @override
  void initState() {
    super.initState();
    _initial = AutoAcceptSettings.fromJson(widget.location.servicePrefsJson);
    _regular = _initial.regular;
    _catering = _initial.catering;
  }

  @override
  Widget build(BuildContext context) {
    final AutoAcceptState operation = ref.watch(autoAcceptProvider);
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
        appBar: AppBar(title: const Text('Auto-Accept Orders')),
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
              'Paid orders can move directly to Confirmed without requiring manual acceptance.',
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              key: const Key('auto-accept-regular'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Automatically accept paid regular orders'),
              value: _regular,
              onChanged: operation.isBusy
                  ? null
                  : (bool value) => _requestChange(
                      kind: _AutoAcceptKind.regular,
                      value: value,
                    ),
            ),
            const Divider(height: 28),
            SwitchListTile(
              key: const Key('auto-accept-catering'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Automatically accept paid catering orders'),
              value: _catering,
              onChanged: operation.isBusy
                  ? null
                  : (bool value) => _requestChange(
                      kind: _AutoAcceptKind.catering,
                      value: value,
                    ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('auto-accept-save'),
              onPressed: operation.isBusy || !_dirty ? null : _save,
              child: Text(
                operation.isBusy ? 'Saving…' : 'Save auto-accept settings',
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

  Future<void> _requestChange({
    required _AutoAcceptKind kind,
    required bool value,
  }) async {
    final bool confirmed = await _confirmChange(kind: kind, value: value);
    if (!confirmed || !mounted) return;
    setState(() {
      if (kind == _AutoAcceptKind.regular) {
        _regular = value;
      } else {
        _catering = value;
      }
    });
  }

  Future<bool> _confirmChange({
    required _AutoAcceptKind kind,
    required bool value,
  }) async {
    final bool catering = kind == _AutoAcceptKind.catering;
    final String orderType = catering ? 'catering' : 'regular';
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(
              value
                  ? 'Enable automatic acceptance for $orderType orders?'
                  : 'Switch $orderType orders to manual acceptance?',
            ),
            content: Text(
              value
                  ? catering
                        ? 'Paid catering orders can move directly to Confirmed without manual review. This may commit the restaurant to new catering orders before staff reviews them.'
                        : 'Paid regular orders can move directly to Confirmed without manual review.'
                  : 'Paid $orderType orders processed after this change will remain Pending until staff accepts them.',
            ),
            actions: <Widget>[
              TextButton(
                key: Key('auto-accept-$orderType-confirm-cancel'),
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(value ? 'Keep manual' : 'Keep auto-accept'),
              ),
              FilledButton(
                key: Key('auto-accept-$orderType-confirm'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  value ? 'Enable auto-accept' : 'Use manual acceptance',
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _save() async {
    await ref
        .read(autoAcceptProvider.notifier)
        .save(
          locationId: widget.location.id,
          originalUpdatedAt: widget.location.updatedAt,
          originalRegular: _initial.regular,
          regular: _regular,
          originalCatering: _initial.catering,
          catering: _catering,
        );
    if (!mounted) return;
    final AutoAcceptState result = ref.read(autoAcceptProvider);
    if (result.phase == AutoAcceptPhase.success) {
      Navigator.pop(context);
    } else if (result.phase == AutoAcceptPhase.conflict) {
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
            result.message ?? 'Auto-accept settings could not be saved.',
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
          content: const Text('Your unsaved auto-accept changes will be lost.'),
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

enum _AutoAcceptKind { regular, catering }
