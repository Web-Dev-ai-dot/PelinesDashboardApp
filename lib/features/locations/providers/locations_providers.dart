import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../data/location_selection_store.dart';
import '../data/locations_repository.dart';
import '../models/location.dart';

final locationsRepositoryProvider = Provider<LocationsRepository>((Ref ref) {
  return ApiLocationsRepository(ref.watch(apiClientProvider));
});

final locationSelectionStoreProvider = Provider<LocationSelectionStore>((
  Ref ref,
) {
  return SharedPreferencesLocationSelectionStore();
});

final locationsProvider =
    AsyncNotifierProvider<LocationsController, List<Location>>(
      LocationsController.new,
    );

final currentLocationProvider =
    AsyncNotifierProvider<CurrentLocationController, Location?>(
      CurrentLocationController.new,
    );

class LocationsController extends AsyncNotifier<List<Location>> {
  @override
  Future<List<Location>> build() {
    return ref.watch(locationsRepositoryProvider).getLocations();
  }

  Future<void> retry() async {
    state = const AsyncLoading<List<Location>>();
    state = await AsyncValue.guard(
      ref.read(locationsRepositoryProvider).getLocations,
    );
  }
}

class CurrentLocationController extends AsyncNotifier<Location?> {
  late LocationSelectionStore _store;

  @override
  Future<Location?> build() async {
    _store = ref.watch(locationSelectionStoreProvider);
    final List<Location> locations = await ref.watch(locationsProvider.future);
    final String? savedId = await _store.readLocationId();

    if (savedId != null) {
      for (final Location location in locations) {
        if (location.id == savedId && location.isActive) return location;
      }
      await _store.clearLocationId();
    }

    final List<Location> active = locations
        .where((Location location) => location.isActive)
        .toList(growable: false);
    if (active.length == 1) {
      await _store.writeLocationId(active.single.id);
      return active.single;
    }
    return null;
  }

  Future<void> select(Location location) async {
    if (!location.isActive) {
      throw ArgumentError.value(location.id, 'location', 'Must be active');
    }
    final List<Location> locations = await ref.read(locationsProvider.future);
    final bool exists = locations.any(
      (Location available) => available.id == location.id,
    );
    if (!exists) {
      throw ArgumentError.value(location.id, 'location', 'Must be available');
    }

    await _store.writeLocationId(location.id);
    state = AsyncData<Location?>(location);
  }
}
