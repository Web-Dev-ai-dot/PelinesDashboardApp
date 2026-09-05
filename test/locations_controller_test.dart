import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/locations/data/location_selection_store.dart';
import 'package:pelines_admin_app/features/locations/data/locations_repository.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/models/temporary_closure.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';

void main() {
  test('available locations supports an empty backend list', () async {
    final ProviderContainer container = _container(<Location>[]);
    addTearDown(container.dispose);

    expect(await container.read(locationsProvider.future), isEmpty);
    expect(await container.read(currentLocationProvider.future), isNull);
  });

  test('restores a valid saved active location id', () async {
    final Location first = _location('first');
    final Location second = _location('second');
    final _MemoryStore store = _MemoryStore(second.id);
    final ProviderContainer container = _container(<Location>[
      first,
      second,
    ], store: store);
    addTearDown(container.dispose);

    expect(await container.read(currentLocationProvider.future), same(second));
    expect(store.value, second.id);
  });

  test(
    'clears a saved id that no longer exists and requires selection',
    () async {
      final _MemoryStore store = _MemoryStore('missing');
      final ProviderContainer container = _container(<Location>[
        _location('first'),
        _location('second'),
      ], store: store);
      addTearDown(container.dispose);

      expect(await container.read(currentLocationProvider.future), isNull);
      expect(store.value, isNull);
    },
  );

  test('does not restore an inactive saved location', () async {
    final Location inactive = _location('inactive', isActive: false);
    final _MemoryStore store = _MemoryStore(inactive.id);
    final ProviderContainer container = _container(<Location>[
      inactive,
      _location('first'),
      _location('second'),
    ], store: store);
    addTearDown(container.dispose);

    expect(await container.read(currentLocationProvider.future), isNull);
    expect(store.value, isNull);
  });

  test('automatically selects and persists the only active location', () async {
    final Location active = _location('active');
    final _MemoryStore store = _MemoryStore();
    final ProviderContainer container = _container(<Location>[
      active,
      _location('inactive', isActive: false),
    ], store: store);
    addTearDown(container.dispose);

    expect(await container.read(currentLocationProvider.future), same(active));
    expect(store.value, active.id);
  });

  test('selects and persists an available active location', () async {
    final Location first = _location('first');
    final Location second = _location('second');
    final _MemoryStore store = _MemoryStore();
    final ProviderContainer container = _container(<Location>[
      first,
      second,
    ], store: store);
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);

    await container.read(currentLocationProvider.notifier).select(second);

    expect(container.read(currentLocationProvider).value, same(second));
    expect(store.value, second.id);
  });
}

ProviderContainer _container(List<Location> locations, {_MemoryStore? store}) {
  return ProviderContainer(
    overrides: [
      locationsRepositoryProvider.overrideWithValue(_FakeRepository(locations)),
      locationSelectionStoreProvider.overrideWithValue(store ?? _MemoryStore()),
    ],
  );
}

Location _location(String name, {bool isActive = true}) => Location(
  id: '$name-id',
  name: name,
  slug: name,
  isActive: isActive,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  isAcceptingOrders: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _FakeRepository implements LocationsRepository {
  _FakeRepository(this.locations);

  final List<Location> locations;

  @override
  Future<List<Location>> getLocations() async => locations;

  @override
  Future<Location> getLocation(String locationId) async =>
      locations.singleWhere((Location location) => location.id == locationId);

  @override
  Future<Location> setAcceptingOrders(
    String locationId,
    bool isAcceptingOrders,
  ) => throw UnimplementedError();

  @override
  Future<Location> saveClosure({
    required String locationId,
    required DateTime originalUpdatedAt,
    required TemporaryClosure closure,
    required bool isNew,
  }) => throw UnimplementedError();
}

class _MemoryStore implements LocationSelectionStore {
  _MemoryStore([this.value]);

  String? value;

  @override
  Future<void> clearLocationId() async => value = null;

  @override
  Future<String?> readLocationId() async => value;

  @override
  Future<void> writeLocationId(String id) async => value = id;
}
