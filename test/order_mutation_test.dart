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
import 'package:pelines_admin_app/features/orders/providers/order_alerts_controller.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

import 'order_test_data.dart';

import 'package:pelines_admin_app/features/orders/presentation/order_preview_action.dart';

void main() {
  testWidgets('preview remount during refresh cannot restore cached status', (
    tester,
  ) async {
    final before = orderDetail(status: OrderStatus.confirmed);
    final after = orderDetail(status: OrderStatus.preparing);
    final refresh = Completer<OrderDetail>();
    var reads = 0;
    final container = ProviderContainer(
      overrides: [
        currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
        orderDetailProvider.overrideWith(
          (ref, id) async => ++reads == 1 ? before : await refresh.future,
        ),
      ],
    );
    final keep = container.listen(orderMutationProvider(before.id), (_, _) {});
    await container.read(currentLocationProvider.future);
    await container.read(orderDetailProvider(before.id).future);
    container
        .read(orderMutationProvider(before.id).notifier)
        .adoptRefreshedOrder(after);
    container.invalidate(orderDetailProvider(before.id));
    // The refreshed provider retains its old value while the GET is pending.
    final pending = container.read(orderDetailProvider(before.id).future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: OrderPreviewAction(
              order: OrderSummary.fromJson(orderJson(status: 'preparing')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      container.read(orderMutationProvider(before.id)).canonicalOrder?.status,
      OrderStatus.preparing,
    );
    expect(find.text('Marking ready...'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('order-primary-action')))
          .onPressed,
      isNull,
    );
    refresh.complete(after);
    await pending;
    await tester.pumpAndSettle();
    expect(find.text('Mark ready'), findsOneWidget);
    expect(find.text('Start preparing'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    keep.close();
    container.dispose();
  });

  for (final (OrderStatus source, OrderStatus target)
      in <(OrderStatus, OrderStatus)>[
        (OrderStatus.pending, OrderStatus.confirmed),
        (OrderStatus.confirmed, OrderStatus.preparing),
        (OrderStatus.preparing, OrderStatus.ready),
        (OrderStatus.ready, OrderStatus.delivered),
      ]) {
    test(
      'preflight and final GET protect ${source.name} to ${target.name}',
      () async {
        final OrderDetail before = orderDetail(status: source);
        final OrderDetail after = orderDetail(status: target);
        final _FakeOrdersRepository repository = _FakeOrdersRepository(
          patchResult: after,
          getResult: after,
          getResults: <OrderDetail>[before, after],
        );
        final ProviderContainer container = _container(repository);
        addTearDown(container.dispose);
        await container.read(currentLocationProvider.future);

        await container
            .read(orderMutationProvider(repository.orderId).notifier)
            .performCurrentAction(before);

        expect(repository.getCalls, 2);
        expect(repository.patchCalls, 1);
        expect(repository.requestedStatuses, <OrderStatus>[target]);
        expect(
          container.read(orderMutationProvider(repository.orderId)).phase,
          OrderMutationPhase.success,
        );
      },
    );
  }

  for (final OrderStatus remote in <OrderStatus>[
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.cancelled,
  ]) {
    test('remote ${remote.name} is adopted before PATCH', () async {
      final OrderDetail canonical = orderDetail(status: remote);
      final _FakeOrdersRepository repository = _FakeOrdersRepository(
        patchResult: canonical,
        getResult: canonical,
        getResults: <OrderDetail>[canonical],
      );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);

      await container
          .read(orderMutationProvider(repository.orderId).notifier)
          .acceptOrder(orderDetail());

      final OrderMutationState result = container.read(
        orderMutationProvider(repository.orderId),
      );
      expect(repository.patchCalls, 0);
      expect(result.canonicalOrder?.status, remote);
      expect(result.message, contains('Order updated elsewhere'));
    });
  }

  test('refunded active order is settled: status change allowed', () async {
    final OrderDetail refunded = orderDetail(payment: PaymentStatus.refunded);
    final OrderDetail accepted = orderDetail(
      status: OrderStatus.confirmed,
      payment: PaymentStatus.refunded,
    );
    final _FakeOrdersRepository repository = _FakeOrdersRepository(
      patchResult: accepted,
      getResult: accepted,
      getResults: <OrderDetail>[refunded, accepted],
    );
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    await container
        .read(orderMutationProvider(repository.orderId).notifier)
        .acceptOrder(refunded);
    expect(repository.patchCalls, 1);
    expect(repository.requestedStatuses, <OrderStatus>[OrderStatus.confirmed]);
    expect(
      container.read(orderMutationProvider(repository.orderId)).phase,
      OrderMutationPhase.success,
    );
  });

  testWidgets(
    'refunded active order shows no payment warning and keeps its action',
    (WidgetTester tester) async {
      final OrderDetail refunded = orderDetail(payment: PaymentStatus.refunded);
      final _FakeOrdersRepository repository = _FakeOrdersRepository(
        patchResult: orderDetail(
          status: OrderStatus.confirmed,
          payment: PaymentStatus.refunded,
        ),
        getResult: refunded,
      );
      await _pumpDetail(tester, repository);
      expect(find.text('Payment not completed'), findsNothing);
      expect(
        find.text(
          'This order cannot be processed because its payment is not marked as paid.',
        ),
        findsNothing,
      );
      expect(find.text('Accept order'), findsWidgets);
    },
  );

  test('canonical unpaid payment blocks a locally paid order', () async {
    final OrderDetail refunded = orderDetail(payment: PaymentStatus.unpaid);
    final _FakeOrdersRepository repository = _FakeOrdersRepository(
      patchResult: orderDetail(status: OrderStatus.confirmed),
      getResult: refunded,
      getResults: <OrderDetail>[refunded],
    );
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    await container
        .read(orderMutationProvider(repository.orderId).notifier)
        .acceptOrder(orderDetail());
    expect(repository.patchCalls, 0);
    expect(
      container.read(orderMutationProvider(repository.orderId)).message,
      contains('payment is not marked as paid'),
    );
  });

  test('post-PATCH mismatch adopts canonical without false success', () async {
    final _FakeOrdersRepository repository = _FakeOrdersRepository(
      patchResult: orderDetail(status: OrderStatus.confirmed),
      getResult: orderDetail(),
      getResults: <OrderDetail>[orderDetail(), orderDetail()],
    );
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    await container
        .read(orderMutationProvider(repository.orderId).notifier)
        .acceptOrder(orderDetail());
    final OrderMutationState result = container.read(
      orderMutationProvider(repository.orderId),
    );
    expect(result.phase, OrderMutationPhase.error);
    expect(result.canonicalOrder?.status, OrderStatus.pending);
    expect(result.message, contains('while the request was being processed'));
    expect(repository.patchCalls, 1);
  });

  test('timeout with failed recovery GET reports uncertain state', () async {
    final _FakeOrdersRepository repository = _FakeOrdersRepository(
      patchError: _networkError(),
      getResult: orderDetail(),
      getResults: <OrderDetail>[orderDetail()],
      getError: const ApiException(message: 'Refresh failed.'),
      getErrorCall: 2,
    );
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    await container
        .read(orderMutationProvider(repository.orderId).notifier)
        .acceptOrder(orderDetail());
    final OrderMutationState result = container.read(
      orderMutationProvider(repository.orderId),
    );
    expect(repository.patchCalls, 1);
    expect(repository.getCalls, 2);
    expect(result.message, contains('Unable to confirm the order status'));
    expect(result.message, contains('Refresh the order before trying again'));
  });

  test(
    'success uses PATCH response, reconciles detail, and refreshes Today',
    () async {
      final _FakeOrdersRepository repository = _FakeOrdersRepository(
        patchResult: orderDetail(status: OrderStatus.confirmed),
        getResult: orderDetail(status: OrderStatus.confirmed),
        getResults: <OrderDetail>[
          orderDetail(),
          orderDetail(status: OrderStatus.confirmed),
        ],
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
      expect(repository.getCalls, 2);
      expect(repository.listLocationIds, <String>['location-id']);
    },
  );

  test('submitting blocks a second tap', () async {
    final Completer<OrderDetail> patch = Completer<OrderDetail>();
    final _FakeOrdersRepository repository = _FakeOrdersRepository(
      patchFuture: patch.future,
      getResult: orderDetail(status: OrderStatus.confirmed),
      getResults: <OrderDetail>[
        orderDetail(),
        orderDetail(status: OrderStatus.confirmed),
      ],
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
    await Future<void>.delayed(Duration.zero);
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
      getResults: <OrderDetail>[orderDetail(), orderDetail()],
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
    expect(repository.getCalls, 2);
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
        getResults: <OrderDetail>[
          orderDetail(),
          orderDetail(status: serverStatus),
        ],
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
      expect(repository.getCalls, 2);
      if (serverStatus == OrderStatus.pending) {
        expect(state.message, contains('try again'));
      } else if (serverStatus == OrderStatus.preparing) {
        expect(
          state.message,
          'Order status changed while the request was being processed.',
        );
      }
    });
  }

  test('location change during preflight blocks PATCH', () async {
    final _FakeOrdersRepository repository = _FakeOrdersRepository(
      patchResult: orderDetail(status: OrderStatus.confirmed),
      getResult: orderDetail(status: OrderStatus.confirmed),
      getResults: <OrderDetail>[orderDetail()],
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
    await mutation;

    expect(repository.patchCalls, 0);
    expect(repository.listLocationIds, isEmpty);
    expect(
      container.read(orderMutationProvider(repository.orderId)).message,
      contains('Location context changed'),
    );
  });

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
        getResults: <OrderDetail>[
          orderDetail(status: OrderStatus.ready),
          orderDetail(status: OrderStatus.delivered, deliveredAt: deliveredAt),
        ],
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
          getResults: <OrderDetail>[
            orderDetail(status: OrderStatus.ready),
            orderDetail(
              status: serverStatus,
              deliveredAt: serverStatus == OrderStatus.delivered
                  ? DateTime.parse('2026-09-04T19:00:00Z')
                  : null,
            ),
          ],
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
        expect(repository.getCalls, 2);
      },
    );
  }

  testWidgets(
    'preview shows contextual action and disables it while submitting',
    (WidgetTester tester) async {
      final Completer<OrderDetail> patch = Completer<OrderDetail>();
      final _FakeOrdersRepository repository = _FakeOrdersRepository(
        patchFuture: patch.future,
        getResult: orderDetail(),
        getResults: <OrderDetail>[
          orderDetail(),
          orderDetail(),
          orderDetail(status: OrderStatus.confirmed),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ordersRepositoryProvider.overrideWithValue(repository),
            currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
          ],
          child: const MaterialApp(
            home: _PreviewScreen(
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

  testWidgets('detail refreshes canonical status on app resume', (
    WidgetTester tester,
  ) async {
    final _FakeOrdersRepository repository = _FakeOrdersRepository(
      getResult: orderDetail(status: OrderStatus.preparing),
      getResults: <OrderDetail>[
        orderDetail(status: OrderStatus.confirmed),
        orderDetail(status: OrderStatus.preparing),
      ],
    );
    await _pumpDetail(tester, repository);
    expect(find.byKey(const Key('order-primary-action')), findsOneWidget);
    expect(find.text('Start preparing'), findsOneWidget);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(OrderDetailScreen)),
    );
    container.read(appResumeTickProvider.notifier).resumed();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('order-primary-action')), findsOneWidget);
    expect(find.text('Mark ready'), findsOneWidget);
    expect(find.text('Start preparing'), findsNothing);
    expect(repository.getCalls, 2);
  });

  testWidgets('failed detail refresh keeps data and shows retry warning', (
    WidgetTester tester,
  ) async {
    final _FakeOrdersRepository repository = _FakeOrdersRepository(
      getResult: orderDetail(status: OrderStatus.confirmed),
      getResults: <OrderDetail>[orderDetail(status: OrderStatus.confirmed)],
      getError: const ApiException(message: 'Refresh failed.'),
      getErrorCall: 2,
      getErrorFromCall: true,
    );
    await _pumpDetail(tester, repository);
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(OrderDetailScreen)),
    );
    container.read(appResumeTickProvider.notifier).resumed();
    await tester.pumpAndSettle();

    expect(repository.getCalls, greaterThanOrEqualTo(2));
    expect(
      container.read(orderDetailProvider(repository.orderId)).hasError,
      isTrue,
    );
    expect(find.byKey(const Key('detail-refresh-warning')), findsOneWidget);
    expect(find.text(orderDetail().orderNumber), findsWidgets);
    expect(find.text('Start preparing'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('location change makes an open detail read-only', (
    WidgetTester tester,
  ) async {
    final _FakeOrdersRepository repository = _FakeOrdersRepository(
      getResult: orderDetail(),
    );
    await _pumpDetail(tester, repository);
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(OrderDetailScreen)),
    );
    final _FakeCurrentLocation current = container.read(
      currentLocationProvider.notifier,
    ) as _FakeCurrentLocation;
    current.change(_location('second-location'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location-context-warning')), findsOneWidget);
    expect(find.byKey(const Key('order-primary-action')), findsNothing);
    expect(repository.patchCalls, 0);
  });

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
          getResults: <OrderDetail>[
            orderDetail(status: OrderStatus.ready, fulfillment: fulfillment),
            orderDetail(status: OrderStatus.ready, fulfillment: fulfillment),
            orderDetail(
              status: OrderStatus.delivered,
              fulfillment: fulfillment,
              deliveredAt: deliveredAt,
            ),
          ],
        );
        await _pumpPreview(tester, repository);
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
        await _pumpPreview(tester, repository);
        expect(find.text('Mark picked up'), findsNothing);
        expect(find.text('Mark delivered'), findsNothing);
      }
    },
  );

  for (final PaymentStatus payment in <PaymentStatus>[
    PaymentStatus.failed,
    PaymentStatus.unpaid,
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
    await _pumpPreview(tester, repository);
    await tester.scrollUntilVisible(
      find.byKey(const Key('order-primary-action')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('order-primary-action')));
    await tester.pumpAndSettle();

    repository.getResult = orderDetail(status: OrderStatus.cancelled);
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(_PreviewScreen)),
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
    List<OrderDetail>? getResults,
    this.getError,
    this.getErrorCall,
    this.getErrorFromCall = false,
  }) : getResults = getResults ?? <OrderDetail>[];

  final OrderDetail? patchResult;
  final Future<OrderDetail>? patchFuture;
  final Object? patchError;
  OrderDetail getResult;
  final List<OrderDetail> getResults;
  final Object? getError;
  final int? getErrorCall;
  final bool getErrorFromCall;
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
    if (getError != null &&
        (getCalls == getErrorCall ||
            getErrorFromCall && getCalls >= (getErrorCall ?? 1))) {
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

class _PreviewScreen extends ConsumerWidget {
  const _PreviewScreen({required this.orderId});
  final String orderId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(orderDetailProvider(orderId));
    return Scaffold(
      body: ListView(
        children: [
          if (detail.value case final order?)
            OrderPreviewAction(
              order: OrderSummary.fromJson(
                orderJson(
                  id: order.id,
                  status: order.status.name,
                  fulfillment: order.fulfillmentType.name,
                  payment: order.paymentStatus.name,
                  locationId: order.locationId,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _pumpPreview(
  WidgetTester tester,
  _FakeOrdersRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ordersRepositoryProvider.overrideWithValue(repository),
        currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
      ],
      child: MaterialApp(home: _PreviewScreen(orderId: repository.orderId)),
    ),
  );
  await tester.pumpAndSettle();
}
