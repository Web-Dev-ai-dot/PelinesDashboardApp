import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/location.dart';
import '../providers/locations_providers.dart';
import '../providers/store_operations_controller.dart';

class StoreOperationsScreen extends ConsumerWidget {
  const StoreOperationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<StoreOperationState>(storeOperationsProvider, (
      StoreOperationState? previous,
      StoreOperationState next,
    ) {
      if (next.message == null || next.message == previous?.message) return;
      final bool failed = next.phase == StoreOperationPhase.error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next.message!),
          backgroundColor: failed ? Theme.of(context).colorScheme.error : null,
        ),
      );
    });

    final AsyncValue<Location?> current = ref.watch(currentLocationProvider);
    final StoreOperationState operation = ref.watch(storeOperationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Store Operations')),
      body: current.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error.toString(), textAlign: TextAlign.center),
          ),
        ),
        data: (Location? location) => location == null
            ? const Center(
                child: Text('Choose a location to manage store operations.'),
              )
            : _OperationsContent(location: location, operation: operation),
      ),
    );
  }
}

class _OperationsContent extends ConsumerWidget {
  const _OperationsContent({required this.location, required this.operation});

  final Location location;
  final StoreOperationState operation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool accepting = location.isAcceptingOrders;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(location.name, style: Theme.of(context).textTheme.headlineSmall),
        if (location.address?.trim().isNotEmpty ?? false) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            location.address!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Online Orders',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Semantics(
                  label: 'Accepting online orders for ${location.name}',
                  toggled: accepting,
                  child: SwitchListTile(
                    key: const Key('accepting-orders-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      accepting
                          ? 'Accepting online orders'
                          : 'Online orders paused',
                    ),
                    subtitle: Text(
                      accepting
                          ? 'Orders can be placed online.'
                          : 'New online orders are currently blocked.',
                    ),
                    value: accepting,
                    onChanged: operation.isBusy
                        ? null
                        : (bool requested) =>
                              _confirmChange(context, ref, location, requested),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'When disabled, this location will stop accepting new online orders for both regular and catering orders. Existing orders are not cancelled.',
                ),
                if (operation.isBusy) ...<Widget>[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(
                    key: Key('store-operation-progress'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    operation.phase == StoreOperationPhase.submitting
                        ? 'Saving change…'
                        : 'Checking the current server setting…',
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmChange(
    BuildContext context,
    WidgetRef ref,
    Location captured,
    bool requested,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          requested
              ? 'Start accepting online orders for ${captured.name}?'
              : 'Stop online orders for ${captured.name}?',
        ),
        content: Text(
          requested
              ? 'This location will be allowed to receive new online orders again. Business hours and other availability rules still apply.'
              : 'New regular and catering orders will be blocked for this location. Existing orders are not cancelled.',
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('accepting-orders-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(requested ? 'Keep closed' : 'Keep accepting'),
          ),
          FilledButton(
            key: const Key('accepting-orders-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(requested ? 'Start orders' : 'Stop orders'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final Location? current = ref.read(currentLocationProvider).value;
    if (current?.id != captured.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The selected location changed. Please confirm again.'),
        ),
      );
      return;
    }
    await ref
        .read(storeOperationsProvider.notifier)
        .setAcceptingOrders(
          locationId: captured.id,
          observedValue: captured.isAcceptingOrders,
          requestedValue: requested,
        );
  }
}
