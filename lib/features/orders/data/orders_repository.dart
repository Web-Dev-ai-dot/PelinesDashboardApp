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

/// Refund reasons staff may choose; `order_cancelled` is server-only.
enum RefundReason {
  requestedByCustomer('requested_by_customer'),
  duplicate('duplicate'),
  fraudulent('fraudulent'),
  other('other');

  const RefundReason(this.wireValue);
  final String wireValue;
}

/// Kept apart from [OrdersRepository] so existing implementations stay valid.
abstract interface class OrderRefundsRepository {
  /// [idempotencyKey] must be generated once per refund form, never per tap,
  /// so a double-submit or retry of that form cannot refund twice.
  Future<OrderDetail> issueRefund({
    required String orderId,
    required int amountCents,
    required RefundReason reason,
    required String idempotencyKey,
    String? note,
  });

  /// Pulls refunds made outside the app (e.g. the Stripe dashboard).
  Future<OrderDetail> syncRefunds(String orderId);
}

class ApiOrdersRepository implements OrdersRepository, OrderRefundsRepository {
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

  @override
  Future<OrderDetail> issueRefund({
    required String orderId,
    required int amountCents,
    required RefundReason reason,
    required String idempotencyKey,
    String? note,
  }) async {
    final String? trimmedNote = note?.trim();
    try {
      final Response<dynamic> response = await _client.dio.post<dynamic>(
        'orders/$orderId/refunds',
        data: <String, dynamic>{
          'amountCents': amountCents,
          'reason': reason.wireValue,
          if (trimmedNote != null && trimmedNote.isNotEmpty)
            'note': trimmedNote,
        },
        options: Options(
          headers: <String, String>{'Idempotency-Key': idempotencyKey},
        ),
      );
      return _orderFrom(response.data);
    } on DioException catch (error) {
      throw _mapRefundError(error);
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
  Future<OrderDetail> syncRefunds(String orderId) async {
    try {
      final Response<dynamic> response = await _client.dio.post<dynamic>(
        'orders/$orderId/refunds/sync',
      );
      return _orderFrom(response.data);
    } on DioException catch (error) {
      throw _mapRefundError(error);
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

  OrderDetail _orderFrom(Object? data) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid refund response.');
    }
    return OrderDetail.fromJson(data);
  }

  /// Refund rejections carry a human `message` (e.g. the remaining balance).
  ApiException _mapRefundError(DioException error) {
    final int? status = error.response?.statusCode;
    final String? serverMessage = _serverMessage(error.response?.data);
    final String message = switch (status) {
      401 => 'Your session is no longer valid. Please sign in again.',
      403 => 'Administrator access is required.',
      400 || 409 || 422 when serverMessage != null => serverMessage,
      // An API without refund routes also answers 404.
      404 => 'Refunds are not available.',
      _
          when error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.sendTimeout =>
        'The Pelines server timed out. Please try again.',
      _ when error.type == DioExceptionType.connectionError =>
        'Could not connect to the Pelines server.',
      _ => 'Refund failed. Please try again.',
    };
    return ApiException(message: message, statusCode: status, cause: error);
  }

  static String? _serverMessage(Object? data) {
    if (data is! Map<String, dynamic>) return null;
    final Object? message = data['message'];
    if (message is String && message.trim().isNotEmpty) return message.trim();
    if (message is List<dynamic>) {
      final String joined = message
          .whereType<String>()
          .where((String part) => part.trim().isNotEmpty)
          .join(' ');
      return joined.isEmpty ? null : joined;
    }
    return null;
  }

  ApiException _mapDioError(DioException error, {required bool detail}) {
    final int? status = error.response?.statusCode;
    final String message = switch (status) {
      401 => 'The server rejected this request. Please try again.',
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
