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
  Future<OrderDetail> getOrderById(String id) async {
    getCalls++;
    return getResult;
  }

  @override
  Future<List<OrderSummary>> getOrders({required String locationId}) async {
    listLocationIds.add(locationId);
    return <OrderSummary>[];
  }
}
