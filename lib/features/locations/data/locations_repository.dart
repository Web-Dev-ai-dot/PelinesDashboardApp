import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../models/location.dart';

abstract interface class LocationsRepository {
  Future<List<Location>> getLocations();
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
}
