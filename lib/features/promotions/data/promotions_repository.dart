import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../models/discount.dart';

abstract interface class PromotionsRepository {
  Future<List<Discount>> getDiscounts();
  Future<Discount> createPromotion(Map<String, dynamic> body);
  Future<Discount> updatePromotion(String id, Map<String, dynamic> patch);
  Future<Discount> setActive(String id, bool isActive);
  Future<void> deletePromotion(String id);
}

class ApiPromotionsRepository implements PromotionsRepository {
  ApiPromotionsRepository(this._client);
  final ApiClient _client;

  @override
  Future<List<Discount>> getDiscounts() async {
    try {
      final Response<dynamic> response = await _client.dio.get<dynamic>(
        'discounts',
      );
      final Object? data = response.data;
      if (data is! List<dynamic>) {
        throw const FormatException('Invalid discounts response.');
      }
      return data
          .map((dynamic item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('Invalid discount item.');
            }
            return Discount.fromJson(item);
          })
          .toList(growable: false);
    } on DioException catch (error) {
      throw _apiError(error, 'load promotions');
    } on FormatException catch (error) {
      throw ApiException(
        message: 'The Pelines server returned invalid promotions.',
        cause: error,
      );
    } on TypeError catch (error) {
      throw ApiException(
        message: 'The Pelines server returned invalid promotions.',
        cause: error,
      );
    }
  }

  @override
  Future<Discount> createPromotion(Map<String, dynamic> body) =>
      _write(() => _client.dio.post<dynamic>('discounts', data: body));

  @override
  Future<Discount> updatePromotion(String id, Map<String, dynamic> patch) =>
      _write(() => _client.dio.patch<dynamic>('discounts/$id', data: patch));

  @override
  Future<Discount> setActive(String id, bool isActive) async {
    return updatePromotion(id, <String, dynamic>{'isActive': isActive});
  }

  @override
  Future<void> deletePromotion(String id) async {
    try {
      // Existing admin DELETE contract returns no entity; accept an empty body.
      await _client.dio.delete<dynamic>('discounts/$id');
    } on DioException catch (error) {
      if (error.response?.statusCode == 409) {
        throw ApiException(
          message: 'This promotion could not be deleted. It may be in use.',
          statusCode: 409,
          cause: error,
        );
      }
      throw _apiError(error, 'delete this promotion');
    }
  }

  Future<Discount> _write(Future<Response<dynamic>> Function() request) async {
    try {
      final Response<dynamic> response = await request();
      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid discount response.');
      }
      return Discount.fromJson(data);
    } on DioException catch (error) {
      throw _apiError(error, 'save this promotion');
    } on FormatException catch (error) {
      throw ApiException(
        message: 'The Pelines server returned an invalid promotion.',
        cause: error,
      );
    } on TypeError catch (error) {
      throw ApiException(
        message: 'The Pelines server returned an invalid promotion.',
        cause: error,
      );
    }
  }

  ApiException _apiError(DioException error, String action) {
    final int? status = error.response?.statusCode;
    final String message = switch (status) {
      401 => 'Your session has expired. Please sign in again.',
      403 => 'Administrator access is required.',
      404 => 'This promotion no longer exists.',
      409 => 'A promotion with this code already exists.',
      _ => switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => 'The Pelines server timed out.',
        DioExceptionType.connectionError =>
          'Could not connect to the Pelines server.',
        _ => 'The Pelines server could not $action.',
      },
    };
    return ApiException(message: message, statusCode: status, cause: error);
  }
}
