import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../models/analytics_order.dart';

class AnalyticsDataset {
  AnalyticsDataset({
    required this.locationId,
    required List<AnalyticsOrder> orders,
  }) : orders = List.unmodifiable(orders);

  final String locationId;
  final List<AnalyticsOrder> orders;
  int get loadedCount => orders.length;
  bool get possiblyTruncated => loadedCount >= 2000;
  DateTime? get oldestLoadedCreatedAt => orders.isEmpty
      ? null
      : orders.map((o) => o.createdAt).reduce((a, b) => a.isBefore(b) ? a : b);
}

abstract interface class AnalyticsRepository {
  Future<AnalyticsDataset> getDataset({required String locationId});
}

class ApiAnalyticsRepository implements AnalyticsRepository {
  ApiAnalyticsRepository(this._client);
  final ApiClient _client;

  @override
  Future<AnalyticsDataset> getDataset({required String locationId}) async {
    try {
      final response = await _client.dio.get<dynamic>(
        'orders',
        queryParameters: {'locationId': locationId},
      );
      final data = response.data;
      if (data is! List) throw const FormatException('Invalid orders list.');
      final orders = data.map((row) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('Invalid order.');
        }
        final order = AnalyticsOrder.fromJson(row);
        if (order.locationId != locationId) {
          throw const FormatException('Order belongs to another location.');
        }
        return order;
      }).toList();
      return AnalyticsDataset(locationId: locationId, orders: orders);
    } on DioException catch (error) {
      throw ApiException(
        message: 'Analytics could not be loaded.',
        statusCode: error.response?.statusCode,
        cause: error,
      );
    } on FormatException catch (error) {
      throw ApiException(
        message: 'Invalid analytics orders response.',
        cause: error,
      );
    } on TypeError catch (error) {
      throw ApiException(
        message: 'Invalid analytics orders response.',
        cause: error,
      );
    }
  }
}
