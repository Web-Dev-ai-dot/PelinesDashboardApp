import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/features/locations/data/location_selection_store.dart';
import 'package:pelines_admin_app/features/locations/data/locations_repository.dart';
import 'package:pelines_admin_app/features/locations/models/business_hours.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/models/temporary_closure.dart';
import 'package:pelines_admin_app/features/locations/presentation/store_operations_screen.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';

void main() {
  test('schedule serializes exactly seven days and closed as null', () {
    BusinessHoursSchedule schedule = BusinessHoursSchedule.dashboardDefault();
    schedule = schedule.replaceDay(2, schedule.days[2].copyWith(closed: true));
    final Map<String, dynamic> json = schedule.toJson();
    expect(json.keys.toSet(), businessDayKeys.toSet());
    expect(json, hasLength(7));
    expect(json['wed'], isNull);
    expect(json['mon'], <String, String>{'open': '11:00', 'close': '22:00'});
  });

  test('validation rejects equal and overnight hours', () {
    final BusinessHoursSchedule base = BusinessHoursSchedule.dashboardDefault();
    expect(
      base
          .replaceDay(
            0,
            const BusinessDayHours(
              open: '11:00',
              close: '11:00',
              closed: false,
            ),
          )
          .validate(),
      contains('Overnight'),
    );
    expect(
      base
          .replaceDay(
            0,
            const BusinessDayHours(
              open: '22:00',
              close: '02:00',
              closed: false,
            ),
          )
          .validate(),
      contains('Overnight'),
    );
  });

  test(
    'repository PATCH contains only hoursJson and leaves extras out',
    () async {
      final BusinessHoursSchedule schedule =
          BusinessHoursSchedule.dashboardDefault();
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'));
      Map<String, dynamic>? patchBody;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                if (options.method == 'PATCH') {
                  patchBody = Map<String, dynamic>.from(
                    options.data as Map<String, dynamic>,
                  );
                }
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: _locationJson(
                      hours: options.method == 'PATCH'
                          ? schedule.toJson()
                          : null,
                    ),
                  ),
                );
              },
        ),
      );
      final ApiLocationsRepository repository = ApiLocationsRepository(
        ApiClient(dio: dio),
      );

      await repository.saveBusinessHours(
        locationId: 'location-id',
        originalUpdatedAt: DateTime.utc(2026, 9, 4),
        schedule: schedule,
      );

      expect(patchBody?.keys, <String>{'hoursJson'});
      expect(patchBody, isNot(contains('hoursExtrasJson')));
      expect(
        (patchBody!['hoursJson'] as Map<String, dynamic>).keys.toSet(),
        businessDayKeys.toSet(),
      );
    },
  );

  test('updatedAt conflict prevents PATCH', () async {
    int patches = 0;
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          if (options.method == 'PATCH') patches++;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: _locationJson(hours: null),
            ),
          );
        },
      ),
    );
    final ApiLocationsRepository repository = ApiLocationsRepository(
      ApiClient(dio: dio),
    );
    expect(
      () => repository.saveBusinessHours(
        locationId: 'location-id',
        originalUpdatedAt: DateTime.utc(2026, 9, 3),
        schedule: BusinessHoursSchedule.dashboardDefault(),
      ),
      throwsA(isA<LocationSettingsConflict>()),
    );
    expect(patches, 0);
  });

  testWidgets(
    'null hours displays not configured and opening edit does not PATCH',
    (WidgetTester tester) async {
      final Location location = Location.fromJson(_locationJson(hours: null));
      final _FakeRepository repository = _FakeRepository(location);
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
        find.byKey(const Key('edit-business-hours')),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Business hours are not configured.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('edit-business-hours')));
      await tester.pumpAndSettle();
      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('11:00 AM'), findsWidgets);
      expect(repository.hourSaves, 0);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(repository.hourSaves, 0);

      await tester.tap(find.byKey(const Key('edit-business-hours')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('business-day-0')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(repository.hourSaves, 0);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
    },
  );
}

Map<String, dynamic> _locationJson({required Map<String, dynamic>? hours}) =>
    <String, dynamic>{
      'id': 'location-id',
      'name': 'Tualatin',
      'slug': 'tualatin',
      'address': '123 Example St',
      'phone': null,
      'hoursJson': hours,
      'isActive': true,
      'deliveryFeeCents': 0,
      'deliveryMinimumCents': 0,
      'isAcceptingOrders': true,
      'servicePrefsJson': null,
      'hoursExtrasJson': <String, dynamic>{
        'closures': <dynamic>[],
        'futureField': <String, dynamic>{'x': 1},
      },
      'cateringDeliveryJson': null,
      'regularDeliveryJson': null,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-09-04T00:00:00.000Z',
    };

class _FakeRepository implements LocationsRepository {
  _FakeRepository(this.location);
  final Location location;
  int hourSaves = 0;
  @override
  Future<List<Location>> getLocations() async => <Location>[location];
  @override
  Future<Location> getLocation(String locationId) async => location;
  @override
  Future<Location> saveBusinessHours({
    required String locationId,
    required DateTime originalUpdatedAt,
    required BusinessHoursSchedule schedule,
  }) async {
    hourSaves++;
    return location;
  }

  @override
  Future<Location> saveClosure({
    required String locationId,
    required DateTime originalUpdatedAt,
    required TemporaryClosure closure,
    required bool isNew,
  }) => throw UnimplementedError();
  @override
  Future<Location> setAcceptingOrders(
    String locationId,
    bool isAcceptingOrders,
  ) => throw UnimplementedError();
  @override
  Future<Location> saveRegularDeliverySettings({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool enabled,
    required int feeCents,
  }) => throw UnimplementedError();
  @override
  Future<Location> saveCateringDeliverySettings({
    required String locationId, required DateTime originalUpdatedAt,
    required bool originalEnabled, required bool enabled,
    required int originalFeeCents, required int feeCents,
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
