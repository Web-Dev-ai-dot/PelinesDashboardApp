import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/auth/models/admin_session.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_controller.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_providers.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/data/order_alert_sound.dart';
import 'package:pelines_admin_app/features/orders/data/order_alert_store.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_alert_shell.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_detail_screen.dart';
import 'package:pelines_admin_app/features/orders/providers/order_alerts_controller.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

import 'order_test_data.dart';

import 'package:pelines_admin_app/features/orders/presentation/today_orders_view.dart';

OrderDetail _detail(
  String id, {
  OrderStatus status = OrderStatus.pending,
  PaymentStatus payment = PaymentStatus.paid,
  bool longAddress = false,
}) => OrderDetail.fromJson({
  ...orderJson(
    id: id,
    status: status.name,
    payment: payment.name,
    fulfillment: 'delivery',
  ),
  'orderNumber': id,
  'deliveryAddress': {
    'line1': longAddress
        ? List.filled(90, 'Long delivery address').join(' ')
        : '123 Main St',
    'city': 'Troutdale',
  },
});
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

class _Location extends CurrentLocationController {
  @override
  Future<Location?> build() async => _location;
}

class _Auth extends AuthController {
  @override
  Future<AdminSession?> build() async => null;
}

class _Store implements OrderAlertStore {
  final values = <String, StoredOrderAlerts>{};
  @override
  Future<StoredOrderAlerts?> read(String id) async => values[id];
  @override
  Future<void> write(String id, StoredOrderAlerts value) async {
    values[id] = value;
  }
}

class _Sound implements OrderAlertSound {
  @override
  Future<void> play() async {}
  @override
  Future<void> dispose() async {}
}

class _Repo implements OrdersRepository {
  final orders = <String, OrderDetail>{};
  int patches = 0;
  int gets = 0;
  Object? getError;
  bool ambiguous = false;
  bool applyPatch = true;
  bool failFinalGet = false;
  Completer<void>? holdPatch;
  @override
  Future<OrderDetail> getOrderById(String id) async {
    gets++;
    if (getError != null) throw getError!;
    return orders[id] ??
        (throw const ApiException(message: 'Missing', statusCode: 404));
  }

  @override
  Future<OrderDetail> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  }) async {
    patches++;
    await holdPatch?.future;
    if (applyPatch) orders[orderId] = _detail(orderId, status: status);
    if (failFinalGet) {
      getError = const ApiException(
        message: 'Final GET unavailable',
        statusCode: 503,
      );
    }
    if (ambiguous) {
      throw ApiException(
        message: 'Connection lost',
        cause: DioException(
          requestOptions: RequestOptions(path: '/orders'),
          type: DioExceptionType.connectionError,
        ),
      );
    }
    return orders[orderId]!;
  }

  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async => summaries;
  List<OrderSummary> get summaries => orders.values
      .map(
        (o) => OrderSummary(
          id: o.id,
          orderNumber: o.orderNumber,
          locationId: o.locationId,
          orderType: o.orderType,
          status: o.status,
          rawStatus: o.rawStatus,
          paymentStatus: o.paymentStatus,
          fulfillmentType: o.fulfillmentType,
          contactName: o.contactName,
          createdAt: o.createdAt,
          itemCount: 1,
          totalCents: o.totalCents,
        ),
      )
      .toList();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Today extends TodayOrdersController {
  _Today(this.repo);
  final _Repo repo;
  int refreshCalls = 0;
  @override
  Future<TodayOrdersState> build() async =>
      TodayOrdersState(orders: repo.summaries);
  @override
  Future<void> refresh() async {
    refreshCalls++;
    state = AsyncData(TodayOrdersState(orders: repo.summaries));
  }
}

class _Harness {
  _Harness(this.container, this.repo);
  final ProviderContainer container;
  final _Repo repo;
  List<String> get unseen =>
      container.read(orderAlertsProvider).requireValue.unseenIds;
  Future<void> emit(WidgetTester tester) async {
    await container.read(todayOrdersProvider.notifier).refresh();
    await tester.pumpAndSettle();
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  bool cancel = false,
  Widget? child,
  double scale = 1,
}) async {
  final repo = _Repo();
  final container = ProviderContainer(
    overrides: [
      ordersRepositoryProvider.overrideWithValue(repo),
      orderCancellationEnabledProvider.overrideWithValue(cancel),
      currentLocationProvider.overrideWith(_Location.new),
      authControllerProvider.overrideWith(_Auth.new),
      orderAlertStoreProvider.overrideWithValue(_Store()),
      orderAlertSoundProvider.overrideWithValue(_Sound()),
      todayOrdersProvider.overrideWith(() => _Today(repo)),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: OrderAlertShell(
          child:
              child ??
              const Scaffold(body: TextField(key: Key('underlying-draft'))),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
  });
  return _Harness(container, repo);
}

void main() {
  testWidgets(
    'Accept moves pending out of Waiting into default Confirmed and preview advances it',
    (tester) async {
      final h = await _pump(
        tester,
        child: Scaffold(
          body: TodayOrdersView(location: _location, onChangeLocation: () {}),
        ),
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Confirmed'))
            .selected,
        isTrue,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Waiting'));
      await tester.pumpAndSettle();
      h.repo.orders['A'] = _detail('A');
      await h.emit(tester);
      await tester.tap(find.byKey(const Key('alert-accept')));
      await tester.pumpAndSettle();
      expect(h.repo.orders['A']!.status, OrderStatus.confirmed);
      expect(find.byKey(const Key('new-order-fullscreen')), findsNothing);
      expect(find.text('A'), findsOneWidget);
      expect(find.byKey(const Key('waiting-count')), findsNothing);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Confirmed'))
            .selected,
        isTrue,
      );
      expect(find.text('Start preparing'), findsOneWidget);
      await tester.tap(find.byKey(const Key('order-primary-action')));
      await tester.pumpAndSettle();
      expect(h.repo.orders['A']!.status, OrderStatus.preparing);
      expect(find.text('A'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Preparing'));
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
      expect(find.text('Mark ready'), findsOneWidget);
      expect(h.repo.patches, 2);
    },
  );
  testWidgets(
    'unreconciled provisional result cannot be acknowledged until canonical refresh',
    (tester) async {
      final h = await _pump(tester);
      h.repo.orders['A'] = _detail('A');
      h.repo.failFinalGet = true;
      await h.emit(tester);
      await tester.tap(find.byKey(const Key('alert-accept')));
      await tester.pumpAndSettle();
      expect(h.repo.patches, 1);
      expect(h.unseen, ['A']);
      expect(find.byKey(const Key('alert-acknowledge')), findsNothing);
      expect(find.byKey(const Key('alert-accept')), findsNothing);
      h.repo.getError = null;
      await tester.tap(find.byKey(const Key('alert-refresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('alert-acknowledge')), findsOneWidget);
      expect(h.unseen, ['A']);
      expect(h.repo.patches, 1);
    },
  );

  testWidgets(
    'remote transition during Accept preflight never sends invalid PATCH',
    (tester) async {
      final h = await _pump(tester);
      h.repo.orders['A'] = _detail('A');
      await h.emit(tester);
      h.repo.orders['A'] = _detail('A', status: OrderStatus.confirmed);
      await tester.tap(find.byKey(const Key('alert-accept')));
      await tester.pumpAndSettle();
      expect(h.repo.patches, 0);
      expect(find.byKey(const Key('alert-accept')), findsNothing);
      expect(h.unseen, ['A']);
      await tester.tap(find.byKey(const Key('alert-refresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('alert-acknowledge')), findsOneWidget);
    },
  );

  testWidgets(
    'shell retains 15 second foreground polling and pauses in background',
    (tester) async {
      final h = await _pump(tester);
      final today = h.container.read(todayOrdersProvider.notifier) as _Today;
      final initial = today.refreshCalls;
      await tester.pump(const Duration(seconds: 14));
      expect(today.refreshCalls, initial);
      await tester.pump(const Duration(seconds: 1));
      expect(today.refreshCalls, initial + 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(today.refreshCalls, initial + 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(today.refreshCalls, initial + 2);
    },
  );

  testWidgets('hidden Detail refresh does not auto-ack the fullscreen', (
    tester,
  ) async {
    final h = await _pump(tester, child: const OrderDetailScreen(orderId: 'A'));
    h.repo.orders['A'] = _detail('A');
    h.container.invalidate(orderDetailProvider('A'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('internal-notes-field')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('internal-notes-field')),
      'Preserve these internal notes',
    );
    await tester.pumpAndSettle();
    await h.emit(tester);
    expect(h.unseen, ['A']);
    await tester.tap(find.byKey(const Key('alert-refresh')));
    await tester.pumpAndSettle();
    expect(h.unseen, ['A']);
    expect(find.byKey(const Key('new-order-fullscreen')), findsOneWidget);
    expect(
      h.container.read(orderNotesProvider('A')).draft,
      'Preserve these internal notes',
    );
    await tester.tap(find.byKey(const Key('alert-accept')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-order-fullscreen')), findsNothing);
    expect(
      h.container.read(orderNotesProvider('A')).draft,
      'Preserve these internal notes',
    );
  });

  for (final (status, label) in [
    (OrderStatus.confirmed, 'Start preparing'),
    (OrderStatus.preparing, 'Mark ready'),
    (OrderStatus.ready, 'Mark delivered'),
  ]) {
    testWidgets('Detail does not duplicate the $label preview action', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        child: const OrderDetailScreen(orderId: 'A'),
      );
      h.repo.orders['A'] = _detail('A', status: status, longAddress: true);
      h.container.invalidate(orderDetailProvider('A'));
      await tester.pumpAndSettle();
      final action = find.byKey(const Key('order-primary-action'));
      expect(action, findsNothing);
      expect(find.text(label), findsNothing);
      expect(find.text('Accept order'), findsNothing);
    });
  }

  testWidgets(
    'fullscreen blocks Back, covers drawer and existing dialog, preserves draft without auto-ack',
    (tester) async {
      final drawerKey = GlobalKey<ScaffoldState>();
      final h = await _pump(
        tester,
        child: Scaffold(
          key: drawerKey,
          drawer: const Drawer(child: Text('Sidebar')),
          body: const TextField(key: Key('underlying-draft')),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('underlying-draft')),
        'Keep my draft',
      );
      drawerKey.currentState!.openDrawer();
      await tester.pumpAndSettle();
      unawaited(
        showDialog<void>(
          context: drawerKey.currentContext!,
          builder: (_) => const AlertDialog(content: Text('Existing dialog')),
        ),
      );
      await tester.pumpAndSettle();
      h.repo.orders['A'] = _detail('A', status: OrderStatus.confirmed);
      await h.emit(tester);
      expect(find.byKey(const Key('new-order-fullscreen')), findsOneWidget);
      expect(find.text('Existing dialog').hitTestable(), findsNothing);
      expect(h.unseen, ['A']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.unseen, ['A']);
      expect(find.byKey(const Key('new-order-fullscreen')), findsOneWidget);
      expect(find.byKey(const Key('alert-accept')), findsNothing);
      await tester.tap(find.byKey(const Key('alert-acknowledge')));
      await tester.pumpAndSettle();
      expect(h.unseen, isEmpty);
      Navigator.of(drawerKey.currentContext!, rootNavigator: true).pop();
      drawerKey.currentState!.closeDrawer();
      await tester.pumpAndSettle();
      expect(find.text('Keep my draft'), findsOneWidget);
    },
  );

  testWidgets(
    'pending double tap runs one reconciled mutation then acknowledges',
    (tester) async {
      final h = await _pump(tester);
      h.repo.orders['A'] = _detail('A');
      await h.emit(tester);
      expect(find.byKey(const Key('alert-acknowledge')), findsNothing);
      expect(find.byKey(const Key('cancel-order-action')), findsNothing);
      expect(h.unseen, ['A']);
      h.repo.holdPatch = Completer<void>();
      final accept = find.byKey(const Key('alert-accept'));
      await tester.tap(accept);
      await tester.tap(accept);
      await tester.pump();
      expect(h.repo.patches, 1);
      expect(tester.widget<FilledButton>(accept).onPressed, isNull);
      expect(h.unseen, ['A']);
      h.repo.holdPatch!.complete();
      await tester.pumpAndSettle();
      expect(h.repo.patches, 1);
      expect(h.repo.gets, greaterThanOrEqualTo(3));
      expect(h.unseen, isEmpty);
      expect(find.byKey(const Key('new-order-fullscreen')), findsNothing);
    },
  );

  for (final applied in [false, true]) {
    testWidgets(
      'ambiguous PATCH reconciles without automatic retry, applied=$applied',
      (tester) async {
        final h = await _pump(tester);
        h.repo.orders['A'] = _detail('A');
        h.repo.ambiguous = true;
        h.repo.applyPatch = applied;
        await h.emit(tester);
        await tester.tap(find.byKey(const Key('alert-accept')));
        await tester.pumpAndSettle();
        expect(h.repo.patches, 1);
        if (applied) {
          expect(h.unseen, isEmpty);
        } else {
          expect(h.unseen, ['A']);
          expect(
            find.byKey(const Key('alert-mutation-message')),
            findsOneWidget,
          );
          h.repo.orders['A'] = _detail('A', status: OrderStatus.confirmed);
          await tester.tap(find.byKey(const Key('alert-refresh')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('alert-accept')), findsNothing);
          expect(h.unseen, ['A']);
          await tester.tap(find.byKey(const Key('alert-acknowledge')));
          await tester.pumpAndSettle();
          expect(h.unseen, isEmpty);
          expect(h.repo.patches, 1);
        }
      },
    );
  }

  for (final change in ['confirmed', 'unpaid', 'missing']) {
    testWidgets(
      'remote $change pins current queue item until explicit acknowledgement',
      (tester) async {
        final h = await _pump(tester);
        h.repo.orders['A'] = _detail('A');
        await h.emit(tester);
        if (change == 'missing') {
          h.repo.orders.remove('A');
        } else {
          h.repo.orders['A'] = _detail(
            'A',
            status: change == 'confirmed'
                ? OrderStatus.confirmed
                : OrderStatus.pending,
            payment: change == 'unpaid'
                ? PaymentStatus.failed
                : PaymentStatus.paid,
          );
        }
        h.repo.orders['B'] = _detail('B');
        await h.emit(tester);
        expect(find.byKey(const Key('new-order-fullscreen')), findsOneWidget);
        expect(find.text('1 of 2'), findsOneWidget);
        expect(find.byKey(const Key('alert-accept')), findsNothing);
        expect(h.repo.patches, 0);
        await tester.tap(find.byKey(const Key('alert-acknowledge')));
        await tester.pumpAndSettle();
        expect(find.text('B'), findsOneWidget);
        expect(find.text('1 of 1'), findsOneWidget);
        expect(find.byKey(const Key('alert-accept')), findsOneWidget);
      },
    );
  }

  testWidgets(
    'new arrival does not replace active decision; Cancel uses existing confirmation and gate',
    (tester) async {
      final h = await _pump(tester, cancel: true);
      h.repo.orders['A'] = _detail('A');
      await h.emit(tester);
      h.repo.orders['B'] = _detail('B');
      await h.emit(tester);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancel-order-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancel-order-keep')));
      await tester.pumpAndSettle();
      expect(h.repo.patches, 0);
      await tester.tap(find.byKey(const Key('cancel-order-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancel-order-confirm')));
      await tester.pumpAndSettle();
      expect(h.repo.orders['A']!.status, OrderStatus.cancelled);
      expect(h.unseen, ['B']);
      expect(find.text('B'), findsOneWidget);
    },
  );

  testWidgets('failed canonical GET offers refresh, never unsafe actions', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.repo.orders['A'] = _detail('A');
    h.repo.getError = const ApiException(
      message: 'Unavailable',
      statusCode: 503,
    );
    await h.emit(tester);
    expect(find.byKey(const Key('alert-accept')), findsNothing);
    expect(find.byKey(const Key('alert-acknowledge')), findsNothing);
    h.repo.getError = null;
    await tester.tap(find.byKey(const Key('alert-refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('alert-accept')), findsOneWidget);
    expect(h.unseen, ['A']);
  });

  for (final width in [390.0, 768.0]) {
    testWidgets(
      'long fullscreen content keeps actions accessible at $width / 2x',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final h = await _pump(tester, scale: 2, cancel: true);
        h.repo.orders['A'] = _detail('A', longAddress: true);
        await h.emit(tester);
        final accept = tester.getRect(find.byKey(const Key('alert-accept')));
        final cancel = tester.getRect(
          find.byKey(const Key('cancel-order-action')),
        );
        final refresh = tester.getRect(find.byKey(const Key('alert-refresh')));
        expect(accept.bottom, lessThan(cancel.top));
        expect(cancel.bottom, lessThan(refresh.top));
        expect(accept.width, cancel.width);
        expect(cancel.width, refresh.width);
        expect(accept.height, greaterThanOrEqualTo(56));
        expect(cancel.height, greaterThanOrEqualTo(56));
        expect(refresh.height, greaterThanOrEqualTo(56));
        expect(
          find.byKey(const Key('alert-accept')).hitTestable(),
          findsOneWidget,
        );
        expect(
          tester.getSize(find.byKey(const Key('alert-accept'))).height,
          greaterThanOrEqualTo(48),
        );
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('alert-accept')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
