import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/features/locations/data/locations_repository.dart';
import 'package:pelines_admin_app/features/locations/models/business_hours.dart';
import 'package:pelines_admin_app/features/locations/models/regular_delivery.dart';

void main() {
  test('money parser is deterministic and rejects unsafe input', () {
    expect(parseMoneyCents('0'), 0);
    expect(parseMoneyCents('4'), 400);
    expect(parseMoneyCents('4.9'), 490);
    expect(parseMoneyCents('4.99'), 499);
    expect(parseMoneyCents('-1'), isNull);
    expect(parseMoneyCents('4.999'), isNull);
    expect(parseMoneyCents('invalid'), isNull);
  });

  test('edit preserves minimum and unknown keys in exclusive PATCH', () async {
    final _Harness harness = _Harness(<String, dynamic>{
      'enabled': true,
      'feeCents': 499,
      'minimumCents': 2500,
      'futureField': 'keep',
    });

    await harness.repository.saveRegularDeliverySettings(
      locationId: 'location-id',
      originalUpdatedAt: DateTime.utc(2026, 9, 5),
      enabled: true,
      feeCents: 599,
    );

    expect(harness.patchBody?.keys, <String>{'regularDeliveryJson'});
    final Map<String, dynamic> saved =
        harness.patchBody!['regularDeliveryJson'] as Map<String, dynamic>;
    expect(saved, <String, dynamic>{
      'enabled': true,
      'feeCents': 599,
      'minimumCents': 2500,
      'futureField': 'keep',
    });
  });

  test('disable preserves fee and minimum', () async {
    final _Harness harness = _Harness(<String, dynamic>{
      'enabled': true,
      'feeCents': 499,
      'minimumCents': 2500,
    });
    await harness.repository.saveRegularDeliverySettings(
      locationId: 'location-id',
      originalUpdatedAt: DateTime.utc(2026, 9, 5),
      enabled: false,
      feeCents: 499,
    );
    final Map<String, dynamic> saved =
        harness.patchBody!['regularDeliveryJson'] as Map<String, dynamic>;
    expect(saved['enabled'], false);
    expect(saved['feeCents'], 499);
    expect(saved['minimumCents'], 2500);
  });

  test(
    'null settings create only known safe schema on explicit save',
    () async {
      final _Harness harness = _Harness(null);
      await harness.repository.saveRegularDeliverySettings(
        locationId: 'location-id',
        originalUpdatedAt: DateTime.utc(2026, 9, 5),
        enabled: true,
        feeCents: 499,
      );
      expect(harness.patchBody!['regularDeliveryJson'], <String, dynamic>{
        'enabled': true,
        'feeCents': 499,
        'minimumCents': 0,
      });
    },
  );

  test('malformed known field and timestamp conflict never PATCH', () async {
    final _Harness malformed = _Harness(<String, dynamic>{'enabled': 'yes'});
    expect(
      () => malformed.repository.saveRegularDeliverySettings(
        locationId: 'location-id',
        originalUpdatedAt: DateTime.utc(2026, 9, 5),
        enabled: true,
        feeCents: 0,
      ),
      throwsA(isA<UnsupportedRegularDeliveryFormat>()),
    );
    expect(malformed.patchCalls, 0);

    final _Harness conflict = _Harness(null);
    expect(
      () => conflict.repository.saveRegularDeliverySettings(
        locationId: 'location-id',
        originalUpdatedAt: DateTime.utc(2026, 9, 4),
        enabled: true,
        feeCents: 0,
      ),
      throwsA(isA<LocationSettingsConflict>()),
    );
    expect(conflict.patchCalls, 0);
  });
}

class _Harness {
  _Harness(Map<String, dynamic>? settings) {
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
              data: _locationJson(settings),
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

Map<String, dynamic> _locationJson(Map<String, dynamic>? regular) =>
    <String, dynamic>{
      'id': 'location-id',
      'name': 'Tualatin',
      'slug': 'tualatin',
      'address': '123 Example St',
      'phone': null,
      'hoursJson': BusinessHoursSchedule.dashboardDefault().toJson(),
      'isActive': true,
      'deliveryFeeCents': 0,
      'deliveryMinimumCents': 0,
      'isAcceptingOrders': true,
      'servicePrefsJson': null,
      'hoursExtrasJson': null,
      'cateringDeliveryJson': null,
      'regularDeliveryJson': regular,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-09-05T00:00:00.000Z',
    };
