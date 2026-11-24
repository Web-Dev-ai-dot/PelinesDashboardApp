import 'package:dio/dio.dart';

import 'holidays_repository.dart';
import '../models/holiday.dart';

import 'pickup_service_repository.dart';
import '../models/pickup_service_settings.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../models/location.dart';
import '../models/business_hours.dart';
import '../models/temporary_closure.dart';
import '../models/regular_delivery.dart';
import '../models/catering_delivery.dart';
import '../models/auto_accept.dart';
import '../models/auto_cancellation.dart';
import 'auto_cancellation_repository.dart';
import 'pickup_preferences_repository.dart';
import '../models/pickup_service_preferences.dart';

class LocationSettingsConflict implements Exception {
  const LocationSettingsConflict(this.canonical);
  final Location canonical;
}

abstract interface class LocationsRepository {
  Future<List<Location>> getLocations();
  Future<Location> getLocation(String locationId);
  Future<Location> setAcceptingOrders(
    String locationId,
    bool isAcceptingOrders,
  );
  Future<Location> saveClosure({
    required String locationId,
    required DateTime originalUpdatedAt,
    required TemporaryClosure closure,
    required bool isNew,
  });
  Future<Location> saveBusinessHours({
    required String locationId,
    required DateTime originalUpdatedAt,
    required BusinessHoursSchedule schedule,
  });
  Future<Location> saveRegularDeliverySettings({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool enabled,
    required int feeCents,
  });
  Future<Location> saveCateringDeliverySettings({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool originalEnabled,
    required bool enabled,
    required int originalFeeCents,
    required int feeCents,
  });
  Future<Location> saveAutoAcceptSettings({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool originalRegular,
    required bool regular,
    required bool originalCatering,
    required bool catering,
  });
}

class ApiLocationsRepository
    implements
        LocationsRepository,
        AutoCancellationRepository,
        PickupPreferencesRepository,
        PickupServiceRepository,
        HolidaysRepository {
  ApiLocationsRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Location>> getLocations() async {
    try {
      final Response<dynamic> response = await _client.dio.get<dynamic>(
        'locations',
      );
      final Object? data = response.data;
      if (data is! List<dynamic>) {
        throw const FormatException('Invalid /locations response.');
      }
      return data
          .map((dynamic item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('Invalid location item.');
            }
            return Location.fromJson(item);
          })
          .toList(growable: false);
    } on DioException catch (error) {
      final int? status = error.response?.statusCode;
      final String message = switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout =>
          'The Pelines server timed out. Please try again.',
        DioExceptionType.connectionError =>
          'Could not connect to the Pelines server.',
        _ => 'The Pelines server could not load locations.',
      };
      throw ApiException(message: message, statusCode: status, cause: error);
    } on FormatException catch (error) {
      throw ApiException(
        message: 'The Pelines server returned invalid locations.',
        cause: error,
      );
    } on TypeError catch (error) {
      throw ApiException(
        message: 'The Pelines server returned invalid locations.',
        cause: error,
      );
    }
  }

  @override
  Future<Location> getLocation(String locationId) =>
      _locationRequest(() => _client.dio.get<dynamic>('locations/$locationId'));

  @override
  Future<Location> setAcceptingOrders(
    String locationId,
    bool isAcceptingOrders,
  ) => _locationRequest(
    () => _client.dio.patch<dynamic>(
      'locations/$locationId',
      data: <String, dynamic>{'isAcceptingOrders': isAcceptingOrders},
    ),
  );

  @override
  Future<Location> saveClosure({
    required String locationId,
    required DateTime originalUpdatedAt,
    required TemporaryClosure closure,
    required bool isNew,
  }) async {
    final Location canonical = await getLocation(locationId);
    if (canonical.updatedAt != originalUpdatedAt) {
      throw LocationSettingsConflict(canonical);
    }
    final List<TemporaryClosure> existing = closuresFromExtras(
      canonical.hoursExtrasJson,
    );
    final List<Map<String, dynamic>> next = existing
        .map((TemporaryClosure item) => item.toJson())
        .toList();
    if (isNew) {
      if (existing.any((TemporaryClosure item) => item.id == closure.id)) {
        throw LocationSettingsConflict(canonical);
      }
      next.add(closure.toJson());
    } else {
      final int index = existing.indexWhere(
        (TemporaryClosure item) => item.id == closure.id,
      );
      if (index < 0) throw LocationSettingsConflict(canonical);
      next[index] = closure.toJson();
    }
    final Map<String, dynamic> extras = <String, dynamic>{
      ...?canonical.hoursExtrasJson,
      'closures': next,
    };
    // updatedAt is checked immediately before this PATCH. The backend has no
    // conditional update, so a small race remains until it supports If-Match.
    return _locationRequest(
      () => _client.dio.patch<dynamic>(
        'locations/$locationId',
        data: <String, dynamic>{'hoursExtrasJson': extras},
      ),
    );
  }

  @override
  Future<Location> saveBusinessHours({
    required String locationId,
    required DateTime originalUpdatedAt,
    required BusinessHoursSchedule schedule,
  }) async {
    final Location canonical = await getLocation(locationId);
    if (canonical.updatedAt != originalUpdatedAt) {
      throw LocationSettingsConflict(canonical);
    }
    final String? validation = schedule.validate();
    if (validation != null) throw ArgumentError(validation);
    return _locationRequest(
      () => _client.dio.patch<dynamic>(
        'locations/$locationId',
        data: <String, dynamic>{'hoursJson': schedule.toJson()},
      ),
    );
  }

  @override
  Future<Location> saveRegularDeliverySettings({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool enabled,
    required int feeCents,
  }) async {
    final Location canonical = await getLocation(locationId);
    if (canonical.updatedAt != originalUpdatedAt) {
      throw LocationSettingsConflict(canonical);
    }
    final RegularDeliverySettings current = RegularDeliverySettings.fromJson(
      canonical.regularDeliveryJson,
    );
    final RegularDeliverySettings next = RegularDeliverySettings(
      enabled: enabled,
      feeCents: feeCents,
      minimumCents: current.minimumCents,
      preserved: current.preserved,
    );
    return _locationRequest(
      () => _client.dio.patch<dynamic>(
        'locations/$locationId',
        data: <String, dynamic>{'regularDeliveryJson': next.toJson()},
      ),
    );
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
    final Location canonical = await getLocation(locationId);
    if (canonical.updatedAt != originalUpdatedAt) {
      throw LocationSettingsConflict(canonical);
    }
    final CateringDeliverySettings current = CateringDeliverySettings.fromJson(
      canonical.cateringDeliveryJson,
    );
    final Map<String, dynamic> patch = <String, dynamic>{};
    if (enabled != originalEnabled) {
      patch['cateringDeliveryJson'] = current.withExplicitEnabled(enabled);
    }
    if (feeCents != originalFeeCents) {
      patch['deliveryFeeCents'] = feeCents;
    }
    if (patch.isEmpty) return canonical;
    return _locationRequest(
      () => _client.dio.patch<dynamic>('locations/$locationId', data: patch),
    );
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
    final Location canonical = await getLocation(locationId);
    if (canonical.updatedAt != originalUpdatedAt) {
      throw LocationSettingsConflict(canonical);
    }
    final AutoAcceptSettings current = AutoAcceptSettings.fromJson(
      canonical.servicePrefsJson,
    );
    final bool regularChanged = regular != originalRegular;
    final bool cateringChanged = catering != originalCatering;
    if (!regularChanged && !cateringChanged) return canonical;
    final Map<String, dynamic> next = current.withChanges(
      regularChanged: regularChanged,
      regular: regular,
      cateringChanged: cateringChanged,
      catering: catering,
    );
    return _locationRequest(
      () => _client.dio.patch<dynamic>(
        'locations/$locationId',
        data: <String, dynamic>{'servicePrefsJson': next},
      ),
    );
  }

  @override
  Future<Location> saveAutoCancellationSettings({
    required String locationId,
    required DateTime originalUpdatedAt,
    required PickupOrderKind kind,
    required AutoCancellationRule original,
    required AutoCancellationRule rule,
    required bool Function() canWrite,
  }) async {
    final validation = rule.validate(kind);
    if (validation != null) throw ArgumentError(validation);
    final canonical = await getLocation(locationId);
    if (!canWrite()) {
      throw const ApiException(
        message: 'The selected location changed. No change was sent.',
      );
    }
    if (canonical.updatedAt != originalUpdatedAt ||
        !AutoCancellationRule.fromJson(
          canonical.servicePrefsJson,
          kind,
        ).sameAs(original)) {
      throw LocationSettingsConflict(canonical);
    }
    if (rule.sameAs(original)) return canonical;
    final next = rule.mergeInto(canonical.servicePrefsJson, original, kind);
    return _locationRequest(
      () => _client.dio.patch<dynamic>(
        'locations/$locationId',
        data: <String, dynamic>{'servicePrefsJson': next},
      ),
    );
  }

  @override
  Future<Location> savePickupPreferences({
    required String locationId,
    required DateTime originalUpdatedAt,
    required PickupOrderKind kind,
    required PickupServicePreferences original,
    required PickupServicePreferences preferences,
    required bool Function() canWrite,
  }) async {
    final validation = preferences.validate();
    if (validation != null) throw ArgumentError(validation);
    final canonical = await getLocation(locationId);
    if (!canWrite()) {
      throw const ApiException(
        message: 'The selected location changed. No change was sent.',
      );
    }
    if (canonical.updatedAt != originalUpdatedAt ||
        !PickupServicePreferences.fromJson(
          canonical.servicePrefsJson,
          kind,
        ).sameAs(original)) {
      throw LocationSettingsConflict(canonical);
    }
    if (preferences.sameAs(original)) return canonical;
    final next = preferences.mergeInto(
      canonical.servicePrefsJson,
      original,
      kind,
    );
    // Local preflight only: the backend does not support atomic If-Match.
    return _locationRequest(
      () => _client.dio.patch<dynamic>(
        'locations/$locationId',
        data: <String, dynamic>{'servicePrefsJson': next},
      ),
    );
  }

  @override
  Future<Location> savePickupService({
    required String locationId,
    required PickupOrderKind kind,
    required PickupServiceSettings original,
    required PickupServiceSettings settings,
    required bool Function() canWrite,
  }) async {
    final validation = settings.validate(kind);
    if (validation != null) throw ArgumentError(validation);
    final canonical = await getLocation(locationId);
    if (!canWrite()) {
      throw const ApiException(
        message: 'The selected location changed. No change was sent.',
      );
    }
    // Another card may have saved since this draft began. Rebase only when
    // this entire order-type group is unchanged, preserving canonical JSON.
    if (!PickupServiceSettings.fromJson(
      canonical.servicePrefsJson,
      kind,
    ).sameAs(original)) {
      throw LocationSettingsConflict(canonical);
    }
    if (settings.sameAs(original)) return canonical;
    final next = settings.mergeInto(canonical.servicePrefsJson, original, kind);
    // Same existing endpoint/JSON contract; no server-side conditional write.
    return _locationRequest(
      () => _client.dio.patch<dynamic>(
        'locations/$locationId',
        data: {'servicePrefsJson': next},
      ),
    );
  }

  @override
  Future<Location> saveHolidays({
    required String locationId,
    required DateTime originalUpdatedAt,
    required List<Holiday> holidays,
    required bool Function() canWrite,
  }) async {
    final validation = validateHolidays(holidays);
    if (validation != null) throw ArgumentError(validation);
    final canonical = await getLocation(locationId);
    if (!canWrite()) {
      throw const ApiException(
        message: 'The selected location changed. No change was sent.',
      );
    }
    if (canonical.updatedAt != originalUpdatedAt) {
      throw LocationSettingsConflict(canonical);
    }
    if (canonical.hoursJson == null) {
      throw ArgumentError('Configure Standard Hours before saving holidays.');
    }
    holidaysFromExtras(
      canonical.hoursExtrasJson,
    ); // Reject unsupported data instead of replacing it.
    // Preserve closures, pickupOverride and future extras; use the existing API.
    // The API has no conditional PATCH, so the same small race as closures remains.
    return _locationRequest(
      () => _client.dio.patch<dynamic>(
        'locations/$locationId',
        data: {
          'hoursExtrasJson': {
            ...?canonical.hoursExtrasJson,
            'holidays': holidays.map((h) => h.toJson()).toList(),
          },
        },
      ),
    );
  }

  Future<Location> _locationRequest(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      final Response<dynamic> response = await request();
      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid location response.');
      }
      return Location.fromJson(data);
    } on DioException catch (error) {
      final int? status = error.response?.statusCode;
      final String message = switch (status) {
        400 => 'The server rejected the location change.',
        401 => 'The server rejected this request. Please try again.',
        403 => 'Administrator access is required.',
        404 => 'This location no longer exists.',
        _ => switch (error.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.receiveTimeout ||
          DioExceptionType.sendTimeout => 'The Pelines server timed out.',
          DioExceptionType.connectionError =>
            'Could not connect to the Pelines server.',
          _ => 'The Pelines server could not update this location.',
        },
      };
      throw ApiException(message: message, statusCode: status, cause: error);
    } on FormatException catch (error) {
      throw ApiException(
        message: 'The Pelines server returned an invalid location.',
        cause: error,
      );
    } on TypeError catch (error) {
      throw ApiException(
        message: 'The Pelines server returned an invalid location.',
        cause: error,
      );
    }
  }
}
