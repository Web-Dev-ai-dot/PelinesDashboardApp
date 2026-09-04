import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/providers/auth_providers.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../../orders/presentation/today_orders_view.dart';

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Location>> locations = ref.watch(locationsProvider);
    final AsyncValue<Location?> currentLocation = ref.watch(
      currentLocationProvider,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pelines Admin'),
        actions: <Widget>[
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onSelected: context.push,
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: '/app/orders/completed',
                    child: Text('Completed Orders'),
                  ),
                  PopupMenuItem<String>(
                    value: '/app/orders/cancelled',
                    child: Text('Cancelled Orders'),
                  ),
                ],
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: locations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => _LocationsError(
          message: error.toString(),
          onRetry: () {
            ref.invalidate(currentLocationProvider);
            ref.read(locationsProvider.notifier).retry();
          },
        ),
        data: (List<Location> available) {
          if (available.isEmpty) return const _EmptyLocations();
          return currentLocation.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object error, StackTrace stackTrace) => _LocationsError(
              message: error.toString(),
              onRetry: () => ref.invalidate(currentLocationProvider),
            ),
            data: (Location? selected) => selected == null
                ? _LocationPicker(locations: available)
                : _HomeContent(location: selected),
          );
        },
      ),
    );
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent({required this.location});
  final Location location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TodayOrdersView(
      location: location,
      onChangeLocation: () => _showLocationPicker(context, ref),
    );
  }

  Future<void> _showLocationPicker(BuildContext context, WidgetRef ref) async {
    final List<Location>? locations = ref.read(locationsProvider).value;
    if (locations == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => SafeArea(
        child: _LocationList(
          locations: locations,
          selectedId: location.id,
          onSelected: (Location next) async {
            await ref.read(currentLocationProvider.notifier).select(next);
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ),
    );
  }
}

class _LocationPicker extends ConsumerWidget {
  const _LocationPicker({required this.locations});

  final List<Location> locations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Choose a location',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Your selection will be used throughout the admin app.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _LocationList(
              locations: locations,
              onSelected: (Location location) =>
                  ref.read(currentLocationProvider.notifier).select(location),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationList extends StatelessWidget {
  const _LocationList({
    required this.locations,
    required this.onSelected,
    this.selectedId,
  });

  final List<Location> locations;
  final String? selectedId;
  final Future<void> Function(Location) onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: locations.length,
      itemBuilder: (BuildContext context, int index) {
        final Location location = locations[index];
        return ListTile(
          enabled: location.isActive,
          leading: Icon(
            location.isActive
                ? Icons.storefront_outlined
                : Icons.store_outlined,
          ),
          title: Text(location.name),
          subtitle: Text(
            <String>[
              if (location.address != null) location.address!,
              if (!location.isActive) 'Inactive',
            ].join('\n'),
          ),
          trailing: selectedId == location.id
              ? const Icon(Icons.check_circle)
              : null,
          onTap: location.isActive ? () => onSelected(location) : null,
        );
      },
    );
  }
}

class _EmptyLocations extends StatelessWidget {
  const _EmptyLocations();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text('No locations are available.'),
    ),
  );
}

class _LocationsError extends StatelessWidget {
  const _LocationsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
