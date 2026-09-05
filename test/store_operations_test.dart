import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/features/locations/data/location_selection_store.dart';
import 'package:pelines_admin_app/features/locations/data/locations_repository.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/presentation/store_operations_screen.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/locations/providers/store_operations_controller.dart';

void main() {
  for (final bool value in <bool>[false, true]) {
    test('repository PATCH sends only isAcceptingOrders=$value', () async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'));
      late RequestOptions captured;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                captured = options;
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: _locationJson(accepting: value),
                  ),
                );
              },
        ),
      );
      final ApiLocationsRepository repository = ApiLocationsRepository(
        ApiClient(dio: dio),
      );

      await repository.setAcceptingOrders('location-id', value);

      expect(captured.method, 'PATCH');
      expect(captured.path, 'locations/location-id');
      expect(captured.data, <String, dynamic>{'isAcceptingOrders': value});
      expect(
        (captured.data as Map<String, dynamic>).containsKey('isActive'),
        false,
      );
    });
  }

  test(
    'unchanged canonical value performs one PATCH and adopts final GET',
    () async {
      final Location initial = _location(accepting: true);
      final Location updated = _location(
        accepting: false,
        updatedAt: DateTime.utc(2026, 9, 5),
      );
      final _FakeLocationsRepository repository = _FakeLocationsRepository(
        locations: <Location>[initial],
        reads: <Location>[initial, updated],
        patchResult: updated,
      );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);

      await container
          .read(storeOperationsProvider.notifier)
          .setAcceptingOrders(
            locationId: initial.id,
            observedValue: true,
            requestedValue: false,
          );

      expect(repository.patchCalls, 1);
      expect(repository.readCalls, 2);
      expect(repository.patchBodies, <bool>[false]);
      expect(
        container.read(storeOperationsProvider).phase,
        StoreOperationPhase.success,
      );
      expect(
        container.read(currentLocationProvider).value?.isAcceptingOrders,
        false,
      );
      expect(
        container.read(currentLocationProvider).value?.updatedAt,
        updated.updatedAt,
      );
      expect(container.read(locationsProvider).value?.single.isActive, true);
      expect(await _MemoryStore.instance.readLocationId(), initial.id);
    },
  );

  test('canonical already requested is a successful no-op', () async {
    final Location initial = _location(accepting: true);
    final Location canonical = _location(accepting: false);
    final _FakeLocationsRepository repository = _FakeLocationsRepository(
      locations: <Location>[initial],
      reads: <Location>[canonical],
      patchResult: canonical,
    );
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);

    await container
        .read(storeOperationsProvider.notifier)
        .setAcceptingOrders(
          locationId: initial.id,
          observedValue: true,
          requestedValue: false,
        );

    expect(repository.patchCalls, 0);
    expect(
      container.read(storeOperationsProvider).phase,
      StoreOperationPhase.success,
    );
    expect(
      container.read(currentLocationProvider).value?.isAcceptingOrders,
      false,
    );
  });

  for (final bool reconciled in <bool>[true, false]) {
    test('timeout reconciles requested=$reconciled without retry', () async {
      final Location initial = _location(accepting: true);
      final Location finalValue = _location(accepting: !reconciled);
      final _FakeLocationsRepository repository = _FakeLocationsRepository(
        locations: <Location>[initial],
        reads: <Location>[initial, finalValue],
        patchResult: finalValue,
        patchError: _timeout(),
      );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);

      await container
          .read(storeOperationsProvider.notifier)
          .setAcceptingOrders(
            locationId: initial.id,
            observedValue: true,
            requestedValue: false,
          );

      expect(repository.patchCalls, 1);
      expect(repository.readCalls, 2);
      expect(
        container.read(storeOperationsProvider).phase,
        reconciled ? StoreOperationPhase.success : StoreOperationPhase.error,
      );
    });
  }

  test('double submission sends at most one PATCH', () async {
    final Location initial = _location(accepting: true);
    final Location updated = _location(accepting: false);
    final Completer<Location> patch = Completer<Location>();
    final _FakeLocationsRepository repository = _FakeLocationsRepository(
      locations: <Location>[initial],
      reads: <Location>[initial, updated],
      patchResult: updated,
      patchFuture: patch.future,
    );
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    final StoreOperationsController controller = container.read(
      storeOperationsProvider.notifier,
    );

    final Future<void> first = controller.setAcceptingOrders(
      locationId: initial.id,
      observedValue: true,
      requestedValue: false,
    );
    await Future<void>.delayed(Duration.zero);
    final Future<void> second = controller.setAcceptingOrders(
      locationId: initial.id,
      observedValue: true,
      requestedValue: false,
    );
    patch.complete(updated);
    await Future.wait(<Future<void>>[first, second]);
    expect(repository.patchCalls, 1);
  });

  testWidgets('tap requires named confirmation and cancel sends no PATCH', (
    WidgetTester tester,
  ) async {
    final Location initial = _location(accepting: true, name: 'Tualatin');
    final _FakeLocationsRepository repository = _FakeLocationsRepository(
      locations: <Location>[initial],
      reads: <Location>[initial],
      patchResult: initial,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationsRepositoryProvider.overrideWithValue(repository),
          locationSelectionStoreProvider.overrideWithValue(
            _MemoryStore.instance,
          ),
        ],
        child: const MaterialApp(home: StoreOperationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('accepting-orders-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Stop online orders for Tualatin?'), findsOneWidget);
    expect(repository.patchCalls, 0);
    await tester.tap(find.byKey(const Key('accepting-orders-cancel')));
    await tester.pumpAndSettle();
    expect(repository.patchCalls, 0);
  });

  testWidgets('confirm performs preflight, one PATCH, and final GET', (
    WidgetTester tester,
  ) async {
    final Location initial = _location(accepting: true, name: 'Tualatin');
    final Location updated = _location(
      accepting: false,
      name: 'Tualatin',
      updatedAt: DateTime.utc(2026, 9, 5),
    );
    final _FakeLocationsRepository repository = _FakeLocationsRepository(
      locations: <Location>[initial],
      reads: <Location>[initial, updated],
      patchResult: updated,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationsRepositoryProvider.overrideWithValue(repository),
          locationSelectionStoreProvider.overrideWithValue(
            _MemoryStore.instance,
          ),
        ],
        child: const MaterialApp(home: StoreOperationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('accepting-orders-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accepting-orders-confirm')));
    await tester.pumpAndSettle();

    expect(repository.readCalls, 2);
    expect(repository.patchCalls, 1);
    expect(repository.patchBodies, <bool>[false]);
    expect(find.text('Online orders paused'), findsOneWidget);
  });

  testWidgets('location change while dialog is open prevents PATCH', (
    WidgetTester tester,
  ) async {
    final Location first = _location(accepting: true, name: 'Tualatin');
    final Location second = _location(
      id: 'second-id',
      accepting: true,
      name: 'Troutdale',
    );
    final _FakeLocationsRepository repository = _FakeLocationsRepository(
      locations: <Location>[first, second],
      reads: <Location>[first],
      patchResult: first,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationsRepositoryProvider.overrideWithValue(repository),
          locationSelectionStoreProvider.overrideWithValue(
            _MemoryStore.instance,
          ),
        ],
        child: const MaterialApp(home: StoreOperationsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(StoreOperationsScreen)),
    );

    await tester.tap(find.byKey(const Key('accepting-orders-switch')));
    await tester.pumpAndSettle();
    await container.read(currentLocationProvider.notifier).select(second);
    await tester.tap(find.byKey(const Key('accepting-orders-confirm')));
    await tester.pumpAndSettle();

    expect(repository.patchCalls, 0);
    expect(container.read(currentLocationProvider).value?.id, second.id);
  });
}

ProviderContainer _container(_FakeLocationsRepository repository) =>
    ProviderContainer(
      overrides: [
        locationsRepositoryProvider.overrideWithValue(repository),
        locationSelectionStoreProvider.overrideWithValue(_MemoryStore.instance),
      ],
    );

Location _location({
  String id = 'location-id',
  required bool accepting,
  String name = 'Tualatin',
  DateTime? updatedAt,
}) => Location(
  id: id,
  name: name,
  slug: 'tualatin',
  address: '123 Example St',
  isActive: true,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  isAcceptingOrders: accepting,
  createdAt: DateTime.utc(2026),
  updatedAt: updatedAt ?? DateTime.utc(2026),
);

Map<String, dynamic> _locationJson({required bool accepting}) =>
    <String, dynamic>{
      'id': 'location-id',
      'name': 'Tualatin',
      'slug': 'tualatin',
      'address': '123 Example St',
      'phone': null,
      'hoursJson': null,
      'isActive': true,
      'deliveryFeeCents': 0,
      'deliveryMinimumCents': 0,
      'isAcceptingOrders': accepting,
      'servicePrefsJson': null,
      'hoursExtrasJson': null,
      'cateringDeliveryJson': null,
      'regularDeliveryJson': null,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-09-05T00:00:00.000Z',
    };

ApiException _timeout() => ApiException(
  message: 'The Pelines server timed out.',
  cause: DioException(
    requestOptions: RequestOptions(path: 'locations/location-id'),
    type: DioExceptionType.receiveTimeout,
  ),
);

class _FakeLocationsRepository implements LocationsRepository {
  _FakeLocationsRepository({
    required this.locations,
    required this.reads,
    required this.patchResult,
    this.patchFuture,
    this.patchError,
  });

  final List<Location> locations;
  final List<Location> reads;
  final Location patchResult;
  final Future<Location>? patchFuture;
  final Object? patchError;
  int readCalls = 0;
  int patchCalls = 0;
  final List<bool> patchBodies = <bool>[];

  @override
  Future<List<Location>> getLocations() async => locations;

  @override
  Future<Location> getLocation(String locationId) async => reads[readCalls++];

  @override
  Future<Location> setAcceptingOrders(
    String locationId,
    bool isAcceptingOrders,
  ) async {
    patchCalls++;
    patchBodies.add(isAcceptingOrders);
    if (patchError != null) throw patchError!;
    if (patchFuture != null) return patchFuture!;
    return patchResult;
  }
}

class _MemoryStore implements LocationSelectionStore {
  static final _MemoryStore instance = _MemoryStore();
  String? value;

  @override
  Future<void> clearLocationId() async => value = null;
  @override
  Future<String?> readLocationId() async => value;
  @override
  Future<void> writeLocationId(String id) async => value = id;
}
