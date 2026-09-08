import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/pelines_tokens.dart';
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
        title: Text(
          'Pelines Admin',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontFamily: PelinesTypography.bodyFamily,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: <Widget>[
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(
              Icons.menu_rounded,
              color: PelinesColors.brandPrimary,
            ),
            onSelected: context.push,
            color: PelinesColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PelinesRadius.card),
              side: const BorderSide(color: PelinesColors.border),
            ),
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: '/app/menu',
                    child: _NavigationItem(
                      icon: Icons.restaurant_menu_outlined,
                      label: 'Menu',
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: '/app/store-operations',
                    child: _NavigationItem(
                      icon: Icons.storefront_outlined,
                      label: 'Store Operations',
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: '/app/promotions',
                    child: _NavigationItem(
                      icon: Icons.local_offer_outlined,
                      label: 'Promotions',
                    ),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: '/app/printing',
                    child: _NavigationItem(
                      icon: Icons.print_outlined,
                      label: 'Printer Settings',
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: '/app/account',
                    child: _NavigationItem(
                      icon: Icons.person_outline,
                      label: 'Account',
                    ),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: '/app/orders/calendar',
                    child: _NavigationItem(
                      icon: Icons.calendar_month_outlined,
                      label: 'Calendar',
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: '/app/orders/completed',
                    child: _NavigationItem(
                      icon: Icons.check_circle_outline,
                      label: 'Completed Orders',
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: '/app/orders/cancelled',
                    child: _NavigationItem(
                      icon: Icons.cancel_outlined,
                      label: 'Cancelled Orders',
                    ),
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

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(icon, color: PelinesColors.brandPrimary),
      const SizedBox(width: PelinesSpacing.sm),
      Text(
        label,
        style: const TextStyle(
          fontFamily: PelinesTypography.bodyFamily,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
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
      padding: const EdgeInsets.all(PelinesSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Choose a location',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: PelinesSpacing.xs),
          Text(
            'Your selection will be used throughout the admin app.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: PelinesSpacing.md),
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
      padding: const EdgeInsets.symmetric(vertical: PelinesSpacing.xs),
      itemCount: locations.length,
      itemBuilder: (BuildContext context, int index) {
        final Location location = locations[index];
        return ListTile(
          enabled: location.isActive,
          selected: selectedId == location.id,
          selectedTileColor: PelinesColors.brandPrimarySoft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PelinesRadius.control),
          ),
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
              ? const Icon(
                  Icons.check_circle,
                  color: PelinesColors.brandPrimary,
                )
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
