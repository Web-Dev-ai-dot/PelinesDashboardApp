import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../locations/models/location.dart';
import '../../locations/presentation/pelines_location_selector.dart';
import '../../locations/presentation/pelines_location_context.dart';
import '../../locations/providers/locations_providers.dart';
import '../../orders/presentation/today_orders_view.dart';
import '../../orders/models/orders_date_filter.dart';

class AdminHomeScreen extends ConsumerStatefulWidget {
  const AdminHomeScreen({this.upcoming = false, super.key});
  final bool upcoming;

  @override
  ConsumerState<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends ConsumerState<AdminHomeScreen> {
  final _ordersKey = GlobalKey<TodayOrdersViewState>();
  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Location>> locations = ref.watch(locationsProvider);
    final AsyncValue<Location?> currentLocation = ref.watch(
      currentLocationProvider,
    );

    return Scaffold(
      appBar: AdminAppBar(
        actions: [
          if (widget.upcoming)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: OutlinedButton.icon(
                key: const Key('orders-header-refresh'),
                onPressed: currentLocation.value == null
                    ? null
                    : () => _ordersKey.currentState?.refresh(),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(tr(context, 'Refresh')),
              ),
            )
          else
            IconButton(
              key: const Key('orders-header-refresh'),
              tooltip: tr(context, 'Refresh orders'),
              onPressed: currentLocation.value == null
                  ? null
                  : () => _ordersKey.currentState?.refresh(),
              icon: const Icon(Icons.refresh),
            ),
        ],
        title: Text(
          tr(context, widget.upcoming ? 'Orders' : 'To Do'),
          style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
        ),
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
                : _HomeContent(
                    location: selected,
                    ordersKey: _ordersKey,
                    upcoming: widget.upcoming,
                  ),
          );
        },
      ),
    );
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent({
    required this.location,
    required this.ordersKey,
    required this.upcoming,
  });
  final bool upcoming;
  final GlobalKey<TodayOrdersViewState> ordersKey;
  final Location location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: PelinesLocationContext(location: location),
            ),
            // Keep Orders' existing bounded viewport; long context scrolls above it
            // instead of squeezing its filters and list at large text scales.
            SizedBox(
              height: constraints.maxHeight,
              child: TodayOrdersView(
                webOrders: upcoming,
                key: ordersKey,
                location: location,
                initialDateFilter: upcoming
                    ? OrdersDateFilter.upcoming
                    : OrdersDateFilter.today,
                onChangeLocation: () => showPelinesLocationPicker(context, ref),
                showLocationSelector: false,
              ),
            ),
          ],
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
            tr(context, 'Choose a location'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: PelinesSpacing.xs),
          Text(
            tr(
              context,
              'Your selection will be used throughout the admin app.',
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: PelinesSpacing.md),
          Expanded(
            child: PelinesLocationList(
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

class _EmptyLocations extends StatelessWidget {
  const _EmptyLocations();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(tr(context, 'No locations are available.')),
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
            FilledButton(
              onPressed: onRetry,
              child: Text(tr(context, 'Try again')),
            ),
          ],
        ),
      ),
    );
  }
}
