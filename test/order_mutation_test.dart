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

void main() {
  test(
    'success uses PATCH response, reconciles detail, and refreshes Today',
    () async {
      final _FakeOrdersRepository repository = _FakeOrdersRepository(
        patchResult: orderDetail(status: OrderStatus.confirmed),
        getResult: orderDetail(status: OrderStatus.confirmed),
      );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);
      final subscription = container.listen(
        orderMutationProvider(repository.orderId),
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container
          .read(orderMutationProvider(repository.orderId).notifier)
          .acceptOrder(orderDetail());

      final OrderMutationState state = container.read(
        orderMutationProvider(repository.orderId),
      );
      expect(state.phase, OrderMutationPhase.success);
      expect(state.canonicalOrder?.status, OrderStatus.confirmed);
      expect(repository.patchCalls, 1);
      expect(repository.getCalls, 1);
      expect(repository.listLocationIds, <String>['location-id']);
    },
  );

  test('submitting blocks a second tap', () async {
    final Completer<OrderDetail> patch = Completer<OrderDetail>();
    final _FakeOrdersRepository repository = _FakeOrdersRepository(
      patchFuture: patch.future,
      getResult: orderDetail(status: OrderStatus.confirmed),
    );
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    final subscription = container.listen(
      orderMutationProvider(repository.orderId),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final OrderMutationController controller = container.read(
      orderMutationProvider(repository.orderId).notifier,
    );

    final Future<void> first = controller.acceptOrder(orderDetail());
    final Future<void> second = controller.acceptOrder(orderDetail());
    expect(
      container.read(orderMutationProvider(repository.orderId)).isBusy,
      isTrue,
    );
    expect(repository.patchCalls, 1);
    patch.complete(orderDetail(status: OrderStatus.confirmed));
    await Future.wait(<Future<void>>[first, second]);
    expect(repository.patchCalls, 1);
  });

  for (final PaymentStatus payment in <PaymentStatus>[
    PaymentStatus.failed,
    PaymentStatus.unpaid,
    PaymentStatus.refunded,
    PaymentStatus.unknown,
  ]) {
    test('${payment.name} payment blocks status PATCH in controller', () async {
      final OrderDetail invalid = orderDetail(payment: payment);
      final _FakeOrdersRepository repository = _FakeOrdersRepository(
        patchResult: orderDetail(status: OrderStatus.confirmed),
        getResult: invalid,
      );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      final subscription = container.listen(
        orderMutationProvider(repository.orderId),
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container
          .read(orderMutationProvider(repository.orderId).notifier)
          .acceptOrder(invalid);

      expect(repository.patchCalls, 0);
      expect(
        container.read(orderMutationProvider(repository.orderId)).message,
        contains('payment is not marked as paid'),
      );
    });
  }

  test('non-network PATCH error remains visible and retryable', () async {
    final _FakeOrdersRepository repository = _FakeOrdersRepository(
      patchError: const ApiException(
        message: 'Administrator access is required.',
        statusCode: 403,
      ),
      getResult: orderDetail(),
    );
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    final subscription = container.listen(
      orderMutationProvider(repository.orderId),
      (_, _) {},
    );
    addTearDown(subscription.close);

    await container
        .read(orderMutationProvider(repository.orderId).notifier)
        .acceptOrder(orderDetail());

    final OrderMutationState state = container.read(
      orderMutationProvider(repository.orderId),
    );
    expect(state.phase, OrderMutationPhase.error);
    expect(state.canonicalOrder?.status, OrderStatus.pending);
    expect(state.message, contains('Administrator'));
    expect(repository.getCalls, 0);
  });

  for (final (OrderStatus serverStatus, OrderMutationPhase phase)
      in <(OrderStatus, OrderMutationPhase)>[
        (OrderStatus.confirmed, OrderMutationPhase.success),
        (OrderStatus.pending, OrderMutationPhase.error),
        (OrderStatus.preparing, OrderMutationPhase.error),
      ]) {
    test('ambiguous network result adopts ${serverStatus.name}', () async {
      final _FakeOrdersRepository repository = _FakeOrdersRepository(
        patchError: _networkError(),
        getResult: orderDetail(status: serverStatus),
      );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);
      final subscription = container.listen(
        orderMutationProvider(repository.orderId),
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container
          .read(orderMutationProvider(repository.orderId).notifier)
          .acceptOrder(orderDetail());

      final OrderMutationState state = container.read(
        orderMutationProvider(repository.orderId),
      );
      expect(state.phase, phase);
      expect(state.canonicalOrder?.status, serverStatus);
      expect(repository.patchCalls, 1);
      expect(repository.getCalls, 1);
      if (serverStatus == OrderStatus.pending) {
        expect(state.message, contains('try again'));
      } else if (serverStatus == OrderStatus.preparing) {
        expect(state.message, 'Order status changed on the server.');
      }
    });
  }

  test(
    'location change during mutation refreshes only the new location',
    () async {
      final Completer<OrderDetail> patch = Completer<OrderDetail>();
      final _FakeOrdersRepository repository = _FakeOrdersRepository(
        patchFuture: patch.future,
        getResult: orderDetail(status: OrderStatus.confirmed),
      );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);
      final subscription = container.listen(
        orderMutationProvider(repository.orderId),
        (_, _) {},
      );
      addTearDown(subscription.close);
      final Future<void> mutation = container
          .read(orderMutationProvider(repository.orderId).notifier)
          .acceptOrder(orderDetail());
      final _FakeCurrentLocation current = container.read(
        currentLocationProvider.notifier,
      ) as _FakeCurrentLocation;
      current.change(_location('second-location'));
      await Future<void>.delayed(Duration.zero);
      patch.complete(orderDetail(status: OrderStatus.confirmed));
      await mutation;

      expect(repository.listLocationIds, <String>['second-location']);
    },
  );

  test(
    'terminal success reconciles delivered timestamp and refreshes Today',
    () async {
      final DateTime deliveredAt = DateTime.parse('2026-09-04T19:00:00Z');
      final _FakeOrdersRepository repository = _FakeOrdersRepository(
        patchResult: orderDetail(
          status: OrderStatus.delivered,
          deliveredAt: deliveredAt,
        ),
        getResult: orderDetail(
          status: OrderStatus.delivered,
          deliveredAt: deliveredAt,
        ),
      );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);
      final subscription = container.listen(
        orderMutationProvider(repository.orderId),
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container
          .read(orderMutationProvider(repository.orderId).notifier)
          .markOrderCompleted(orderDetail(status: OrderStatus.ready));

      final OrderMutationState state = container.read(
        orderMutationProvider(repository.orderId),
      );
      expect(state.phase, OrderMutationPhase.success);
      expect(state.canonicalOrder?.status, OrderStatus.delivered);
      expect(state.canonicalOrder?.deliveredAt, deliveredAt);
      expect(repository.patchCalls, 1);
      expect(repository.listLocationIds, <String>['location-id']);
    },
  );

  for (final (OrderStatus serverStatus, OrderMutationPhase phase, bool retry)
      in <(OrderStatus, OrderMutationPhase, bool)>[
        (OrderStatus.delivered, OrderMutationPhase.success, false),
        (OrderStatus.ready, OrderMutationPhase.error, true),
        (OrderStatus.cancelled, OrderMutationPhase.error, false),
      ]) {
    test(
      'terminal timeout adopts ${serverStatus.name} without retrying PATCH',
      () async {
        final _FakeOrdersRepository repository = _FakeOrdersRepository(
          patchError: _networkError(),
          getResult: orderDetail(
            status: serverStatus,
            deliveredAt: serverStatus == OrderStatus.delivered
                ? DateTime.parse('2026-09-04T19:00:00Z')
                : null,
          ),
        );
        final ProviderContainer container = _container(repository);
        addTearDown(container.dispose);
        await container.read(currentLocationProvider.future);
        final subscription = container.listen(
          orderMutationProvider(repository.orderId),
          (_, _) {},
        );
        addTearDown(subscription.close);

        await container
            .read(orderMutationProvider(repository.orderId).notifier)
            .markOrderCompleted(orderDetail(status: OrderStatus.ready));

        final OrderMutationState state = container.read(
          orderMutationProvider(repository.orderId),
        );
        expect(state.phase, phase);
        expect(state.canonicalOrder?.status, serverStatus);
        expect(state.terminalRetryAllowed, retry);
        expect(repository.patchCalls, 1);
        expect(repository.getCalls, 1);
      },
    );
  }

  testWidgets(
    'detail shows contextual action and disables it while submitting',
    (WidgetTester tester) async {
      final Completer<OrderDetail> patch = Completer<OrderDetail>();
      final _FakeOrdersRepository repository = _FakeOrdersRepository(
        patchFuture: patch.future,
        getResult: orderDetail(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ordersRepositoryProvider.overrideWithValue(repository),
            currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
          ],
          child: const MaterialApp(
            home: OrderDetailScreen(
              orderId: '11111111-1111-4111-8111-111111111111',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('order-primary-action')),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Accept order'), findsOneWidget);
      await tester.tap(find.byKey(const Key('order-primary-action')));
      await tester.pump();
      final FilledButton button = tester.widget<FilledButton>(
        find.byKey(const Key('order-primary-action')),
      );
      expect(button.onPressed, isNull);
      expect(find.text('Accepting...'), findsOneWidget);
      expect(repository.patchCalls, 1);

      patch.complete(orderDetail(status: OrderStatus.confirmed));
      await tester.pumpAndSettle();
      expect(repository.patchCalls, 1);
    },
  );

  for (final (FulfillmentType fulfillment, String label)
      in <(FulfillmentType, String)>[
        (FulfillmentType.pickup, 'Mark picked up'),
        (FulfillmentType.delivery, 'Mark delivered'),
      ]) {
    testWidgets(
      'ready ${fulfillment.name} confirms before one terminal PATCH',
      (WidgetTester tester) async {
        final DateTime deliveredAt = DateTime.parse('2026-09-04T19:00:00Z');
        final _FakeOrdersRepository repository = _FakeOrdersRepository(
          patchResult: orderDetail(
            status: OrderStatus.delivered,
            fulfillment: fulfillment,
            deliveredAt: deliveredAt,
          ),
          getResult: orderDetail(
            status: OrderStatus.ready,
            fulfillment: fulfillment,
          ),
        );
        await _pumpDetail(tester, repository);
        await tester.scrollUntilVisible(
          find.byKey(const Key('order-primary-action')),
          500,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(
          find.byKey(const Key('order-primary-action')),
        );
        await tester.pumpAndSettle();
        expect(find.text(label), findsOneWidget);

        await tester.tap(find.byKey(const Key('order-primary-action')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('completion-confirm')), findsOneWidget);
        expect(repository.patchCalls, 0);

        await tester.tap(find.byKey(const Key('completion-cancel')));
        await tester.pumpAndSettle();
        expect(repository.patchCalls, 0);

        await tester.ensureVisible(
          find.byKey(const Key('order-primary-action')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('order-primary-action')));
        await tester.pumpAndSettle();
        repository.getResult = orderDetail(
          status: OrderStatus.delivered,
          fulfillment: fulfillment,
          deliveredAt: deliveredAt,
        );
        await tester.tap(find.byKey(const Key('completion-confirm')));
        await tester.pumpAndSettle();
        expect(repository.patchCalls, 1);
      },
    );
  }

  testWidgets(
    'terminal action is absent outside ready or for unknown fulfillment',
    (WidgetTester tester) async {
      for (final OrderDetail detail in <OrderDetail>[
        orderDetail(status: OrderStatus.preparing),
        orderDetail(
          status: OrderStatus.ready,
          fulfillment: FulfillmentType.unknown,
        ),
        orderDetail(status: OrderStatus.delivered),
      ]) {
        final _FakeOrdersRepository repository = _FakeOrdersRepository(
          patchResult: detail,
          getResult: detail,
        );
        await _pumpDetail(tester, repository);
        expect(find.text('Mark picked up'), findsNothing);
        expect(find.text('Mark delivered'), findsNothing);
      }
    },
  );

  for (final PaymentStatus payment in <PaymentStatus>[
    PaymentStatus.failed,
    PaymentStatus.unpaid,
    PaymentStatus.refunded,
    PaymentStatus.unknown,
  ]) {
    testWidgets('direct detail blocks actions for ${payment.name} payment', (
      WidgetTester tester,
    ) async {
      final OrderDetail invalid = orderDetail(payment: payment);
      final _FakeOrdersRepository repository = _FakeOrdersRepository(
        patchResult: orderDetail(status: OrderStatus.confirmed),
        getResult: invalid,
      );
      await _pumpDetail(tester, repository);

      expect(find.text('Payment not completed'), findsOneWidget);
      expect(
        find.text(
          'This order cannot be processed because its payment is not marked as paid.',
        ),
        findsOneWidget,
      );
      expect(find.text('Accept order'), findsNothing);
      expect(find.byKey(const Key('order-primary-action')), findsNothing);
      expect(find.text(invalid.orderNumber), findsWidgets);
      expect(repository.patchCalls, 0);
    });
  }

  testWidgets('status changed while dialog is open prevents terminal PATCH', (
    WidgetTester tester,
  ) async {
    final _FakeOrdersRepository repository = _FakeOrdersRepository(
      patchResult: orderDetail(status: OrderStatus.delivered),
      getResult: orderDetail(status: OrderStatus.ready),
    );
    await _pumpDetail(tester, repository);
    await tester.scrollUntilVisible(
      find.byKey(const Key('order-primary-action')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('order-primary-action')));
    await tester.pumpAndSettle();

    repository.getResult = orderDetail(status: OrderStatus.cancelled);
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(OrderDetailScreen)),
    );
    container.invalidate(orderDetailProvider(repository.orderId));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('completion-confirm')));
    await tester.pumpAndSettle();

    expect(repository.patchCalls, 0);
    final OrderMutationState state = container.read(
      orderMutationProvider(repository.orderId),
    );
    expect(state.canonicalOrder?.status, OrderStatus.cancelled);
    expect(state.message, 'Order status changed on the server.');
  });
}

Future<void> _pumpDetail(
  WidgetTester tester,
  _FakeOrdersRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ordersRepositoryProvider.overrideWithValue(repository),
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
  });

  final OrderDetail? patchResult;
  final Future<OrderDetail>? patchFuture;
  final Object? patchError;
  OrderDetail getResult;
  int patchCalls = 0;
  int getCalls = 0;
  final List<String> listLocationIds = <String>[];
  String get orderId => getResult.id;

  @override
  Future<OrderDetail> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  }) async {
    patchCalls++;
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
