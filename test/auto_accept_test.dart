import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/locations/data/location_selection_store.dart';
import 'package:pelines_admin_app/features/locations/data/locations_repository.dart';
import 'package:pelines_admin_app/features/locations/models/auto_accept.dart';
import 'package:pelines_admin_app/features/locations/models/business_hours.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/models/temporary_closure.dart';
import 'package:pelines_admin_app/features/locations/presentation/auto_accept_screen.dart';
import 'package:pelines_admin_app/features/locations/presentation/store_operations_screen.dart';
import 'package:pelines_admin_app/features/locations/providers/auto_accept_controller.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';

void main() {
  group('effective semantics', () {
    test('null and empty default both order types to manual', () {
      for (final Map<String, dynamic>? json in <Map<String, dynamic>?>[
        null,
        <String, dynamic>{},
      ]) {
        final AutoAcceptSettings settings = AutoAcceptSettings.fromJson(json);
        expect(settings.regular, false);
        expect(settings.catering, false);
      }
    });

    for (final Object? value in <Object?>[null, false, true]) {
      test('regular $value is parsed without truthiness', () {
        final AutoAcceptSettings settings = AutoAcceptSettings.fromJson(
          <String, dynamic>{'autoAcceptRegular': value},
        );
        expect(settings.regular, value == true);
      });
      test('catering $value is parsed without truthiness', () {
        final AutoAcceptSettings settings = AutoAcceptSettings.fromJson(
          <String, dynamic>{'autoAcceptCatering': value},
        );
        expect(settings.catering, value == true);
      });
    }

    test('malformed target field blocks editing', () {
      expect(
        () => AutoAcceptSettings.fromJson(<String, dynamic>{
          'autoAcceptRegular': 'false',
        }),
        throwsA(isA<UnsupportedAutoAcceptFormat>()),
      );
    });
  });

  test('null root plus regular ON writes only minimal JSON', () async {
    final _ApiHarness harness = _ApiHarness(prefs: null);
    await harness.repository.saveAutoAcceptSettings(
      locationId: 'location-id',
      originalUpdatedAt: _updatedAt,
      originalRegular: false,
      regular: true,
      originalCatering: false,
      catering: false,
    );
    expect(harness.patchBody, <String, dynamic>{
      'servicePrefsJson': <String, dynamic>{'autoAcceptRegular': true},
    });
  });

  test('known and deeply nested unknown fields are preserved', () async {
    final Map<String, dynamic> prefs = <String, dynamic>{
      'acceptRegular': true,
      'autoAcceptRegular': false,
      'minRegular': 15,
      'autoCancelRegularEnabled': true,
      'futureField': <String, dynamic>{
        'x': 1,
        'items': <dynamic>[
          <String, dynamic>{'keep': true},
        ],
      },
    };
    final _ApiHarness harness = _ApiHarness(prefs: prefs);
    await harness.repository.saveAutoAcceptSettings(
      locationId: 'location-id',
      originalUpdatedAt: _updatedAt,
      originalRegular: false,
      regular: true,
      originalCatering: false,
      catering: false,
    );
    final Map<String, dynamic> saved =
        harness.patchBody!['servicePrefsJson'] as Map<String, dynamic>;
    expect(saved, <String, dynamic>{...prefs, 'autoAcceptRegular': true});
    expect(identical(saved['futureField'], prefs['futureField']), false);
  });

  test(
    'both changes use one exact PATCH and explicit false remains present',
    () async {
      final _ApiHarness harness = _ApiHarness(
        prefs: <String, dynamic>{
          'autoAcceptRegular': false,
          'autoAcceptCatering': true,
          'other': 7,
        },
      );
      await harness.repository.saveAutoAcceptSettings(
        locationId: 'location-id',
        originalUpdatedAt: _updatedAt,
        originalRegular: false,
        regular: true,
        originalCatering: true,
        catering: false,
      );
      expect(harness.patchCalls, 1);
      expect(harness.patchBody, <String, dynamic>{
        'servicePrefsJson': <String, dynamic>{
          'autoAcceptRegular': true,
          'autoAcceptCatering': false,
          'other': 7,
        },
      });
    },
  );

  test('no semantic change and timestamp conflict never PATCH', () async {
    final _ApiHarness noChange = _ApiHarness(prefs: null);
    await noChange.repository.saveAutoAcceptSettings(
      locationId: 'location-id',
      originalUpdatedAt: _updatedAt,
      originalRegular: false,
      regular: false,
      originalCatering: false,
      catering: false,
    );
    expect(noChange.patchCalls, 0);

    final _ApiHarness conflict = _ApiHarness(
      prefs: null,
      updatedAt: DateTime.utc(2026, 9, 6),
    );
    await expectLater(
      conflict.repository.saveAutoAcceptSettings(
        locationId: 'location-id',
        originalUpdatedAt: _updatedAt,
        originalRegular: false,
        regular: true,
        originalCatering: false,
        catering: false,
      ),
      throwsA(isA<LocationSettingsConflict>()),
    );
    expect(conflict.patchCalls, 0);
  });

  test('malformed canonical target prevents PATCH', () async {
    final _ApiHarness harness = _ApiHarness(
      prefs: <String, dynamic>{'autoAcceptRegular': 'false'},
    );
    await expectLater(
      harness.repository.saveAutoAcceptSettings(
        locationId: 'location-id',
        originalUpdatedAt: _updatedAt,
        originalRegular: false,
        regular: true,
        originalCatering: false,
        catering: false,
      ),
      throwsA(isA<UnsupportedAutoAcceptFormat>()),
    );
    expect(harness.patchCalls, 0);
  });

  testWidgets('summary and editor show manual defaults without saving', (
    WidgetTester tester,
  ) async {
    final Location initial = _location(prefs: null);
    final _FakeRepository repository = _FakeRepository(initial: initial);
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
      find.byKey(const Key('auto-accept-card')),
      500,
    );
    expect(find.text('Auto-Accept Orders'), findsOneWidget);
    expect(find.text('Manual acceptance'), findsNWidgets(2));
    expect(repository.saveCalls, 0);
    await tester.ensureVisible(find.byKey(const Key('edit-auto-accept')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-auto-accept')));
    await tester.pumpAndSettle();
    expect(
      find.text('Automatically accept paid regular orders'),
      findsOneWidget,
    );
    expect(
      find.text('Automatically accept paid catering orders'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('auto-accept-save')))
          .onPressed,
      isNull,
    );
  });

  for (final ({bool catering, bool initial, String title, String detail})
      scenario
      in <({bool catering, bool initial, String title, String detail})>[
        (
          catering: false,
          initial: false,
          title: 'Enable automatic acceptance for regular orders?',
          detail: 'Paid regular orders can move directly to Confirmed without manual review.',
        ),
        (
          catering: false,
          initial: true,
          title: 'Switch regular orders to manual acceptance?',
          detail: 'Paid regular orders processed after this change will remain Pending until staff accepts them.',
        ),
        (
          catering: true,
          initial: false,
          title: 'Enable automatic acceptance for catering orders?',
          detail: 'This may commit the restaurant to new catering orders before staff reviews them.',
        ),
        (
          catering: true,
          initial: true,
          title: 'Switch catering orders to manual acceptance?',
          detail: 'Paid catering orders processed after this change will remain Pending until staff accepts them.',
        ),
      ]) {
    testWidgets('confirmation: ${scenario.title}', (WidgetTester tester) async {
      final Location initial = _location(
        prefs: <String, dynamic>{
          scenario.catering ? 'autoAcceptCatering' : 'autoAcceptRegular':
              scenario.initial,
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: AutoAcceptScreen(location: initial)),
        ),
      );
      final Key key = Key(
        scenario.catering ? 'auto-accept-catering' : 'auto-accept-regular',
      );
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(find.text(scenario.title), findsOneWidget);
      expect(find.textContaining(scenario.detail), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byKey(key)).value,
        scenario.initial,
      );
    });
  }

  testWidgets('default OFF to ON to OFF returns clean after confirmations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: AutoAcceptScreen(location: _location(prefs: null)),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('auto-accept-regular')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auto-accept-regular-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auto-accept-regular')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auto-accept-regular-confirm')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('auto-accept-save')))
          .onPressed,
      isNull,
    );
  });

  final List<
    ({
      String name,
      bool oldRegular,
      bool regular,
      bool oldCatering,
      bool catering,
      Map<String, dynamic>? result,
      bool success,
    })
  >
  timeoutCases = [
    (
      name: 'regular ON applied',
      oldRegular: false,
      regular: true,
      oldCatering: false,
      catering: false,
      result: <String, dynamic>{'autoAcceptRegular': true},
      success: true,
    ),
    (
      name: 'regular OFF applied',
      oldRegular: true,
      regular: false,
      oldCatering: false,
      catering: false,
      result: <String, dynamic>{'autoAcceptRegular': false},
      success: true,
    ),
    (
      name: 'catering ON applied',
      oldRegular: false,
      regular: false,
      oldCatering: false,
      catering: true,
      result: <String, dynamic>{'autoAcceptCatering': true},
      success: true,
    ),
    (
      name: 'catering OFF applied',
      oldRegular: false,
      regular: false,
      oldCatering: true,
      catering: false,
      result: <String, dynamic>{'autoAcceptCatering': false},
      success: true,
    ),
    (
      name: 'both applied',
      oldRegular: false,
      regular: true,
      oldCatering: false,
      catering: true,
      result: <String, dynamic>{
        'autoAcceptRegular': true,
        'autoAcceptCatering': true,
      },
      success: true,
    ),
    (
      name: 'not applied',
      oldRegular: false,
      regular: true,
      oldCatering: false,
      catering: false,
      result: null,
      success: false,
    ),
    (
      name: 'explicit OFF missing is ambiguous',
      oldRegular: true,
      regular: false,
      oldCatering: false,
      catering: false,
      result: <String, dynamic>{},
      success: false,
    ),
    (
      name: 'malformed canonical is ambiguous',
      oldRegular: false,
      regular: true,
      oldCatering: false,
      catering: false,
      result: <String, dynamic>{'autoAcceptRegular': 'true'},
      success: false,
    ),
  ];
  for (final scenario in timeoutCases) {
    test('timeout ${scenario.name} without second PATCH', () async {
      final Location initial = _location(
        prefs: <String, dynamic>{
          'autoAcceptRegular': scenario.oldRegular,
          'autoAcceptCatering': scenario.oldCatering,
        },
      );
      final _FakeRepository repository = _FakeRepository(
        initial: initial,
        finalLocation: _location(prefs: scenario.result),
        saveError: _timeout(),
      );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);
      await container
          .read(autoAcceptProvider.notifier)
          .save(
            locationId: initial.id,
            originalUpdatedAt: initial.updatedAt,
            originalRegular: scenario.oldRegular,
            regular: scenario.regular,
            originalCatering: scenario.oldCatering,
            catering: scenario.catering,
          );
      expect(repository.saveCalls, 1);
      expect(repository.readCalls, 1);
      expect(
        container.read(autoAcceptProvider).phase,
        scenario.success ? AutoAcceptPhase.success : AutoAcceptPhase.error,
      );
    });
  }

  test(
    'success adopts full canonical location and updatedAt in both providers',
    () async {
      final Location initial = _location(prefs: null);
      final Location canonical = _location(
        prefs: <String, dynamic>{'autoAcceptRegular': true},
        updatedAt: DateTime.utc(2026, 9, 7),
      );
      final _FakeRepository repository = _FakeRepository(
        initial: initial,
        finalLocation: canonical,
      );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);
      await container
          .read(autoAcceptProvider.notifier)
          .save(
            locationId: initial.id,
            originalUpdatedAt: initial.updatedAt,
            originalRegular: false,
            regular: true,
            originalCatering: false,
            catering: false,
          );
      expect(container.read(autoAcceptProvider).phase, AutoAcceptPhase.success);
      expect(
        container.read(currentLocationProvider).value?.updatedAt,
        canonical.updatedAt,
      );
      expect(
        container.read(locationsProvider).value?.single.updatedAt,
        canonical.updatedAt,
      );
      expect(await repository.store.readLocationId(), initial.id);
    },
  );

  test('location change blocks save', () async {
    final Location initial = _location(prefs: null);
    final Location other = _location(
      prefs: null,
      id: 'other-id',
      name: 'Troutdale',
    );
    final _FakeRepository repository = _FakeRepository(
      initial: initial,
      locations: <Location>[initial, other],
    );
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    await container.read(currentLocationProvider.notifier).select(other);
    await container
        .read(autoAcceptProvider.notifier)
        .save(
          locationId: initial.id,
          originalUpdatedAt: initial.updatedAt,
          originalRegular: false,
          regular: true,
          originalCatering: false,
          catering: false,
        );
    expect(repository.saveCalls, 0);
    expect(container.read(autoAcceptProvider).phase, AutoAcceptPhase.error);
  });
}

final DateTime _updatedAt = DateTime.utc(2026, 9, 5);

class _ApiHarness {
  _ApiHarness({required Map<String, dynamic>? prefs, DateTime? updatedAt}) {
    final Map<String, dynamic> response = _locationJson(
      prefs: prefs,
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
              data: response,
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

ProviderContainer _container(_FakeRepository repository) => ProviderContainer(
  overrides: [
    locationsRepositoryProvider.overrideWithValue(repository),
    locationSelectionStoreProvider.overrideWithValue(repository.store),
  ],
);

class _FakeRepository implements LocationsRepository {
  _FakeRepository({
    required this.initial,
    Location? finalLocation,
    this.saveError,
    List<Location>? locations,
  }) : finalLocation = finalLocation ?? initial,
       locations = locations ?? <Location>[initial];
  final Location initial;
  final Location finalLocation;
  final Object? saveError;
  final List<Location> locations;
  final _MemoryStore store = _MemoryStore();
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
  Future<Location> saveAutoAcceptSettings({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool originalRegular,
    required bool regular,
    required bool originalCatering,
    required bool catering,
  }) async {
    saveCalls++;
    if (saveError != null) throw saveError!;
    return finalLocation;
  }

  @override
  Future<Location> setAcceptingOrders(String locationId, bool value) =>
      throw UnimplementedError();
  @override
  Future<Location> saveClosure({
    required String locationId,
    required DateTime originalUpdatedAt,
    required TemporaryClosure closure,
    required bool isNew,
  }) => throw UnimplementedError();
  @override
  Future<Location> saveBusinessHours({
    required String locationId,
    required DateTime originalUpdatedAt,
    required BusinessHoursSchedule schedule,
  }) => throw UnimplementedError();
  @override
  Future<Location> saveRegularDeliverySettings({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool enabled,
    required int feeCents,
  }) => throw UnimplementedError();
  @override
  Future<Location> saveCateringDeliverySettings({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool originalEnabled,
    required bool enabled,
    required int originalFeeCents,
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

Location _location({
  required Map<String, dynamic>? prefs,
  DateTime? updatedAt,
  String id = 'location-id',
  String name = 'Tualatin',
}) => Location.fromJson(
  _locationJson(prefs: prefs, updatedAt: updatedAt, id: id, name: name),
);

Map<String, dynamic> _locationJson({
  required Map<String, dynamic>? prefs,
  DateTime? updatedAt,
  String id = 'location-id',
  String name = 'Tualatin',
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'slug': name.toLowerCase(),
  'address': '123 Example St',
  'phone': null,
  'hoursJson': null,
  'isActive': true,
  'deliveryFeeCents': 500,
  'deliveryMinimumCents': 15000,
  'isAcceptingOrders': true,
  'servicePrefsJson': prefs,
  'hoursExtrasJson': null,
  'cateringDeliveryJson': null,
  'regularDeliveryJson': null,
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': (updatedAt ?? _updatedAt).toIso8601String(),
};

ApiException _timeout() => ApiException(
  message: 'The Pelines server timed out.',
  cause: DioException(
    requestOptions: RequestOptions(path: 'locations/location-id'),
    type: DioExceptionType.receiveTimeout,
  ),
);
