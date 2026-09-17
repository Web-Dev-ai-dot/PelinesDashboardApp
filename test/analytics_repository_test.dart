import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/analytics/data/analytics_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';

import 'order_test_data.dart';

void main() {
  test(
    'one location-only GET preserves items and exact payment states',
    () async {
      final rows = ['paid', 'refunded', 'failed']
          .map(
            (payment) => orderJson(payment: payment)
              ..['items'] = [
                {
                  'id': 'line',
                  'productId': 'product',
                  'productName': 'Taco',
                  'unitPriceCents': 200,
                  'quantity': 3,
                  'lineTotalCents': 600,
                  'modifiers': [],
                },
              ],
          )
          .toList();
      final adapter = Adapter(rows);
      final dataset = await repository(adapter)
          .getDataset(locationId: 'location-id');
      expect(adapter.calls, 1);
      expect(adapter.options!.method, 'GET');
      expect(adapter.options!.path, 'orders');
      expect(adapter.options!.queryParameters, {'locationId': 'location-id'});
      expect(dataset.orders.map((o) => o.paymentStatus), [
        PaymentStatus.paid,
        PaymentStatus.refunded,
        PaymentStatus.failed,
      ]);
      expect(dataset.orders.first.items.single.productId, 'product');
      expect(dataset.orders.first.items.single.quantity, 3);
      expect(dataset.orders.first.items.single.lineTotalCents, 600);
      expect(dataset.loadedCount, 3);
      expect(dataset.possiblyTruncated, isFalse);
      expect(() => dataset.orders.clear(), throwsUnsupportedError);
    },
  );

  for (final count in [0, 1999, 2000]) {
    test('$count records: count, cutoff metadata and oldest date', () async {
      final rows = List.generate(
        count,
        (i) => orderJson()
          ..['createdAt'] = (i == 1 ? DateTime.utc(2025) : DateTime.utc(2026))
              .toIso8601String(),
      );
      final adapter = Adapter(rows);
      final dataset = await repository(adapter)
          .getDataset(locationId: 'location-id');
      expect(adapter.calls, 1);
      expect(dataset.loadedCount, count);
      expect(dataset.possiblyTruncated, count == 2000);
      expect(
        dataset.oldestLoadedCreatedAt,
        count == 0 ? null : DateTime.utc(2025),
      );
    });
  }

  for (final body in <Object?>[
    {},
    [null],
    [orderJson()..remove('totalCents')],
    [orderJson(locationId: 'wrong-location')],
  ]) {
    test(
      'invalid response is an error, never an empty dataset: $body',
      () async {
        expect(
          repository(Adapter(body)).getDataset(locationId: 'location-id'),
          throwsA(isA<ApiException>()),
        );
      },
    );
  }
  for (final code in [401, 403, 500]) {
    test('HTTP $code retains status code', () async {
      expect(
        repository(Adapter({}, status: code))
            .getDataset(locationId: 'location-id'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', code),
        ),
      );
    });
  }
  test('timeout is an error without retry', () async {
    final adapter = Adapter(null, timeout: true);
    await expectLater(
      repository(adapter).getDataset(locationId: 'location-id'),
      throwsA(isA<ApiException>()),
    );
    expect(adapter.calls, 1);
  });
}

ApiAnalyticsRepository repository(Adapter adapter) => ApiAnalyticsRepository(
  ApiClient(
    dio: Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
      ..httpClientAdapter = adapter,
  ),
);

class Adapter implements HttpClientAdapter {
  Adapter(this.body, {this.status = 200, this.timeout = false});
  final Object? body;
  final int status;
  final bool timeout;
  int calls = 0;
  RequestOptions? options;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    this.options = options;
    if (timeout) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
