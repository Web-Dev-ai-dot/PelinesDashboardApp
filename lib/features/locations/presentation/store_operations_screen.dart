import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/location.dart';
import '../models/temporary_closure.dart';
import '../models/business_hours.dart';
import '../models/regular_delivery.dart';
import '../models/catering_delivery.dart';
import '../../orders/presentation/order_ui_helpers.dart';
import 'business_hours_screen.dart';
import 'regular_delivery_screen.dart';
import 'catering_delivery_screen.dart';
import 'closure_form_screen.dart';
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
        const SizedBox(height: 20),
        _TemporaryClosuresCard(location: location),
        const SizedBox(height: 20),
        _BusinessHoursCard(location: location),
        const SizedBox(height: 20),
        _RegularDeliveryCard(location: location),
        const SizedBox(height: 20),
        _CateringDeliveryCard(location: location),
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

class _CateringDeliveryCard extends StatelessWidget {
  const _CateringDeliveryCard({required this.location});
  final Location location;

  @override
  Widget build(BuildContext context) {
    late final CateringDeliverySettings settings;
    try {
      settings = CateringDeliverySettings.fromJson(
        location.cateringDeliveryJson,
      );
    } on UnsupportedCateringDeliveryFormat catch (error) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Catering Delivery', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(error.toString(), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      );
    }
    return Card(
      key: const Key('catering-delivery-card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Catering Delivery', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(settings.enabled ? 'Enabled' : 'Disabled'),
            if (settings.usesDefault) const Text('Using default setting'),
            const SizedBox(height: 12),
            Text('Delivery fee: ${money(location.deliveryFeeCents)}'),
            Text('Minimum order: ${money(location.deliveryMinimumCents)}'),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('edit-catering-delivery'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CateringDeliveryScreen(location: location),
                ),
              ),
              child: const Text('Edit catering delivery'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegularDeliveryCard extends StatelessWidget {
  const _RegularDeliveryCard({required this.location});
  final Location location;
  @override
  Widget build(BuildContext context) {
    late final RegularDeliverySettings settings;
    try {
      settings = RegularDeliverySettings.fromJson(location.regularDeliveryJson);
    } on UnsupportedRegularDeliveryFormat catch (error) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Regular Delivery',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                error.toString(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Regular Delivery',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(settings.enabled ? 'Enabled' : 'Disabled'),
            const SizedBox(height: 12),
            Text('Delivery fee: ${money(settings.feeCents)}'),
            Text('Minimum order: ${money(settings.minimumCents)}'),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('edit-regular-delivery'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => RegularDeliveryScreen(location: location),
                ),
              ),
              child: const Text('Edit regular delivery'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessHoursCard extends StatelessWidget {
  const _BusinessHoursCard({required this.location});
  final Location location;

  @override
  Widget build(BuildContext context) {
    final BusinessHoursSchedule? schedule = location.hoursJson == null
        ? null
        : BusinessHoursSchedule.fromJson(location.hoursJson!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Business Hours',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Business hours affect regular online ordering. Catering availability is handled separately.',
            ),
            const SizedBox(height: 12),
            if (schedule == null)
              const Text('Business hours are not configured.')
            else
              for (int index = 0; index < 7; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 92,
                        child: Text(businessDayLabels[index].substring(0, 3)),
                      ),
                      Expanded(
                        child: Text(_summary(context, schedule.days[index])),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('edit-business-hours'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => BusinessHoursScreen(location: location),
                ),
              ),
              child: const Text('Edit business hours'),
            ),
          ],
        ),
      ),
    );
  }

  String _summary(BuildContext context, BusinessDayHours day) {
    if (day.closed) return 'Closed';
    String display(String value) {
      final List<String> parts = value.split(':');
      return TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ).format(context);
    }

    return '${display(day.open)} – ${display(day.close)}';
  }
}

class _TemporaryClosuresCard extends StatelessWidget {
  const _TemporaryClosuresCard({required this.location});
  final Location location;

  @override
  Widget build(BuildContext context) {
    late final List<TemporaryClosure> closures;
    try {
      closures = closuresFromExtras(location.hoursExtrasJson).toList()
        ..sort(
          (TemporaryClosure a, TemporaryClosure b) =>
              a.start.compareTo(b.start),
        );
    } on UnsupportedClosureFormat catch (error) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Temporary Closures',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                error.toString(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Temporary Closures',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Temporary closures affect regular online ordering. Catering availability is handled separately by the current backend.',
            ),
            const SizedBox(height: 12),
            if (closures.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No temporary closures.'),
              )
            else
              for (final TemporaryClosure closure in closures)
                ListTile(
                  key: Key('closure-${closure.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    closure.reason.isEmpty
                        ? 'Temporary closure'
                        : closure.reason,
                  ),
                  subtitle: Text(
                    '${_dateRange(closure)}\n${closure.active ? 'Active' : 'Inactive'}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openForm(context, closure),
                ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('add-closure'),
              onPressed: () => _openForm(context, null),
              icon: const Icon(Icons.add),
              label: const Text('Add closure'),
            ),
          ],
        ),
      ),
    );
  }

  String _dateRange(TemporaryClosure closure) {
    final DateFormat format = DateFormat.yMMMd();
    final String start = format.format(parseCalendarDate(closure.start)!);
    final String end = format.format(parseCalendarDate(closure.end)!);
    return closure.start == closure.end ? start : '$start – $end';
  }

  Future<void> _openForm(BuildContext context, TemporaryClosure? closure) =>
      Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              ClosureFormScreen(location: location, closure: closure),
        ),
      );
}
