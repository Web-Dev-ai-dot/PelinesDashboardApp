import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../models/order_models.dart';

abstract interface class OrdersRepository {
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  });
  Future<OrderDetail> getOrderById(String id);
  Future<OrderDetail> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  });
  Future<OrderDetail> updateInternalNotes({
    required String orderId,
    required String internalNotes,
  });
}

class ApiOrdersRepository implements OrdersRepository {
  ApiOrdersRepository(this._client);
  final ApiClient _client;

  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async {
    try {
      final Response<dynamic> response = await _client.dio.get<dynamic>(
        'orders',
        queryParameters: <String, dynamic>{
          'locationId': locationId,
          if (status != null) 'status': status.name,
        },
      );
      if (response.statusCode == 206) {
        throw const ApiException(message: 'Incomplete orders response.');
      }
      final Object? data = response.data;
      if (data is! List<dynamic>) {
        throw const FormatException('Invalid /orders response.');
      }
      return data
          .map((dynamic value) {
            if (value is! Map<String, dynamic>) {
              throw const FormatException('Invalid order.');
            }
            return OrderSummary.fromJson(value);
          })
          .toList(growable: false);
    } on DioException catch (error) {
      throw _mapDioError(error, detail: false);
    } on FormatException catch (error) {
      throw ApiException(
        message: 'The Pelines server returned invalid orders.',
        cause: error,
      );
    } on TypeError catch (error) {
      throw ApiException(
        message: 'The Pelines server returned invalid orders.',
        cause: error,
      );
    }
  }

  @override
  Future<OrderDetail> getOrderById(String id) async {
    try {
      final Response<dynamic> response = await _client.dio.get<dynamic>(
        'orders/$id',
      );
      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid order detail.');
      }
      return OrderDetail.fromJson(data);
    } on DioException catch (error) {
      throw _mapDioError(error, detail: true);
    } on FormatException catch (error) {
      throw ApiException(
        message: 'The Pelines server returned an invalid order.',
        cause: error,
      );
    } on TypeError catch (error) {
      throw ApiException(
        message: 'The Pelines server returned an invalid order.',
        cause: error,
      );
    }
  }

  @override
  Future<OrderDetail> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  }) async {
    try {
      final Response<dynamic> response = await _client.dio.patch<dynamic>(
        'orders/$orderId/status',
        data: <String, dynamic>{'status': status.name},
      );
      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid status update response.');
      }
      return OrderDetail.fromJson(data);
    } on DioException catch (error) {
      throw _mapDioError(error, detail: true);
    } on FormatException catch (error) {
      throw ApiException(
        message: 'The Pelines server returned an invalid order.',
        cause: error,
      );
    } on TypeError catch (error) {
      throw ApiException(
        message: 'The Pelines server returned an invalid order.',
        cause: error,
      );
    }
  }

  @override
  Future<OrderDetail> updateInternalNotes({
    required String orderId,
    required String internalNotes,
  }) async {
    try {
      final Response<dynamic> response = await _client.dio.patch<dynamic>(
        'orders/$orderId/internal-notes',
        data: <String, dynamic>{'internalNotes': internalNotes},
      );
      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid internal notes response.');
      }
      return OrderDetail.fromJson(data);
    } on DioException catch (error) {
      throw _mapDioError(error, detail: true);
    } on FormatException catch (error) {
      throw ApiException(
        message: 'The Pelines server returned an invalid order.',
        cause: error,
      );
    } on TypeError catch (error) {
      throw ApiException(
        message: 'The Pelines server returned an invalid order.',
        cause: error,
      );
    }
  }

  ApiException _mapDioError(DioException error, {required bool detail}) {
    final int? status = error.response?.statusCode;
    final String message = switch (status) {
      401 => 'Your session is no longer valid. Please sign in again.',
      403 => 'Administrator access is required.',
      404 when detail => 'Order no longer available.',
      _
          when error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.sendTimeout =>
        'The Pelines server timed out. Please try again.',
      _ when error.type == DioExceptionType.connectionError =>
        'Could not connect to the Pelines server.',
      _ =>
        detail
            ? 'The order could not be loaded.'
            : 'Orders could not be loaded.',
    };
    return ApiException(message: message, statusCode: status, cause: error);
  }
}
