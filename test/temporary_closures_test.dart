import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/locations/data/location_selection_store.dart';
import 'package:pelines_admin_app/features/locations/data/locations_repository.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/models/business_hours.dart';
import 'package:pelines_admin_app/features/locations/models/temporary_closure.dart';
import 'package:pelines_admin_app/features/locations/providers/closures_controller.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';

void main() {
  test('editing preserves root, sibling, and unknown closure fields', () async {
    final Map<String, dynamic> extras = _extras();
    final _RecordingAdapter adapter = _RecordingAdapter(
      _locationJson(extras: extras),
    );
    final ApiLocationsRepository repository = _repository(adapter);
    final TemporaryClosure original = closuresFromExtras(extras).first;

    await repository.saveClosure(
      locationId: 'location-id',
      originalUpdatedAt: DateTime.utc(2026, 9, 4),
      closure: original.copyWith(reason: 'Renovation'),
      isNew: false,
    );

    final Map<String, dynamic> body = adapter.patchBody!;
    expect(body.keys, <String>{'hoursExtrasJson'});
    final Map<String, dynamic> saved =
        body['hoursExtrasJson'] as Map<String, dynamic>;
    expect(saved['holidays'], extras['holidays']);
    expect(saved['pickupOverride'], extras['pickupOverride']);
    expect(saved['futureField'], extras['futureField']);
    final List<dynamic> closures = saved['closures'] as List<dynamic>;
    expect(closures, hasLength(2));
    expect((closures[0] as Map<String, dynamic>)['reason'], 'Renovation');
    expect(
      (closures[0] as Map<String, dynamic>)['futureClosureField'],
      'keep-me',
    );
    expect(closures[1], (extras['closures'] as List<dynamic>)[1]);
  });

  test(
    'creating from null JSON sends only closures and keeps calendar dates',
    () async {
      final _RecordingAdapter adapter = _RecordingAdapter(
        _locationJson(extras: null),
      );
      final ApiLocationsRepository repository = _repository(adapter);
      final TemporaryClosure closure = TemporaryClosure(
        id: newClosureId(),
        reason: '',
        start: '2026-11-01',
        end: '2026-11-01',
        notes: '',
        active: true,
      );

      await repository.saveClosure(
        locationId: 'location-id',
        originalUpdatedAt: DateTime.utc(2026, 9, 4),
        closure: closure,
        isNew: true,
      );

      final Map<String, dynamic> saved =
          adapter.patchBody!['hoursExtrasJson'] as Map<String, dynamic>;
      expect(saved.keys, <String>{'closures'});
      final Map<String, dynamic> item =
          (saved['closures'] as List<dynamic>).single as Map<String, dynamic>;
      expect(item['start'], '2026-11-01');
      expect(item['end'], '2026-11-01');
    },
  );

  test('deactivation preserves the entity and changes only active', () async {
    final Map<String, dynamic> extras = _extras();
    final _RecordingAdapter adapter = _RecordingAdapter(
      _locationJson(extras: extras),
    );
    final TemporaryClosure closure = closuresFromExtras(extras).first;

    await _repository(adapter).saveClosure(
      locationId: 'location-id',
      originalUpdatedAt: DateTime.utc(2026, 9, 4),
      closure: closure.copyWith(active: false),
      isNew: false,
    );

    final List<dynamic> saved =
        (adapter.patchBody!['hoursExtrasJson']
                as Map<String, dynamic>)['closures']
            as List<dynamic>;
    expect(saved, hasLength(2));
    expect((saved.first as Map<String, dynamic>)['id'], closure.id);
    expect((saved.first as Map<String, dynamic>)['active'], false);
  });

  test('malformed closures and updatedAt conflict never PATCH', () async {
    for (final ({Map<String, dynamic>? extras, DateTime expected}) fixture
        in <({Map<String, dynamic>? extras, DateTime expected})>[
          (
            extras: <String, dynamic>{'closures': 'bad'},
            expected: DateTime.utc(2026, 9, 4),
          ),
          (extras: null, expected: DateTime.utc(2026, 9, 3)),
        ]) {
      final _RecordingAdapter adapter = _RecordingAdapter(
        _locationJson(extras: fixture.extras),
      );
      final TemporaryClosure closure = TemporaryClosure(
        id: 'new-id',
        reason: '',
        start: '2026-09-05',
        end: '2026-09-05',
        notes: '',
        active: true,
      );
      expect(
        () => _repository(adapter).saveClosure(
          locationId: 'location-id',
          originalUpdatedAt: fixture.expected,
          closure: closure,
          isNew: true,
        ),
        throwsA(
          anyOf(
            isA<UnsupportedClosureFormat>(),
            isA<LocationSettingsConflict>(),
          ),
        ),
      );
      expect(adapter.patchCalls, 0);
    }
  });

  test('calendar parsing validates dates without timezone conversion', () {
    expect(formatCalendarDate(DateTime(2026, 9, 4)), '2026-09-04');
    expect(parseCalendarDate('2026-09-04'), DateTime(2026, 9, 4));
    expect(parseCalendarDate('2026-02-30'), isNull);
    expect(parseCalendarDate('2026-9-4'), isNull);
    expect(isValidClosureRange('2026-09-04', '2026-09-04'), true);
    expect(isValidClosureRange('2026-09-04', '2026-09-06'), true);
    expect(isValidClosureRange('2026-09-06', '2026-09-04'), false);
    expect(
      newClosureId(),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  for (final bool applied in <bool>[true, false]) {
    test(
      'timeout reconciliation applied=$applied sends no second PATCH',
      () async {
        final TemporaryClosure expected = TemporaryClosure(
          id: 'new-id',
          reason: 'Weather',
          start: '2026-09-05',
          end: '2026-09-06',
          notes: '',
          active: true,
        );
        final Location initial = Location.fromJson(_locationJson(extras: null));
        final Location after = Location.fromJson(
          _locationJson(
            extras: applied
                ? <String, dynamic>{
                    'closures': <dynamic>[expected.toJson()],
                  }
                : null,
            updatedAt: '2026-09-05T00:00:00.000Z',
          ),
        );
        final _TimeoutRepository repository = _TimeoutRepository(
          initial,
          after,
        );
        final ProviderContainer container = ProviderContainer(
          overrides: [
            locationsRepositoryProvider.overrideWithValue(repository),
            locationSelectionStoreProvider.overrideWithValue(_MemoryStore()),
          ],
        );
        addTearDown(container.dispose);
        await container.read(currentLocationProvider.future);

        await container
            .read(closureSaveProvider.notifier)
            .save(
              locationId: initial.id,
              originalUpdatedAt: initial.updatedAt,
              closure: expected,
              isNew: true,
            );

        expect(repository.saveCalls, 1);
        expect(repository.getCalls, 1);
        expect(
          container.read(closureSaveProvider).phase,
          applied ? ClosureSavePhase.success : ClosureSavePhase.error,
        );
      },
    );
  }

  test(
    'changed location context prevents either location from being patched',
    () async {
      final Location first = Location.fromJson(_locationJson(extras: null));
      final Location second = Location.fromJson(<String, dynamic>{
        ..._locationJson(extras: null),
        'id': 'second-id',
        'name': 'Troutdale',
        'slug': 'troutdale',
      });
      final _ContextRepository repository = _ContextRepository(<Location>[
        first,
        second,
      ]);
      final ProviderContainer container = ProviderContainer(
        overrides: [
          locationsRepositoryProvider.overrideWithValue(repository),
          locationSelectionStoreProvider.overrideWithValue(_MemoryStore()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);
      await container.read(currentLocationProvider.notifier).select(second);

      await container
          .read(closureSaveProvider.notifier)
          .save(
            locationId: first.id,
            originalUpdatedAt: first.updatedAt,
            closure: TemporaryClosure(
              id: 'new-id',
              reason: '',
              start: '2026-09-05',
              end: '2026-09-05',
              notes: '',
              active: true,
            ),
            isNew: true,
          );

      expect(repository.saveCalls, 0);
      expect(container.read(closureSaveProvider).phase, ClosureSavePhase.error);
      expect(container.read(currentLocationProvider).value?.id, second.id);
    },
  );
}

ApiLocationsRepository _repository(_RecordingAdapter adapter) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'));
  dio.httpClientAdapter = adapter;
  return ApiLocationsRepository(ApiClient(dio: dio));
}

Map<String, dynamic> _extras() => <String, dynamic>{
  'closures': <dynamic>[
    <String, dynamic>{
      'id': 'a',
      'reason': 'Maintenance',
      'start': '2026-09-04',
      'end': '2026-09-05',
      'notes': '',
      'active': true,
      'futureClosureField': 'keep-me',
    },
    <String, dynamic>{
      'id': 'b',
      'reason': 'Private event',
      'start': '2026-09-20',
      'end': '2026-09-20',
      'notes': 'keep sibling',
      'active': false,
    },
  ],
  'holidays': <dynamic>[
    <String, dynamic>{'date': '2026-12-25', 'status': 'closed'},
  ],
  'pickupOverride': <dynamic>[
    <String, dynamic>{'day': 'Mon'},
  ],
  'futureField': <String, dynamic>{'x': 1},
};

Map<String, dynamic> _locationJson({
  Map<String, dynamic>? extras,
  String updatedAt = '2026-09-04T00:00:00.000Z',
}) => <String, dynamic>{
  'id': 'location-id',
  'name': 'Tualatin',
  'slug': 'tualatin',
  'address': '123 Example St',
  'phone': null,
  'hoursJson': null,
  'isActive': true,
  'deliveryFeeCents': 0,
  'deliveryMinimumCents': 0,
  'isAcceptingOrders': true,
  'servicePrefsJson': null,
  'hoursExtrasJson': extras,
  'cateringDeliveryJson': null,
  'regularDeliveryJson': null,
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': updatedAt,
};

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.location);
  final Map<String, dynamic> location;
  Map<String, dynamic>? patchBody;
  int patchCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'PATCH') {
      patchCalls++;
      patchBody = Map<String, dynamic>.from(
        options.data as Map<String, dynamic>,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(location),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _TimeoutRepository implements LocationsRepository {
  _TimeoutRepository(this.initial, this.after);
  final Location initial;
  final Location after;
  int saveCalls = 0;
  int getCalls = 0;
  @override
  Future<List<Location>> getLocations() async => <Location>[initial];
  @override
  Future<Location> getLocation(String locationId) async {
    getCalls++;
    return after;
  }

  @override
  Future<Location> saveClosure({
    required String locationId,
    required DateTime originalUpdatedAt,
    required TemporaryClosure closure,
    required bool isNew,
  }) async {
    saveCalls++;
    throw ApiException(
      message: 'The Pelines server timed out.',
      cause: DioException(
        requestOptions: RequestOptions(path: 'locations/$locationId'),
        type: DioExceptionType.receiveTimeout,
      ),
    );
  }

  @override
  Future<Location> setAcceptingOrders(
    String locationId,
    bool isAcceptingOrders,
  ) => throw UnimplementedError();
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
  @override
  Future<Location> saveAutoAcceptSettings({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool originalRegular,
    required bool regular,
    required bool originalCatering,
    required bool catering,
  }) => throw UnimplementedError();
}

class _ContextRepository implements LocationsRepository {
  _ContextRepository(this.locations);
  final List<Location> locations;
  int saveCalls = 0;

  @override
  Future<List<Location>> getLocations() async => locations;
  @override
  Future<Location> getLocation(String locationId) async =>
      locations.singleWhere((Location item) => item.id == locationId);
  @override
  Future<Location> saveClosure({
    required String locationId,
    required DateTime originalUpdatedAt,
    required TemporaryClosure closure,
    required bool isNew,
  }) async {
    saveCalls++;
    return getLocation(locationId);
  }

  @override
  Future<Location> setAcceptingOrders(
    String locationId,
    bool isAcceptingOrders,
  ) => throw UnimplementedError();
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
  @override
  Future<Location> saveAutoAcceptSettings({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool originalRegular,
    required bool regular,
    required bool originalCatering,
    required bool catering,
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
