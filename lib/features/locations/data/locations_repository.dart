import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../models/location.dart';

abstract interface class LocationsRepository {
  Future<List<Location>> getLocations();
  Future<Location> getLocation(String locationId);
  Future<Location> setAcceptingOrders(
    String locationId,
    bool isAcceptingOrders,
  );
}

class ApiLocationsRepository implements LocationsRepository {
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
        401 => 'Your session has expired. Please sign in again.',
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
