import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../models/profile.dart';

abstract interface class AccountRepository {
  Future<Profile> getMe();
}

class ApiAccountRepository implements AccountRepository {
  ApiAccountRepository(this._client);

  final ApiClient _client;

  @override
  Future<Profile> getMe() async {
    try {
      final Response<dynamic> response = await _client.dio.get<dynamic>('me');
      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid /me response.');
      }
      return Profile.fromJson(data);
    } on DioException catch (error) {
      final int? status = error.response?.statusCode;
      final String message = switch (status) {
        401 => 'Your session is no longer valid. Please sign in again.',
        403 => 'This account is not authorized to use the admin app.',
        _
            when error.type == DioExceptionType.connectionTimeout ||
                error.type == DioExceptionType.receiveTimeout ||
                error.type == DioExceptionType.sendTimeout =>
          'The Pelines server timed out. Please try again.',
        _ when error.type == DioExceptionType.connectionError =>
          'Could not connect to the Pelines server.',
        _ => 'The Pelines server could not load your profile.',
      };
      throw ApiException(message: message, statusCode: status, cause: error);
    } on FormatException catch (error) {
      throw ApiException(
        message: 'The Pelines server returned an invalid profile.',
        cause: error,
      );
    }
  }
}
