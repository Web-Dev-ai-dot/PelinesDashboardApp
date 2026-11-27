import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/models/refund_amount.dart';

import 'order_test_data.dart';

Map<String, dynamic> refundJson({
  String id = 'refund-1',
  int amountCents = 500,
  String status = 'succeeded',
  String reason = 'requested_by_customer',
  String source = 'staff',
  String? note,
  String createdAt = '2026-10-28T18:00:00.000Z',
}) => <String, dynamic>{
  'id': id,
  'stripeRefundId': 're_$id',
  'amountCents': amountCents,
  'status': status,
  'reason': reason,
  'note': note,
  'source': source,
  'failureReason': null,
  'createdAt': createdAt,
};

void main() {
  group('OrderDetail.fromJson refunds', () {
    test(
      'older API without refund fields: no refunds and no refund support',
      () {
        final OrderDetail order = OrderDetail.fromJson(orderJson());
        expect(order.refunds, isEmpty);
        expect(order.refundedCents, 0);
        expect(order.refundableCents, isNull);
        expect(order.supportsRefunds, isFalse);
        expect(order.canIssueRefund, isFalse);
        expect(order.isFullyRefunded, isFalse);
      },
    );

    test('parses refunds, refundedCents and refundableCents', () {
      final OrderDetail order = OrderDetail.fromJson(<String, dynamic>{
        ...orderJson(),
        'refunds': <dynamic>[
          refundJson(note: 'Missing salsa'),
          refundJson(
            id: 'refund-2',
            amountCents: 100,
            status: 'requires_action',
            reason: 'order_cancelled',
            source: 'stripe',
          ),
        ],
        'refundedCents': 600,
        'refundableCents': 500,
      });
      expect(order.refunds, hasLength(2));
      expect(order.refunds.first.id, 'refund-1');
      expect(order.refunds.first.amountCents, 500);
      expect(order.refunds.first.status, RefundStatus.succeeded);
      expect(order.refunds.first.reason, 'requested_by_customer');
      expect(order.refunds.first.note, 'Missing salsa');
      expect(order.refunds.first.stripeRefundId, 're_refund-1');
      expect(order.refunds.first.createdAt, DateTime.utc(2026, 10, 28, 18));
      expect(order.refunds.last.status, RefundStatus.requiresAction);
      expect(order.refunds.last.status.isPending, isTrue);
      expect(order.refunds.last.viaStripe, isTrue);
      expect(order.refundedCents, 600);
      expect(order.refundableCents, 500);
      expect(order.canIssueRefund, isTrue);
      expect(order.isFullyRefunded, isFalse);
    });

    test('fully refunded order cannot be refunded again', () {
      final OrderDetail order = OrderDetail.fromJson(<String, dynamic>{
        ...orderJson(payment: 'refunded'),
        'refunds': <dynamic>[refundJson(amountCents: 1100)],
        'refundedCents': 1100,
        'refundableCents': 0,
      });
      expect(order.paymentStatus, PaymentStatus.refunded);
      expect(order.canIssueRefund, isFalse);
      expect(order.isFullyRefunded, isTrue);
    });

    test('tolerates malformed refund data without rejecting the order', () {
      final OrderDetail order = OrderDetail.fromJson(<String, dynamic>{
        ...orderJson(),
        'refunds': <dynamic>[
          'nonsense',
          <String, dynamic>{'id': 'no-amount'},
          <String, dynamic>{
            'id': 'minimal',
            'amountCents': 250,
            'status': 'brand_new_status',
            'createdAt': 'not a date',
          },
        ],
        'refundedCents': '250',
        'refundableCents': null,
      });
      expect(order.refunds, hasLength(1));
      final OrderRefund refund = order.refunds.single;
      expect(refund.status, RefundStatus.unknown);
      expect(refund.status.returnedMoney, isTrue);
      expect(refund.createdAt, isNull);
      expect(refund.reason, 'other');
      expect(refund.source, 'staff');
      expect(order.refundedCents, 0);
      expect(order.refundableCents, isNull);
      expect(order.supportsRefunds, isFalse);
    });

    test('a paid order with refundableCents supports refunds', () {
      final OrderDetail order = OrderDetail.fromJson(<String, dynamic>{
        ...orderJson(),
        'refunds': <dynamic>[],
        'refundedCents': 0,
        'refundableCents': 1100,
      });
      expect(order.supportsRefunds, isTrue);
      expect(order.canIssueRefund, isTrue);
    });

    test('non-list refunds field is treated as no refunds', () {
      final OrderDetail order = OrderDetail.fromJson(<String, dynamic>{
        ...orderJson(),
        'refunds': <String, dynamic>{'id': 'x'},
      });
      expect(order.refunds, isEmpty);
    });

    test('failed and canceled refunds returned no money', () {
      expect(RefundStatus.fromJson('failed').returnedMoney, isFalse);
      expect(RefundStatus.fromJson('canceled').returnedMoney, isFalse);
      expect(RefundStatus.fromJson('pending').isPending, isTrue);
      expect(RefundStatus.fromJson('succeeded').isPending, isFalse);
    });
  });

  group('parseDollarsToCents', () {
    final Map<String, int?> cases = <String, int?>{
      '12': 1200,
      '12.5': 1250,
      '12.50': 1250,
      '0.01': 1,
      '0.1': 10,
      '0': 0,
      '0.00': 0,
      r'$5.96': 596,
      r' $ 5.96 ': 596,
      '  7.05  ': 705,
      '19.99': 1999,
      '0.29': 29,
      '1.005': null,
      '12.345': null,
      '12.': null,
      '.5': null,
      '': null,
      '   ': null,
      '-1': null,
      '+1': null,
      '1,000.00': null,
      '1e3': null,
      'abc': null,
      '12.5.0': null,
      '9999999999999999999999': null,
    };
    cases.forEach((String input, int? expected) {
      test('"$input" -> $expected', () {
        expect(parseDollarsToCents(input), expected);
      });
    });

    test('round-trips every cent value through the prefill format', () {
      for (int cents = 0; cents < 2000; cents++) {
        expect(parseDollarsToCents(centsToDollarInput(cents)), cents);
      }
      expect(centsToDollarInput(596), '5.96');
      expect(centsToDollarInput(1100), '11.00');
      expect(centsToDollarInput(5), '0.05');
    });
  });

  test('idempotency keys are v4 UUIDs and unique per call', () {
    final RegExp uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final Set<String> keys = <String>{
      for (int i = 0; i < 50; i++) newIdempotencyKey(),
    };
    expect(keys, hasLength(50));
    expect(keys.every(uuid.hasMatch), isTrue);
    expect(newIdempotencyKey(Random(1)), newIdempotencyKey(Random(1)));
  });

  group('ApiOrdersRepository refunds', () {
    test(
      'POSTs integer cents, reason, trimmed note and the key header',
      () async {
        final _Adapter adapter = _Adapter(<(int, Object)>[
          (
            200,
            <String, dynamic>{
              ...orderJson(),
              'refunds': <dynamic>[refundJson()],
              'refundedCents': 500,
              'refundableCents': 600,
            },
          ),
        ]);
        final ApiOrdersRepository repository = _repository(adapter);
        final OrderDetail order = await repository.issueRefund(
          orderId: 'order-1',
          amountCents: 500,
          reason: RefundReason.fraudulent,
          idempotencyKey: 'key-1',
          note: '  Missing salsa  ',
        );
        expect(adapter.requests, hasLength(1));
        final RequestOptions request = adapter.requests.single;
        expect(request.method, 'POST');
        expect(request.path, 'orders/order-1/refunds');
        expect(request.headers['Idempotency-Key'], 'key-1');
        expect(request.data, <String, dynamic>{
          'amountCents': 500,
          'reason': 'fraudulent',
          'note': 'Missing salsa',
        });
        expect(
          (request.data as Map<String, dynamic>)['amountCents'],
          isA<int>(),
        );
        expect(adapter.bodies.single, contains('"amountCents":500'));
        expect(order.refundedCents, 500);
        expect(order.refundableCents, 600);
      },
    );

    test('omits a blank note', () async {
      final _Adapter adapter = _Adapter(<(int, Object)>[(200, orderJson())]);
      await _repository(adapter).issueRefund(
        orderId: 'order-1',
        amountCents: 1,
        reason: RefundReason.requestedByCustomer,
        idempotencyKey: 'key-2',
        note: '   ',
      );
      expect(adapter.requests.single.data, <String, dynamic>{
        'amountCents': 1,
        'reason': 'requested_by_customer',
      });
    });

    for (final int status in <int>[400, 409, 422]) {
      test('$status surfaces the API message', () async {
        final _Adapter adapter = _Adapter(<(int, Object)>[
          (
            status,
            <String, dynamic>{
              'statusCode': status,
              'message': r'Refund amount exceeds the remaining refundable balance of $5.96.',
            },
          ),
        ]);
        await expectLater(
          _repository(adapter).issueRefund(
            orderId: 'order-1',
            amountCents: 700,
            reason: RefundReason.other,
            idempotencyKey: 'key-3',
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', status)
                .having(
                  (e) => e.message,
                  'message',
                  r'Refund amount exceeds the remaining refundable balance of $5.96.',
                ),
          ),
        );
      });
    }

    test('validation message arrays are joined', () async {
      final _Adapter adapter = _Adapter(<(int, Object)>[
        (
          400,
          <String, dynamic>{
            'message': <String>[
              'amountCents must be an integer',
              'note too long',
            ],
          },
        ),
      ]);
      await expectLater(
        _repository(adapter).issueRefund(
          orderId: 'order-1',
          amountCents: 1,
          reason: RefundReason.other,
          idempotencyKey: 'key-4',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'amountCents must be an integer note too long',
          ),
        ),
      );
    });

    test(
      'server errors without a message fall back to a generic one',
      () async {
        final _Adapter adapter = _Adapter(<(int, Object)>[(500, 'oops')]);
        await expectLater(
          _repository(adapter).issueRefund(
            orderId: 'order-1',
            amountCents: 1,
            reason: RefundReason.other,
            idempotencyKey: 'key-5',
          ),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              'Refund failed. Please try again.',
            ),
          ),
        );
      },
    );

    test('sync POSTs to the sync endpoint and parses the order', () async {
      final _Adapter adapter = _Adapter(<(int, Object)>[
        (
          200,
          <String, dynamic>{
            ...orderJson(payment: 'refunded'),
            'refunds': <dynamic>[
              refundJson(amountCents: 1100, source: 'stripe'),
            ],
            'refundedCents': 1100,
            'refundableCents': 0,
          },
        ),
      ]);
      final OrderDetail order = await _repository(adapter)
          .syncRefunds('order-1');
      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, 'orders/order-1/refunds/sync');
      expect(order.isFullyRefunded, isTrue);
    });

    test('sync 404 from an older API throws (caller ignores it)', () async {
      final _Adapter adapter = _Adapter(<(int, Object)>[
        (404, <String, dynamic>{'message': 'Cannot POST'}),
      ]);
      await expectLater(
        _repository(adapter).syncRefunds('order-1'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}

ApiOrdersRepository _repository(_Adapter adapter) => ApiOrdersRepository(
  ApiClient(
    dio: Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
      ..httpClientAdapter = adapter,
  ),
);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.responses);
  final List<(int, Object)> responses;
  final List<RequestOptions> requests = <RequestOptions>[];
  final List<String> bodies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      final List<int> bytes = <int>[
        for (final Uint8List chunk in await requestStream.toList()) ...chunk,
      ];
      bodies.add(utf8.decode(bytes));
    }
    final (int status, Object body) = responses[requests.length - 1];
    return ResponseBody.fromString(
      body is String ? body : jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
