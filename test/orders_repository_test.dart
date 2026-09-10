import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';

import 'order_test_data.dart';

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

  for (final OrderStatus status in <OrderStatus>[
    OrderStatus.delivered,
    OrderStatus.cancelled,
  ]) {
    test(
      'GETs exact ${status.name} history query and parses response',
      () async {
        final _Adapter adapter = _Adapter(
          statusCode: 200,
          body: jsonEncode(<Map<String, dynamic>>[
            orderJson(
              status: status.name,
              deliveredAt: status == OrderStatus.delivered
                  ? '2026-09-04T20:00:00.000Z'
                  : null,
            ),
          ]),
        );
        final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
          ..httpClientAdapter = adapter;
        final OrdersRepository repository = ApiOrdersRepository(
          ApiClient(dio: dio),
        );

        final List<OrderSummary> result = await repository.getOrders(
          locationId: 'location-uuid',
          status: status,
        );

        expect(adapter.lastOptions?.method, 'GET');
        expect(adapter.lastOptions?.path, 'orders');
        expect(adapter.lastOptions?.queryParameters, <String, dynamic>{
          'locationId': 'location-uuid',
          'status': status.name,
        });
        expect(adapter.hadRequestBody, isFalse);
        expect(result.single.status, status);
        if (status == OrderStatus.delivered) {
          expect(result.single.deliveredAt, isNotNull);
        }
      },
    );

    test('${status.name} history accepts an empty list', () async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
        ..httpClientAdapter = _Adapter(statusCode: 200, body: '[]');
      final OrdersRepository repository = ApiOrdersRepository(
        ApiClient(dio: dio),
      );
      expect(
        await repository.getOrders(locationId: 'location-id', status: status),
        isEmpty,
      );
    });

    for (final int code in <int>[401, 403]) {
      test('${status.name} history maps $code', () async {
        final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
          ..httpClientAdapter = _Adapter(
            statusCode: code,
            body: jsonEncode(<String, dynamic>{'message': 'error'}),
          );
        final OrdersRepository repository = ApiOrdersRepository(
          ApiClient(dio: dio),
        );
        await expectLater(
          repository.getOrders(locationId: 'location-id', status: status),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', code),
          ),
        );
      });
    }
  }

  test('history maps timeout', () async {
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
      ..httpClientAdapter = _ThrowingAdapter();
    final OrdersRepository repository = ApiOrdersRepository(
      ApiClient(dio: dio),
    );
    await expectLater(
      repository.getOrders(
        locationId: 'location-id',
        status: OrderStatus.delivered,
      ),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
  });

  test('history rejects invalid response', () async {
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
      ..httpClientAdapter = _Adapter(statusCode: 200, body: '{}');
    final OrdersRepository repository = ApiOrdersRepository(
      ApiClient(dio: dio),
    );
    await expectLater(
      repository.getOrders(
        locationId: 'location-id',
        status: OrderStatus.cancelled,
      ),
      throwsA(isA<ApiException>()),
    );
  });

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

  test(
    'PATCHes the exact order UUID/status body and parses its response',
    () async {
      const String id = '11111111-1111-4111-8111-111111111111';
      final _Adapter adapter = _Adapter(
        statusCode: 200,
        body: jsonEncode(orderJson(id: id, status: 'confirmed')),
      );
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
        ..httpClientAdapter = adapter;
      final OrdersRepository repository = ApiOrdersRepository(
        ApiClient(dio: dio),
      );

      final OrderDetail result = await repository.updateOrderStatus(
        orderId: id,
        status: OrderStatus.confirmed,
      );

      expect(adapter.lastOptions?.method, 'PATCH');
      expect(adapter.lastOptions?.path, 'orders/$id/status');
      expect(adapter.lastOptions?.data, <String, dynamic>{
        'status': 'confirmed',
      });
      expect(result.id, id);
      expect(result.status, OrderStatus.confirmed);
    },
  );

  test('PATCHes exact cancellation body and parses its response', () async {
    const String id = '11111111-1111-4111-8111-111111111111';
    final _Adapter adapter = _Adapter(
      statusCode: 200,
      body: jsonEncode(orderJson(id: id, status: 'cancelled')),
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
      ..httpClientAdapter = adapter;
    final OrdersRepository repository = ApiOrdersRepository(
      ApiClient(dio: dio),
    );

    final OrderDetail result = await repository.updateOrderStatus(
      orderId: id,
      status: OrderStatus.cancelled,
    );

    expect(adapter.calls, 1);
    expect(adapter.lastOptions?.method, 'PATCH');
    expect(adapter.lastOptions?.path, 'orders/$id/status');
    expect(adapter.lastOptions?.data, <String, dynamic>{'status': 'cancelled'});
    expect(result.id, id);
    expect(result.status, OrderStatus.cancelled);
  });

  for (final int status in <int>[401, 403, 404]) {
    test('maps status mutation $status to a typed ApiException', () async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
        ..httpClientAdapter = _Adapter(
          statusCode: status,
          body: jsonEncode(<String, dynamic>{'message': 'error'}),
        );
      final OrdersRepository repository = ApiOrdersRepository(
        ApiClient(dio: dio),
      );

      await expectLater(
        repository.updateOrderStatus(
          orderId: '11111111-1111-4111-8111-111111111111',
          status: OrderStatus.confirmed,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.statusCode,
            'statusCode',
            status,
          ),
        ),
      );
    });
  }

  for (final String notes in <String>['Call the customer', '']) {
    test(
      'PATCHes exact internal notes body for ${notes.isEmpty ? 'clear' : 'text'}',
      () async {
        const String id = '11111111-1111-4111-8111-111111111111';
        final _Adapter adapter = _Adapter(
          statusCode: 200,
          body: jsonEncode(orderJson(id: id, internalNotes: notes)),
        );
        final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
          ..httpClientAdapter = adapter;
        final OrdersRepository repository = ApiOrdersRepository(
          ApiClient(dio: dio),
        );

        final OrderDetail result = await repository.updateInternalNotes(
          orderId: id,
          internalNotes: notes,
        );

        expect(adapter.lastOptions?.method, 'PATCH');
        expect(adapter.lastOptions?.path, 'orders/$id/internal-notes');
        expect(adapter.lastOptions?.data, <String, dynamic>{
          'internalNotes': notes,
        });
        expect(result.internalNotes, notes);
      },
    );
  }

  for (final int status in <int>[401, 403, 404]) {
    test('maps internal notes $status to a typed ApiException', () async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
        ..httpClientAdapter = _Adapter(
          statusCode: status,
          body: jsonEncode(<String, dynamic>{'message': 'error'}),
        );
      final OrdersRepository repository = ApiOrdersRepository(
        ApiClient(dio: dio),
      );

      await expectLater(
        repository.updateInternalNotes(
          orderId: 'order-id',
          internalNotes: 'draft',
        ),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', status),
        ),
      );
    });
  }

  test('rejects an invalid internal notes response', () async {
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
      ..httpClientAdapter = _Adapter(statusCode: 200, body: '[]');
    final OrdersRepository repository = ApiOrdersRepository(
      ApiClient(dio: dio),
    );

    await expectLater(
      repository.updateInternalNotes(
        orderId: 'order-id',
        internalNotes: 'draft',
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('maps an internal notes timeout without retrying', () async {
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
      ..httpClientAdapter = _ThrowingAdapter();
    final OrdersRepository repository = ApiOrdersRepository(
      ApiClient(dio: dio),
    );

    await expectLater(
      repository.updateInternalNotes(
        orderId: 'order-id',
        internalNotes: 'draft',
      ),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', isNull)
            .having((e) => e.message, 'message', contains('timed out')),
      ),
    );
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter({required this.statusCode, required this.body});
  final int statusCode;
  final String body;
  int calls = 0;
  RequestOptions? lastOptions;
  bool hadRequestBody = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    lastOptions = options;
    hadRequestBody = requestStream != null;
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

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => throw DioException(
    requestOptions: options,
    type: DioExceptionType.receiveTimeout,
  );

  @override
  void close({bool force = false}) {}
}
