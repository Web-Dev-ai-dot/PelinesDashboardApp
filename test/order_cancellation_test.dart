import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_detail_screen.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

import 'order_test_data.dart';

import 'package:pelines_admin_app/features/orders/models/order_status_action.dart';
import 'package:pelines_admin_app/features/printing/providers/printing_providers.dart';

void main() {
  for (final source in [
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.ready,
  ]) {
    test(
      'cancel ${source.name}: one PATCH, two GETs, canonical payment retained',
      () async {
        final before = orderDetail(status: source);
        final after = orderDetail(
          status: OrderStatus.cancelled,
          payment: PaymentStatus.paid,
        );
        final repo = _FakeOrdersRepository(
          getResult: after,
          getResults: [before, after],
          patchResult: orderDetail(
            status: OrderStatus.cancelled,
            payment: PaymentStatus.refunded,
          ),
        );
        final c = _container(repo);
        addTearDown(c.dispose);
        await c.read(currentLocationProvider.future);
        await c
            .read(orderMutationProvider(before.id).notifier)
            .cancelOrder(before);
        final result = c.read(orderMutationProvider(before.id));
        expect(result.phase, OrderMutationPhase.success);
        expect(result.canonicalOrder?.paymentStatus, PaymentStatus.paid);
        expect(repo.patchCalls, 1);
        expect(repo.getCalls, 2);
        expect(repo.requestedStatuses, [OrderStatus.cancelled]);
        expect(
          OrderStatusAction.forOrder(source, FulfillmentType.pickup),
          isNot(OrderStatusAction.cancelOrder),
        );
      },
    );
  }
  for (final error in [
    const ApiException(message: 'Refund failed', statusCode: 422),
    _networkError(),
    const ApiException(message: 'Server error', statusCode: 500),
    const ApiException(message: 'Forbidden', statusCode: 403),
  ]) {
    for (final remote in [
      OrderStatus.pending,
      OrderStatus.cancelled,
      OrderStatus.preparing,
    ]) {
      test(
        '${error.statusCode ?? 'timeout'} reconciles ${remote.name} without resend',
        () async {
          final before = orderDetail();
          final after = orderDetail(status: remote);
          final repo = _FakeOrdersRepository(
            getResult: after,
            getResults: [before, after],
            patchError: error,
          );
          final c = _container(repo);
          addTearDown(c.dispose);
          await c.read(currentLocationProvider.future);
          await c
              .read(orderMutationProvider(before.id).notifier)
              .cancelOrder(before);
          final result = c.read(orderMutationProvider(before.id));
          expect(result.canonicalOrder?.status, remote);
          expect(
            result.phase,
            remote == OrderStatus.cancelled
                ? OrderMutationPhase.success
                : OrderMutationPhase.error,
          );
          expect(
            result.message,
            contains(
              remote == OrderStatus.cancelled
                  ? 'Order cancelled'
                  : remote == OrderStatus.pending
                  ? 'try again manually'
                  : 'Order updated elsewhere',
            ),
          );
          expect(repo.patchCalls, 1);
          expect(repo.getCalls, 2);
        },
      );
    }
  }
  for (final patchError in [null, _networkError()]) {
    test(
      'failed final GET is uncertain, including after successful PATCH: $patchError',
      () async {
        final before = orderDetail();
        final repo = _FakeOrdersRepository(
          getResult: before,
          getResults: [before],
          patchResult: orderDetail(status: OrderStatus.cancelled),
          patchError: patchError,
          getError: const ApiException(message: 'GET failed'),
          getErrorCall: 2,
        );
        final c = _container(repo);
        addTearDown(c.dispose);
        await c.read(currentLocationProvider.future);
        await c
            .read(orderMutationProvider(before.id).notifier)
            .cancelOrder(before);
        final result = c.read(orderMutationProvider(before.id));
        expect(result.phase, OrderMutationPhase.error);
        expect(result.message, contains('uncertain'));
        expect(result.canonicalOrder?.status, OrderStatus.pending);
        expect(repo.patchCalls, 1);
        expect(repo.getCalls, 2);
      },
    );
  }
  for (final remote in [
    OrderStatus.delivered,
    OrderStatus.cancelled,
    OrderStatus.confirmed,
  ]) {
    test('preflight adopts remote ${remote.name} with zero PATCH', () async {
      final repo = _FakeOrdersRepository(
        getResult: orderDetail(status: remote),
      );
      final c = _container(repo);
      addTearDown(c.dispose);
      await c.read(currentLocationProvider.future);
      await c
          .read(orderMutationProvider(repo.orderId).notifier)
          .cancelOrder(orderDetail());
      expect(repo.patchCalls, 0);
      expect(
        c.read(orderMutationProvider(repo.orderId)).canonicalOrder?.status,
        remote,
      );
    });
  }
  for (final payment in [
    PaymentStatus.unpaid,
    PaymentStatus.failed,
    PaymentStatus.refunded,
    PaymentStatus.unknown,
  ]) {
    test('preflight rejects canonical ${payment.name}', () async {
      final repo = _FakeOrdersRepository(
        getResult: orderDetail(payment: payment),
      );
      final c = _container(repo);
      addTearDown(c.dispose);
      await c.read(currentLocationProvider.future);
      await c
          .read(orderMutationProvider(repo.orderId).notifier)
          .cancelOrder(orderDetail());
      expect(repo.patchCalls, 0);
      expect(
        c
            .read(orderMutationProvider(repo.orderId))
            .canonicalOrder
            ?.paymentStatus,
        payment,
      );
    });
  }
  test('feature disabled blocks controller before GET or PATCH', () async {
    final repo = _FakeOrdersRepository(getResult: orderDetail());
    final c = ProviderContainer(
      overrides: [
        ordersRepositoryProvider.overrideWithValue(repo),
        orderCancellationEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(c.dispose);
    await c
        .read(orderMutationProvider(repo.orderId).notifier)
        .cancelOrder(orderDetail());
    expect(repo.getCalls, 0);
    expect(repo.patchCalls, 0);
  });
  test('location change blocks PATCH', () async {
    final repo = _FakeOrdersRepository(getResult: orderDetail());
    final c = _container(repo);
    addTearDown(c.dispose);
    await c.read(currentLocationProvider.future);
    (c.read(currentLocationProvider.notifier) as _FakeCurrentLocation).change(
      _location('elsewhere'),
    );
    await c
        .read(orderMutationProvider(repo.orderId).notifier)
        .cancelOrder(orderDetail());
    expect(repo.patchCalls, 0);
  });
  test('double cancel and progression cannot overlap', () async {
    final pending = Completer<OrderDetail>();
    final before = orderDetail();
    final after = orderDetail(status: OrderStatus.cancelled);
    final repo = _FakeOrdersRepository(
      getResult: after,
      getResults: [before, after],
      patchFuture: pending.future,
    );
    final c = _container(repo);
    addTearDown(c.dispose);
    await c.read(currentLocationProvider.future);
    final ctrl = c.read(orderMutationProvider(repo.orderId).notifier);
    final first = ctrl.cancelOrder(before);
    await Future<void>.delayed(Duration.zero);
    await ctrl.cancelOrder(before);
    await ctrl.acceptOrder(before);
    expect(repo.patchCalls, 1);
    pending.complete(after);
    await first;
    expect(repo.patchCalls, 1);
  });
  test(
    'cancel never accesses the printing runtime or creates print jobs',
    () async {
      final before = orderDetail();
      final after = orderDetail(status: OrderStatus.cancelled);
      final repo = _FakeOrdersRepository(
        getResult: after,
        getResults: [before, after],
        patchResult: after,
      );
      var printingAccesses = 0;
      final c = ProviderContainer(
        overrides: [
          ordersRepositoryProvider.overrideWithValue(repo),
          currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
          orderCancellationEnabledProvider.overrideWithValue(true),
          printingRuntimeProvider.overrideWith((ref) {
            printingAccesses++;
            throw StateError('Cancel must not use printing');
          }),
        ],
      );
      addTearDown(c.dispose);
      await c.read(currentLocationProvider.future);
      await c
          .read(orderMutationProvider(before.id).notifier)
          .cancelOrder(before);
      expect(
        c.read(orderMutationProvider(before.id)).phase,
        OrderMutationPhase.success,
      );
      expect(printingAccesses, 0);
    },
  );
  for (final status in [
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.ready,
    OrderStatus.delivered,
    OrderStatus.cancelled,
  ]) {
    testWidgets('Cancel visibility for paid ${status.name}', (tester) async {
      final repo = _FakeOrdersRepository(
        getResult: orderDetail(status: status),
      );
      await _pumpDetail(tester, repo);
      expect(
        find.byKey(const Key('cancel-order-action')),
        status == OrderStatus.cancelled || status == OrderStatus.delivered
            ? findsNothing
            : findsOneWidget,
      );
      if (status == OrderStatus.cancelled) {
        expect(find.byKey(const Key('save-internal-notes')), findsNothing);
      }
    });
  }
  for (final payment in [
    PaymentStatus.unpaid,
    PaymentStatus.failed,
    PaymentStatus.refunded,
    PaymentStatus.unknown,
  ]) {
    testWidgets('no Cancel UI for ${payment.name}', (tester) async {
      await _pumpDetail(
        tester,
        _FakeOrdersRepository(getResult: orderDetail(payment: payment)),
      );
      expect(find.byKey(const Key('cancel-order-action')), findsNothing);
    });
  }
  testWidgets(
    'confirmation identifies order, total and refund; Keep Order sends no PATCH',
    (tester) async {
      final repo = _FakeOrdersRepository(getResult: orderDetail());
      await _pumpDetail(tester, repo);
      await tester.ensureVisible(find.byKey(const Key('cancel-order-action')));
      await tester.tap(find.byKey(const Key('cancel-order-action')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cancel ORD-1048 (\$11.00)?'), findsOneWidget);
      expect(find.textContaining('may initiate a refund'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancel-order-keep')));
      await tester.pumpAndSettle();
      expect(repo.patchCalls, 0);
    },
  );
  testWidgets(
    'confirm cancels, displays refunded and leaves Detail read-only',
    (tester) async {
      final before = orderDetail();
      final after = orderDetail(
        status: OrderStatus.cancelled,
        payment: PaymentStatus.refunded,
      );
      final repo = _FakeOrdersRepository(getResult: before, patchResult: after);
      await _pumpDetail(tester, repo);
      await tester.ensureVisible(find.byKey(const Key('cancel-order-action')));
      await tester.tap(find.byKey(const Key('cancel-order-action')));
      await tester.pumpAndSettle();
      repo.getResults.addAll([before, after]);
      repo.getResult = after;
      await tester.tap(find.byKey(const Key('cancel-order-confirm')));
      await tester.pumpAndSettle();
      expect(repo.patchCalls, 1);
      expect(find.byKey(const Key('cancel-order-action')), findsNothing);
      expect(find.byKey(const Key('order-primary-action')), findsNothing);
      expect(find.byKey(const Key('save-internal-notes')), findsNothing);
      expect(find.text('refunded'), findsOneWidget);
    },
  );
  testWidgets('location changes while confirmation is open: zero PATCH', (
    tester,
  ) async {
    final repo = _FakeOrdersRepository(getResult: orderDetail());
    await _pumpDetail(tester, repo);
    await tester.tap(find.byKey(const Key('cancel-order-action')));
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(
      tester.element(find.byType(OrderDetailScreen)),
    );
    (c.read(currentLocationProvider.notifier) as _FakeCurrentLocation).change(
      _location('other'),
    );
    await tester.tap(find.byKey(const Key('cancel-order-confirm')));
    await tester.pumpAndSettle();
    expect(repo.patchCalls, 0);
  });
  testWidgets(
    'raw canonical payment value remains visible after cancellation',
    (tester) async {
      final order = OrderDetail.fromJson(
        orderJson(status: 'cancelled', payment: 'refund_pending'),
      );
      await _pumpDetail(tester, _FakeOrdersRepository(getResult: order));
      expect(find.text('refund_pending'), findsOneWidget);
      expect(find.text('refunded'), findsNothing);
      expect(find.byKey(const Key('save-internal-notes')), findsNothing);
    },
  );
  testWidgets('production gate hides Cancel on a paid active order', (
    tester,
  ) async {
    final repo = _FakeOrdersRepository(getResult: orderDetail());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ordersRepositoryProvider.overrideWithValue(repo),
          currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
          orderCancellationEnabledProvider.overrideWithValue(false),
        ],
        child: MaterialApp(home: OrderDetailScreen(orderId: repo.orderId)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -1800));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cancel-order-action')), findsNothing);
  });
  test('422 permits only an explicitly requested manual retry', () async {
    final before = orderDetail();
    final repo = _FakeOrdersRepository(
      getResult: before,
      patchError: const ApiException(message: 'Refund failed', statusCode: 422),
    );
    final c = _container(repo);
    addTearDown(c.dispose);
    final sub = c.listen(orderMutationProvider(before.id), (_, _) {});
    addTearDown(sub.close);
    await c.read(currentLocationProvider.future);
    final ctrl = c.read(orderMutationProvider(before.id).notifier);
    await ctrl.cancelOrder(before);
    expect(repo.patchCalls, 1);
    await Future<void>.delayed(Duration.zero);
    expect(repo.patchCalls, 1);
    await ctrl.cancelOrder(
      c.read(orderMutationProvider(before.id)).canonicalOrder!,
    );
    expect(repo.patchCalls, 2);
    expect(repo.getCalls, 4);
  });
  test(
    'reopening detail cannot reuse a cached pre-cancellation order',
    () async {
      final before = orderDetail();
      final after = orderDetail(status: OrderStatus.cancelled);
      final repo = _FakeOrdersRepository(
        getResult: after,
        getResults: [before, before, after],
        patchResult: after,
      );
      final c = _container(repo);
      addTearDown(c.dispose);
      await c.read(currentLocationProvider.future);
      expect(
        (await c.read(orderDetailProvider(before.id).future)).status,
        OrderStatus.pending,
      );
      await c
          .read(orderMutationProvider(before.id).notifier)
          .cancelOrder(before);
      expect(
        (await c.read(orderDetailProvider(before.id).future)).status,
        OrderStatus.cancelled,
      );
      expect(repo.patchCalls, 1);
    },
  );
  test('failed preflight GET sends no PATCH', () async {
    final repo = _FakeOrdersRepository(
      getResult: orderDetail(),
      getError: const ApiException(message: 'Unavailable'),
      getErrorCall: 1,
    );
    final c = _container(repo);
    addTearDown(c.dispose);
    await c.read(currentLocationProvider.future);
    await c
        .read(orderMutationProvider(repo.orderId).notifier)
        .cancelOrder(orderDetail());
    expect(repo.patchCalls, 0);
    expect(repo.getCalls, 1);
  });
}

Future<void> _pumpDetail(
  WidgetTester tester,
  _FakeOrdersRepository repository,
) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ordersRepositoryProvider.overrideWithValue(repository),
        orderCancellationEnabledProvider.overrideWithValue(true),
        currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
      ],
      child: MaterialApp(home: OrderDetailScreen(orderId: repository.orderId)),
    ),
  );
  await tester.pumpAndSettle();
}

ProviderContainer _container(_FakeOrdersRepository repository) =>
    ProviderContainer(
      overrides: [
        ordersRepositoryProvider.overrideWithValue(repository),
        orderCancellationEnabledProvider.overrideWithValue(true),
        currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
      ],
    );

ApiException _networkError() {
  final DioException cause = DioException(
    requestOptions: RequestOptions(path: 'orders/id/status'),
    type: DioExceptionType.receiveTimeout,
  );
  return ApiException(message: 'The Pelines server timed out.', cause: cause);
}

Location _location(String id) => Location(
  id: id,
  name: id,
  slug: id,
  isActive: true,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  isAcceptingOrders: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _FakeCurrentLocation extends CurrentLocationController {
  @override
  Future<Location?> build() async => _location('location-id');

  void change(Location location) => state = AsyncData<Location?>(location);
}

class _FakeOrdersRepository implements OrdersRepository {
  _FakeOrdersRepository({
    this.patchResult,
    this.patchFuture,
    this.patchError,
    required this.getResult,
    List<OrderDetail>? getResults,
    this.getError,
    this.getErrorCall,
  }) : getResults = getResults ?? <OrderDetail>[];

  final OrderDetail? patchResult;
  final Future<OrderDetail>? patchFuture;
  final Object? patchError;
  OrderDetail getResult;
  final List<OrderDetail> getResults;
  final Object? getError;
  final int? getErrorCall;
  int patchCalls = 0;
  int getCalls = 0;
  final List<String> listLocationIds = <String>[];
  final List<OrderStatus> requestedStatuses = <OrderStatus>[];
  String get orderId => getResult.id;

  @override
  Future<OrderDetail> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  }) async {
    patchCalls++;
    requestedStatuses.add(status);
    if (patchError != null) throw patchError!;
    if (patchFuture != null) return patchFuture!;
    return patchResult!;
  }

  @override
  Future<OrderDetail> updateInternalNotes({
    required String orderId,
    required String internalNotes,
  }) => throw UnimplementedError();

  @override
  Future<OrderDetail> getOrderById(String id) async {
    getCalls++;
    if (getError != null && getCalls == getErrorCall) {
      throw getError!;
    }
    if (getResults.isNotEmpty) return getResults.removeAt(0);
    return getResult;
  }

  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async {
    listLocationIds.add(locationId);
    return <OrderSummary>[];
  }
}
