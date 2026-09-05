import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/locations/data/location_selection_store.dart';
import 'package:pelines_admin_app/features/locations/data/locations_repository.dart';
import 'package:pelines_admin_app/features/locations/models/catering_delivery.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/presentation/catering_delivery_screen.dart';
import 'package:pelines_admin_app/features/locations/presentation/store_operations_screen.dart';
import 'package:pelines_admin_app/features/locations/providers/catering_delivery_controller.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';

void main() {
  group('effective enabled semantics', () {
    for (final ({
          Map<String, dynamic>? json,
          CateringDeliveryEnabledState state,
        })
        fixture
        in <({Map<String, dynamic>? json, CateringDeliveryEnabledState state})>[
          (json: null, state: CateringDeliveryEnabledState.defaultEnabled),
          (
            json: <String, dynamic>{},
            state: CateringDeliveryEnabledState.defaultEnabled,
          ),
          (
            json: <String, dynamic>{'enabled': null},
            state: CateringDeliveryEnabledState.defaultEnabled,
          ),
          (
            json: <String, dynamic>{'enabled': true},
            state: CateringDeliveryEnabledState.explicitEnabled,
          ),
          (
            json: <String, dynamic>{'enabled': false},
            state: CateringDeliveryEnabledState.explicitDisabled,
          ),
        ]) {
      test('${fixture.json} maps to ${fixture.state}', () {
        final CateringDeliverySettings settings =
            CateringDeliverySettings.fromJson(fixture.json);
        expect(settings.enabledState, fixture.state);
        expect(
          settings.enabled,
          fixture.state != CateringDeliveryEnabledState.explicitDisabled,
        );
      });
    }

    test('incompatible enabled is not editable', () {
      expect(
        () => CateringDeliverySettings.fromJson(<String, dynamic>{
          'enabled': 'yes',
        }),
        throwsA(isA<UnsupportedCateringDeliveryFormat>()),
      );
    });
  });

  test('default-enabled no-op sends no PATCH', () async {
    final _Harness harness = _Harness(catering: null, fee: 500);
    await harness.repository.saveCateringDeliverySettings(
      locationId: 'location-id',
      originalUpdatedAt: _updatedAt,
      originalEnabled: true,
      enabled: true,
      originalFeeCents: 500,
      feeCents: 500,
    );
    expect(harness.patchCalls, 0);
  });

  test('default-enabled fee-only PATCH omits JSON and minimum', () async {
    final _Harness harness = _Harness(catering: null, fee: 400);
    await harness.repository.saveCateringDeliverySettings(
      locationId: 'location-id',
      originalUpdatedAt: _updatedAt,
      originalEnabled: true,
      enabled: true,
      originalFeeCents: 400,
      feeCents: 550,
    );
    expect(harness.patchBody, <String, dynamic>{'deliveryFeeCents': 550});
  });

  test('default-enabled disable preserves unknown keys', () async {
    final _Harness harness = _Harness(
      catering: <String, dynamic>{
        'enabled': null,
        'label': 'Delivery',
        'futureField': <String, dynamic>{'x': 1},
      },
      fee: 500,
    );
    await harness.repository.saveCateringDeliverySettings(
      locationId: 'location-id',
      originalUpdatedAt: _updatedAt,
      originalEnabled: true,
      enabled: false,
      originalFeeCents: 500,
      feeCents: 500,
    );
    expect(harness.patchBody, <String, dynamic>{
      'cateringDeliveryJson': <String, dynamic>{
        'enabled': false,
        'label': 'Delivery',
        'futureField': <String, dynamic>{'x': 1},
      },
    });
  });

  test(
    'explicit false to true plus fee uses one minimal atomic PATCH',
    () async {
      final _Harness harness = _Harness(
        catering: <String, dynamic>{'enabled': false, 'label': 'Keep'},
        fee: 500,
      );
      await harness.repository.saveCateringDeliverySettings(
        locationId: 'location-id',
        originalUpdatedAt: _updatedAt,
        originalEnabled: false,
        enabled: true,
        originalFeeCents: 500,
        feeCents: 600,
      );
      expect(harness.patchCalls, 1);
      expect(harness.patchBody, <String, dynamic>{
        'cateringDeliveryJson': <String, dynamic>{
          'enabled': true,
          'label': 'Keep',
        },
        'deliveryFeeCents': 600,
      });
      expect(harness.patchBody!.containsKey('deliveryMinimumCents'), false);
    },
  );

  test('conflict and malformed canonical settings never PATCH', () async {
    final _Harness conflict = _Harness(
      catering: null,
      fee: 500,
      updatedAt: DateTime.utc(2026, 9, 6),
    );
    await expectLater(
      conflict.repository.saveCateringDeliverySettings(
        locationId: 'location-id',
        originalUpdatedAt: _updatedAt,
        originalEnabled: true,
        enabled: false,
        originalFeeCents: 500,
        feeCents: 500,
      ),
      throwsA(isA<LocationSettingsConflict>()),
    );
    expect(conflict.patchCalls, 0);

    final _Harness malformed = _Harness(
      catering: <String, dynamic>{'enabled': 1},
      fee: 500,
    );
    await expectLater(
      malformed.repository.saveCateringDeliverySettings(
        locationId: 'location-id',
        originalUpdatedAt: _updatedAt,
        originalEnabled: true,
        enabled: false,
        originalFeeCents: 500,
        feeCents: 500,
      ),
      throwsA(isA<UnsupportedCateringDeliveryFormat>()),
    );
    expect(malformed.patchCalls, 0);
  });

  testWidgets('default UI, minimum read-only, and dirty reversal are safe', (
    WidgetTester tester,
  ) async {
    final Location location = Location.fromJson(
      _locationJson(catering: null, fee: 500),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: CateringDeliveryScreen(location: location)),
      ),
    );
    expect(find.text('Using default setting'), findsOneWidget);
    expect(find.text(r'$150.00'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('catering-delivery-save')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('catering-delivery-enabled')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('catering-delivery-enabled')));
    await tester.pump();
    expect(find.text('Using default setting'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('catering-delivery-save')))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'Store Operations summary shows effective default state and amounts',
    (WidgetTester tester) async {
      final Location initial = Location.fromJson(
        _locationJson(catering: null, fee: 500),
      );
      final _ControllerRepository repository = _ControllerRepository(
        initial: initial,
        finalLocation: initial,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationsRepositoryProvider.overrideWithValue(repository),
            locationSelectionStoreProvider.overrideWithValue(_MemoryStore()),
          ],
          child: const MaterialApp(home: StoreOperationsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('catering-delivery-card')),
        400,
      );
      expect(find.text('Catering Delivery'), findsOneWidget);
      expect(find.text('Using default setting'), findsOneWidget);
      expect(find.text(r'Delivery fee: $5.00'), findsOneWidget);
      expect(find.text(r'Minimum order: $150.00'), findsOneWidget);
    },
  );

  testWidgets('disable requires confirmation and cancellation sends nothing', (
    WidgetTester tester,
  ) async {
    final Location location = Location.fromJson(
      _locationJson(catering: null, fee: 500),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: CateringDeliveryScreen(location: location)),
      ),
    );
    await tester.tap(find.byKey(const Key('catering-delivery-enabled')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('catering-delivery-save')));
    await tester.pumpAndSettle();
    expect(
      find.text('Disable catering delivery for Tualatin?'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('catering-delivery-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(CateringDeliveryScreen), findsOneWidget);
  });

  for (final bool applied in <bool>[true, false]) {
    test(
      'timeout ${applied ? 'applied' : 'not applied'} reconciles without retry',
      () async {
        final Location initial = Location.fromJson(
          _locationJson(catering: null, fee: 500),
        );
        final Location finalLocation = Location.fromJson(
          _locationJson(
            catering: applied ? <String, dynamic>{'enabled': false} : null,
            fee: applied ? 600 : 500,
          ),
        );
        final _ControllerRepository repository = _ControllerRepository(
          initial: initial,
          finalLocation: finalLocation,
          error: _timeout(),
        );
        final ProviderContainer container = _container(repository);
        addTearDown(container.dispose);
        await container.read(currentLocationProvider.future);

        await container
            .read(cateringDeliveryProvider.notifier)
            .save(
              locationId: initial.id,
              originalUpdatedAt: initial.updatedAt,
              originalEnabled: true,
              enabled: false,
              originalFeeCents: 500,
              feeCents: 600,
              originalMinimumCents: 15000,
            );

        expect(repository.saveCalls, 1);
        expect(repository.readCalls, 1);
        expect(
          container.read(cateringDeliveryProvider).phase,
          applied ? CateringDeliveryPhase.success : CateringDeliveryPhase.error,
        );
      },
    );
  }

  test('location context change prevents save', () async {
    final Location initial = Location.fromJson(
      _locationJson(catering: null, fee: 500),
    );
    final Location other = Location.fromJson(<String, dynamic>{
      ..._locationJson(catering: null, fee: 500),
      'id': 'other-id',
      'name': 'Troutdale',
    });
    final _ControllerRepository repository = _ControllerRepository(
      initial: initial,
      finalLocation: initial,
      locations: <Location>[initial, other],
    );
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    await container.read(currentLocationProvider.notifier).select(other);

    await container
        .read(cateringDeliveryProvider.notifier)
        .save(
          locationId: initial.id,
          originalUpdatedAt: initial.updatedAt,
          originalEnabled: true,
          enabled: false,
          originalFeeCents: 500,
          feeCents: 500,
          originalMinimumCents: 15000,
        );

    expect(repository.saveCalls, 0);
    expect(
      container.read(cateringDeliveryProvider).phase,
      CateringDeliveryPhase.error,
    );
  });
}

final DateTime _updatedAt = DateTime.utc(2026, 9, 5);

class _Harness {
  _Harness({
    required Map<String, dynamic>? catering,
    required int fee,
    DateTime? updatedAt,
  }) {
    final Map<String, dynamic> location = _locationJson(
      catering: catering,
      fee: fee,
      updatedAt: updatedAt,
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          if (options.method == 'PATCH') {
            patchCalls++;
            patchBody = Map<String, dynamic>.from(
              options.data as Map<String, dynamic>,
            );
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: location,
            ),
          );
        },
      ),
    );
    repository = ApiLocationsRepository(ApiClient(dio: dio));
  }

  late final ApiLocationsRepository repository;
  int patchCalls = 0;
  Map<String, dynamic>? patchBody;
}

ProviderContainer _container(_ControllerRepository repository) =>
    ProviderContainer(
      overrides: [
        locationsRepositoryProvider.overrideWithValue(repository),
        locationSelectionStoreProvider.overrideWithValue(_MemoryStore()),
      ],
    );

class _ControllerRepository implements LocationsRepository {
  _ControllerRepository({
    required this.initial,
    required this.finalLocation,
    this.error,
    List<Location>? locations,
  }) : locations = locations ?? <Location>[initial];

  final Location initial;
  final Location finalLocation;
  final Object? error;
  final List<Location> locations;
  int saveCalls = 0;
  int readCalls = 0;

  @override
  Future<List<Location>> getLocations() async => locations;
  @override
  Future<Location> getLocation(String locationId) async {
    readCalls++;
    return finalLocation;
  }

  @override
  Future<Location> saveCateringDeliverySettings({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool originalEnabled,
    required bool enabled,
    required int originalFeeCents,
    required int feeCents,
  }) async {
    saveCalls++;
    if (error != null) throw error!;
    return finalLocation;
  }

  @override
  Future<Location> setAcceptingOrders(
    String locationId,
    bool isAcceptingOrders,
  ) => throw UnimplementedError();
  @override
  Future<Location> saveClosure({
    required String locationId,
    required DateTime originalUpdatedAt,
    required dynamic closure,
    required bool isNew,
  }) => throw UnimplementedError();
  @override
  Future<Location> saveBusinessHours({
    required String locationId,
    required DateTime originalUpdatedAt,
    required dynamic schedule,
  }) => throw UnimplementedError();
  @override
  Future<Location> saveRegularDeliverySettings({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool enabled,
    required int feeCents,
  }) => throw UnimplementedError();
}

class _MemoryStore implements LocationSelectionStore {
  String? value;
  @override
  Future<void> clearLocationId() async => value = null;
  @override
  Future<String?> readLocationId() async => value;
  @override
  Future<void> writeLocationId(String id) async => value = id;
}

ApiException _timeout() => ApiException(
  message: 'The Pelines server timed out.',
  cause: DioException(
    requestOptions: RequestOptions(path: 'locations/location-id'),
    type: DioExceptionType.receiveTimeout,
  ),
);

Map<String, dynamic> _locationJson({
  required Map<String, dynamic>? catering,
  required int fee,
  DateTime? updatedAt,
}) => <String, dynamic>{
  'id': 'location-id',
  'name': 'Tualatin',
  'slug': 'tualatin',
  'address': '123 Example St',
  'phone': null,
  'hoursJson': null,
  'isActive': true,
  'deliveryFeeCents': fee,
  'deliveryMinimumCents': 15000,
  'isAcceptingOrders': true,
  'servicePrefsJson': null,
  'hoursExtrasJson': null,
  'cateringDeliveryJson': catering,
  'regularDeliveryJson': null,
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': (updatedAt ?? _updatedAt).toIso8601String(),
};
