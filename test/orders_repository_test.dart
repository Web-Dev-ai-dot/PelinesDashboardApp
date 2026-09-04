import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';

void main() {
  test(
    'sends the backend location UUID as locationId and parses empty list',
    () async {
      final _Adapter adapter = _Adapter(statusCode: 200, body: '[]');
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
        ..httpClientAdapter = adapter;
      final OrdersRepository repository = ApiOrdersRepository(
        ApiClient(dio: dio),
      );

      expect(await repository.getOrders(locationId: 'location-uuid'), isEmpty);
      expect(adapter.lastOptions?.path, 'orders');
      expect(adapter.lastOptions?.queryParameters, <String, dynamic>{
        'locationId': 'location-uuid',
      });
    },
  );

  test('maps detail 404 to a typed ApiException', () async {
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
      ..httpClientAdapter = _Adapter(
        statusCode: 404,
        body: jsonEncode(<String, dynamic>{'message': 'Not Found'}),
      );
    final OrdersRepository repository = ApiOrdersRepository(
      ApiClient(dio: dio),
    );

    await expectLater(
      repository.getOrderById('order-uuid'),
      throwsA(
        isA<ApiException>().having(
          (ApiException e) => e.statusCode,
          'statusCode',
          404,
        ),
      ),
    );
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter({required this.statusCode, required this.body});
  final int statusCode;
  final String body;
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
