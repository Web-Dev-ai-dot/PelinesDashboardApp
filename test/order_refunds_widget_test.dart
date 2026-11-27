import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_detail_screen.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_refunds.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

import 'order_refunds_test.dart' show refundJson;
import 'order_test_data.dart';

const String _minus = '−';

Map<String, dynamic> _order({
  String payment = 'paid',
  List<Map<String, dynamic>>? refunds,
  int? refundedCents,
  int? refundableCents,
  bool legacyApi = false,
}) => <String, dynamic>{
  ...orderJson(payment: payment),
  'cardBrand': 'visa',
  'cardLast4': '4242',
  // An API without refund routes omits all three fields.
  if (!legacyApi) ...<String, dynamic>{
    'refunds': refunds ?? <dynamic>[],
    'refundedCents': refundedCents ?? 0,
    'refundableCents': refundableCents ?? 1100,
  },
};

Widget _app(Widget home, {List overrides = const [], double scale = 1}) =>
    ProviderScope(
      overrides: [...overrides],
      child: MaterialApp(
        theme: AppTheme.light,
        supportedLocales: AdminLocalizations.supportedLocales,
        localizationsDelegates: const [
          AdminLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ),
    );

Future<void> _pumpSection(
  WidgetTester tester,
  OrderDetail order, {
  OrdersRepository? repository,
  double width = 375,
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _app(
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: OrderRefundSection(order: order),
        ),
      ),
      overrides: [
        if (repository != null)
          ordersRepositoryProvider.overrideWithValue(repository),
      ],
      scale: scale,
    ),
  );
  await tester.pumpAndSettle();
}

/// Real repository over a scripted Dio adapter: proves what goes on the wire.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.responses);
  final List<(int, Object)> responses;
  final List<RequestOptions> requests = <RequestOptions>[];
  Completer<void>? gate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (gate != null) await gate!.future;
    final (int status, Object body) = responses[requests.length - 1];
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiOrdersRepository _repository(_ScriptedAdapter adapter) =>
    ApiOrdersRepository(
      ApiClient(
        dio: Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
          ..httpClientAdapter = adapter,
      ),
    );

Finder _submit() => find.byKey(const Key('refund-submit'));

bool _submitEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_submit()).onPressed != null;

Future<void> _openPartial(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('refund-issue')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('refund-mode-partial')));
  await tester.pumpAndSettle();
}

Future<void> _enterAmount(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(const Key('refund-amount')), value);
  await tester.pump();
}

String _hint(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('refund-amount-hint'))).data!;

final _location = Location(
  id: 'location-id',
  name: 'Troutdale',
  slug: 'troutdale',
  isActive: true,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  isAcceptingOrders: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _Current extends CurrentLocationController {
  @override
  Future<Location?> build() async => _location;
}

class _SyncingRepo implements OrdersRepository, OrderRefundsRepository {
  _SyncingRepo(this.json, {this.syncFails = false});
  Map<String, dynamic> json;
  final bool syncFails;
  int syncs = 0;
  int gets = 0;

  @override
  Future<OrderDetail> getOrderById(String id) async {
    gets++;
    return OrderDetail.fromJson(json);
  }

  @override
  Future<OrderDetail> syncRefunds(String orderId) async {
    syncs++;
    if (syncFails) throw Exception('404');
    json = <String, dynamic>{
      ...json,
      'refunds': <dynamic>[refundJson(amountCents: 300, source: 'stripe')],
      'refundedCents': 300,
      'refundableCents': 800,
    };
    return OrderDetail.fromJson(json);
  }

  @override
  Future<OrderDetail> issueRefund({
    required String orderId,
    required int amountCents,
    required RefundReason reason,
    required String idempotencyKey,
    String? note,
  }) async {
    refundCalls++;
    final int refunded = (json['refundedCents'] as int) + amountCents;
    json = <String, dynamic>{
      ...json,
      'refunds': <dynamic>[
        ...json['refunds'] as List<dynamic>,
        refundJson(id: 'refund-$refundCalls', amountCents: amountCents),
      ],
      'refundedCents': refunded,
      'refundableCents': (json['totalCents'] as int) - refunded,
    };
    return OrderDetail.fromJson(json);
  }

  int refundCalls = 0;

  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async => <OrderSummary>[];

  @override
  Future<OrderDetail> updateInternalNotes({
    required String orderId,
    required String internalNotes,
  }) => throw UnimplementedError();

  @override
  Future<OrderDetail> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  }) => throw UnimplementedError();
}

void main() {
  group('refund section', () {
    testWidgets('(a) paid without refunds shows only Issue Refund', (
      tester,
    ) async {
      await _pumpSection(tester, OrderDetail.fromJson(_order()));
      expect(find.text('Issue Refund'), findsOneWidget);
      expect(find.byKey(const Key('refund-badge')), findsNothing);
      expect(find.text('Refunded'), findsNothing);
      expect(find.text('REFUND HISTORY'), findsNothing);
    });

    testWidgets('(b) partial refund: badge, totals, history, another refund', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        OrderDetail.fromJson(
          _order(
            refunds: <Map<String, dynamic>>[
              refundJson(id: 'old', amountCents: 200, note: 'Missing salsa'),
              refundJson(
                id: 'failed',
                amountCents: 150,
                status: 'failed',
                createdAt: '2026-10-29T18:00:00.000Z',
              ),
              refundJson(
                id: 'new',
                amountCents: 300,
                status: 'pending',
                reason: 'duplicate',
                source: 'stripe',
                createdAt: '2026-10-30T18:00:00.000Z',
              ),
            ],
            refundedCents: 500,
            refundableCents: 600,
          ),
        ),
      );
      expect(find.text('Partially Refunded'), findsOneWidget);
      expect(find.text('Fully Refunded'), findsNothing);
      expect(find.text('Refunded'), findsOneWidget);
      expect(find.text('$_minus\$5.00'), findsOneWidget);
      expect(find.text('Remaining refundable'), findsOneWidget);
      expect(find.text(r'$6.00'), findsOneWidget);
      expect(find.text('Issue Another Refund'), findsOneWidget);
      expect(find.text('Issue Refund'), findsNothing);
      expect(find.text('REFUND HISTORY'), findsOneWidget);

      // Newest first.
      final double newY = tester
          .getTopLeft(find.byKey(const Key('refund-row-new')))
          .dy;
      final double failedY = tester
          .getTopLeft(find.byKey(const Key('refund-row-failed')))
          .dy;
      final double oldY = tester
          .getTopLeft(find.byKey(const Key('refund-row-old')))
          .dy;
      expect(newY, lessThan(failedY));
      expect(failedY, lessThan(oldY));

      expect(
        find.text('• Oct 30, 2026 • Duplicate • via Stripe'),
        findsOneWidget,
      );
      expect(
        find.text('• Oct 28, 2026 • Requested by customer'),
        findsOneWidget,
      );
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      final Text failedAmount = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('refund-row-failed')),
          matching: find.text('$_minus\$1.50'),
        ),
      );
      expect(failedAmount.style?.decoration, TextDecoration.lineThrough);
      final Text note = tester.widget<Text>(find.text('“Missing salsa”'));
      expect(note.style?.fontStyle, FontStyle.italic);
      expect(tester.takeException(), isNull);
    });

    testWidgets('(c) fully refunded: no button, Fully Refunded', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        OrderDetail.fromJson(
          _order(
            payment: 'refunded',
            refunds: <Map<String, dynamic>>[
              refundJson(
                amountCents: 1100,
                reason: 'order_cancelled',
                source: 'cancel',
              ),
            ],
            refundedCents: 1100,
            refundableCents: 0,
          ),
        ),
      );
      expect(find.text('Fully Refunded'), findsOneWidget);
      expect(find.text('Partially Refunded'), findsNothing);
      expect(find.text('$_minus\$11.00'), findsNWidgets(2));
      expect(find.text('Remaining refundable'), findsNothing);
      expect(find.byKey(const Key('refund-issue')), findsNothing);
      expect(find.text('• Oct 28, 2026 • Order cancelled'), findsOneWidget);
    });

    testWidgets('(e) paid order from an API without refunds shows nothing', (
      tester,
    ) async {
      await _pumpSection(tester, OrderDetail.fromJson(_order(legacyApi: true)));
      expect(find.byKey(const Key('refund-section')), findsNothing);
      expect(find.byKey(const Key('refund-issue')), findsNothing);
      expect(find.text('Issue Refund'), findsNothing);
    });

    testWidgets('(d) unpaid order shows nothing', (tester) async {
      await _pumpSection(
        tester,
        OrderDetail.fromJson(_order(payment: 'unpaid')),
      );
      expect(find.byKey(const Key('refund-section')), findsNothing);
      expect(find.byKey(const Key('refund-issue')), findsNothing);
    });

    testWidgets('Spanish labels and narrow 2x text do not overflow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('es'),
            supportedLocales: AdminLocalizations.supportedLocales,
            localizationsDelegates: const [
              AdminLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: OrderRefundSection(
                  order: OrderDetail.fromJson(
                    _order(
                      refunds: <Map<String, dynamic>>[
                        refundJson(
                          reason: 'duplicate',
                          source: 'stripe',
                          status: 'pending',
                        ),
                      ],
                      refundedCents: 500,
                      refundableCents: 600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reembolsado parcialmente'), findsOneWidget);
      expect(find.text('Emitir otro reembolso'), findsOneWidget);
      expect(find.textContaining('Duplicado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('refund sheet', () {
    testWidgets('validates amounts and keeps submit disabled while invalid', (
      tester,
    ) async {
      final _ScriptedAdapter adapter = _ScriptedAdapter(<(int, Object)>[]);
      await _pumpSection(
        tester,
        OrderDetail.fromJson(_order()),
        repository: _repository(adapter),
      );
      await tester.tap(find.byKey(const Key('refund-issue')));
      await tester.pumpAndSettle();

      expect(find.text('Refund Payment'), findsOneWidget);
      expect(find.text('Order ORD-1048 · Visa •••• 4242'), findsOneWidget);
      expect(_hint(tester), r'Remaining refundable: $11.00');
      // Full mode: amount locked to the remaining balance.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('refund-amount')))
            .enabled,
        isFalse,
      );
      expect(find.text(r'Process Refund ($11.00)'), findsOneWidget);
      expect(_submitEnabled(tester), isTrue);

      await tester.tap(find.byKey(const Key('refund-mode-partial')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('refund-amount')))
            .enabled,
        isTrue,
      );

      await _enterAmount(tester, '12.345');
      expect(_hint(tester), 'Enter an amount like 12.50');
      expect(_submitEnabled(tester), isFalse);

      await _enterAmount(tester, '0');
      expect(_hint(tester), r'Amount must be at least $0.01');
      expect(_submitEnabled(tester), isFalse);

      await _enterAmount(tester, '11.01');
      expect(_hint(tester), r'Max refundable is $11.00');
      expect(_submitEnabled(tester), isFalse);

      await _enterAmount(tester, '');
      expect(_submitEnabled(tester), isFalse);

      await _enterAmount(tester, '12.5');
      expect(_submitEnabled(tester), isFalse);

      await _enterAmount(tester, '5.5');
      expect(_hint(tester), r'Remaining refundable: $11.00');
      expect(find.text(r'Process Refund ($5.50)'), findsOneWidget);
      expect(_submitEnabled(tester), isTrue);

      // Fraud hint.
      expect(find.byKey(const Key('refund-fraud-hint')), findsNothing);
      await tester.tap(find.byKey(const Key('refund-reason')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fraudulent').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Stripe will also block this card from future payments.'),
        findsOneWidget,
      );

      expect(adapter.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'double tap sends ONE request; retry after an error reuses the key',
      (tester) async {
        final _ScriptedAdapter adapter = _ScriptedAdapter(<(int, Object)>[
          (
            422,
            <String, dynamic>{
              'statusCode': 422,
              'message': r'Refund amount exceeds the remaining refundable balance of $5.96.',
            },
          ),
          (
            200,
            _order(
              refunds: <Map<String, dynamic>>[refundJson(amountCents: 500)],
              refundedCents: 500,
              refundableCents: 600,
            ),
          ),
        ]);
        await _pumpSection(
          tester,
          OrderDetail.fromJson(_order()),
          repository: _repository(adapter),
        );
        await _openPartial(tester);
        await _enterAmount(tester, '5');
        await tester.enterText(find.byKey(const Key('refund-note')), ' Late ');
        await tester.pump();

        adapter.gate = Completer<void>();
        await tester.ensureVisible(_submit());
        await tester.pumpAndSettle();
        await tester.tap(_submit());
        await tester.tap(_submit(), warnIfMissed: false);
        // Let Dio's interceptor chain reach the adapter.
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(adapter.requests, hasLength(1));
        expect(find.text('Processing…'), findsOneWidget);
        expect(_submitEnabled(tester), isFalse);
        expect(
          tester
              .widget<OutlinedButton>(find.byKey(const Key('refund-cancel')))
              .onPressed,
          isNull,
        );

        // Not dismissible while in flight: back / barrier dismissal
        // (both route through maybePop) are ignored.
        final NavigatorState navigator = tester.state<NavigatorState>(
          find.byType(Navigator),
        );
        await navigator.maybePop();
        await tester.pump();
        expect(find.byKey(const Key('refund-sheet')), findsOneWidget);

        adapter.gate!.complete();
        adapter.gate = null;
        await tester.pumpAndSettle();
        expect(adapter.requests, hasLength(1));
        expect(
          find.text(
            r'Refund amount exceeds the remaining refundable balance of $5.96.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('refund-sheet')), findsOneWidget);
        expect(_submitEnabled(tester), isTrue);

        await tester.ensureVisible(_submit());
        await tester.pumpAndSettle();
        await tester.tap(_submit());
        await tester.pumpAndSettle();
        expect(adapter.requests, hasLength(2));
        final String firstKey =
            adapter.requests[0].headers['Idempotency-Key'] as String;
        expect(firstKey, isNotEmpty);
        expect(adapter.requests[1].headers['Idempotency-Key'], firstKey);
        for (final RequestOptions request in adapter.requests) {
          expect(request.method, 'POST');
          expect(request.path, 'orders/${orderJson()['id']}/refunds');
          expect(request.data, <String, dynamic>{
            'amountCents': 500,
            'reason': 'requested_by_customer',
            'note': 'Late',
          });
        }

        expect(find.byKey(const Key('refund-sheet')), findsNothing);
        expect(find.text(r'Refunded $5.00'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a newly opened sheet gets a new key', (tester) async {
      final _ScriptedAdapter adapter = _ScriptedAdapter(<(int, Object)>[
        (
          422,
          <String, dynamic>{'message': 'Only paid orders can be refunded.'},
        ),
        (
          422,
          <String, dynamic>{'message': 'Only paid orders can be refunded.'},
        ),
      ]);
      await _pumpSection(
        tester,
        OrderDetail.fromJson(_order()),
        repository: _repository(adapter),
      );
      for (int i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const Key('refund-issue')));
        await tester.pumpAndSettle();
        await tester.tap(_submit());
        await tester.pumpAndSettle();
        expect(find.text('Only paid orders can be refunded.'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('refund-cancel')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('refund-cancel')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('refund-sheet')), findsNothing);
      }
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests[0].headers['Idempotency-Key'],
        isNot(adapter.requests[1].headers['Idempotency-Key']),
      );
      expect(adapter.requests[0].data['amountCents'], 1100);
    });

    testWidgets('scrolls with the keyboard open at 375pt', (tester) async {
      final _ScriptedAdapter adapter = _ScriptedAdapter(<(int, Object)>[]);
      await _pumpSection(
        tester,
        OrderDetail.fromJson(_order()),
        repository: _repository(adapter),
        width: 375,
        scale: 1.5,
      );
      await _openPartial(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(_submit());
      await tester.pumpAndSettle();
      expect(_submit().hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('order detail screen', () {
    Future<void> mount(WidgetTester tester, _SyncingRepo repo) async {
      await tester.binding.setSurfaceSize(const Size(375, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          OrderDetailScreen(orderId: repo.json['id'] as String),
          overrides: [
            ordersRepositoryProvider.overrideWithValue(repo),
            currentLocationProvider.overrideWith(_Current.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('syncs Stripe refunds once on open, then refreshes', (
      tester,
    ) async {
      final _SyncingRepo repo = _SyncingRepo(
        _order()..['status'] = 'confirmed',
      );
      await mount(tester, repo);
      expect(repo.syncs, 1);
      expect(repo.gets, greaterThanOrEqualTo(2));
      await tester.scrollUntilVisible(
        find.text('Partially Refunded'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Partially Refunded'), findsOneWidget);
      expect(find.text('Issue Another Refund'), findsOneWidget);
      expect(
        find.text('• Oct 28, 2026 • Requested by customer • via Stripe'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(repo.syncs, 1);
    });

    testWidgets('sync errors are ignored', (tester) async {
      final _SyncingRepo repo = _SyncingRepo(
        _order()..['status'] = 'confirmed',
        syncFails: true,
      );
      await mount(tester, repo);
      expect(repo.syncs, 1);
      await tester.scrollUntilVisible(
        find.text('Issue Refund'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Issue Refund'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('API without refunds: no sync and no refund UI', (
      tester,
    ) async {
      final _SyncingRepo repo = _SyncingRepo(
        _order(legacyApi: true)..['status'] = 'confirmed',
      );
      await mount(tester, repo);
      expect(repo.syncs, 0);
      expect(find.byKey(const Key('detail-paid-card')), findsOneWidget);
      expect(find.byKey(const Key('refund-section')), findsNothing);
      expect(find.text('Issue Refund'), findsNothing);
    });

    testWidgets('a successful refund updates the open detail', (tester) async {
      final _SyncingRepo repo = _SyncingRepo(
        _order()..['status'] = 'confirmed',
        syncFails: true,
      );
      await mount(tester, repo);
      final int getsBefore = repo.gets;
      await tester.scrollUntilVisible(
        find.byKey(const Key('refund-issue')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const Key('refund-issue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('refund-issue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('refund-mode-partial')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('refund-amount')), '4');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('refund-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('refund-submit')));
      await tester.pumpAndSettle();

      expect(repo.refundCalls, 1);
      expect(find.byKey(const Key('refund-sheet')), findsNothing);
      expect(find.text(r'Refunded $4.00'), findsOneWidget);
      expect(repo.gets, greaterThan(getsBefore));
      expect(find.text('Partially Refunded'), findsOneWidget);
      expect(find.text('Issue Another Refund'), findsOneWidget);
      expect(find.text(r'$7.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no sync for unpaid orders', (tester) async {
      final _SyncingRepo repo = _SyncingRepo(_order(payment: 'unpaid'));
      await mount(tester, repo);
      expect(repo.syncs, 0);
    });
  });
}
