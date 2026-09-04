import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../models/menu_models.dart';

abstract interface class MenuRepository {
  Future<List<MenuCategory>> getCategories({
    required String locationSlug,
    required MenuKind kind,
  });
  Future<List<MenuProduct>> getProducts({
    required String locationSlug,
    required String categoryId,
  });
  Future<MenuProduct> getProduct(String productId);
}

class ApiMenuRepository implements MenuRepository {
  ApiMenuRepository(this._client);
  final ApiClient _client;

  @override
  Future<List<MenuCategory>> getCategories({
    required String locationSlug,
    required MenuKind kind,
  }) => _list(
    'categories',
    <String, dynamic>{'kind': kind.name, 'location': locationSlug},
    MenuCategory.fromJson,
    'categories',
  );

  @override
  Future<List<MenuProduct>> getProducts({
    required String locationSlug,
    required String categoryId,
  }) => _list(
    'products',
    <String, dynamic>{'categoryId': categoryId, 'location': locationSlug},
    MenuProduct.fromJson,
    'products',
  );

  @override
  Future<MenuProduct> getProduct(String productId) async {
    try {
      final Response<dynamic> response = await _client.dio.get<dynamic>(
        'products/$productId',
      );
      if (response.data is! Map<String, dynamic>) {
        throw const FormatException('Invalid product.');
      }
      return MenuProduct.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw _error(error, detail: true);
    } on Object catch (error) {
      throw ApiException(
        message: 'The server returned an invalid product.',
        cause: error,
      );
    }
  }

  Future<List<T>> _list<T>(
    String path,
    Map<String, dynamic> query,
    T Function(Map<String, dynamic>) parse,
    String label,
  ) async {
    try {
      final response = await _client.dio.get<dynamic>(
        path,
        queryParameters: query,
      );
      if (response.data is! List<dynamic>) {
        throw const FormatException('Invalid list.');
      }
      return (response.data as List<dynamic>)
          .map((value) => parse(value as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (error) {
      throw _error(error);
    } on Object catch (error) {
      throw ApiException(
        message: 'The server returned invalid $label.',
        cause: error,
      );
    }
  }

  ApiException _error(DioException error, {bool detail = false}) {
    final int? status = error.response?.statusCode;
    final String message = switch (status) {
      401 => 'Your session is no longer valid. Please sign in again.',
      403 => 'Administrator access is required.',
      404 when detail => 'Product no longer available.',
      _
          when error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.sendTimeout =>
        'The Pelines server timed out. Please try again.',
      _ when error.type == DioExceptionType.connectionError =>
        'Could not connect to the Pelines server.',
      _ =>
        detail
            ? 'The product could not be loaded.'
            : 'The menu could not be loaded.',
    };
    return ApiException(message: message, statusCode: status, cause: error);
  }
}
