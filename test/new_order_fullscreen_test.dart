import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/core/time/pelines_time.dart';
import 'package:pelines_admin_app/features/orders/models/orders_date_filter.dart';
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
import 'package:pelines_admin_app/features/orders/providers/order_alert_coordinator.dart';
import 'package:pelines_admin_app/features/account/models/profile.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

import 'order_test_data.dart';

import 'package:pelines_admin_app/features/orders/presentation/today_orders_view.dart';

OrderDetail _detail(
  String id, {
  OrderStatus status = OrderStatus.pending,
  PaymentStatus payment = PaymentStatus.paid,
  bool longAddress = false,
  bool rich = false,
  int itemCount = 1,
  DateTime? scheduled,
  String type = 'online',
  String fulfillment = 'delivery',
  String locationId = 'location-id',
}) => OrderDetail.fromJson({
  ...orderJson(
    id: id,
    status: status.name,
    payment: payment.name,
    fulfillment: fulfillment,
    locationId: locationId,
  ),
  'orderNumber': id,
  'createdAt': DateTime.now().toUtc().toIso8601String(),
  'scheduledFor': scheduled?.toIso8601String(),
  'orderType': type,
  if (rich) ...{
    'contactName': 'María Customer',
    'eventDetails': {'eventName': 'Celebración familiar', 'attendees': 25},
    'notes': 'Customer note: no onions',
    'internalNotes': 'Kitchen note: call on arrival',
    'location': {'name': 'Troutdale'},
    'subtotalCents': 2400,
    'discountCents': 100,
    'discountCode': 'FAMILY',
    'serviceFeeCents': 60,
    'deliveryFeeCents': 200,
    'taxCents': 140,
    'tipCents': 300,
    'totalCents': 3000,
    'items': [
      for (var i = 0; i < itemCount; i++)
        {
          'id': 'item-$i',
          'productName': i == 0 ? 'Tacos de camarón' : 'Item $i',
          'quantity': 2,
          'unitPriceCents': 1200,
          'lineTotalCents': 2400,
          'notes': 'Salsa aparte',
          'modifiers': [
            {
              'id': 'm-1',
              'groupName': 'Salsa',
              'optionName': 'Verde',
              'priceDeltaCents': 50,
            },
          ],
        },
    ],
  },
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
  void clear() => state = const AsyncData(null);
}

class _Auth extends AuthController {
  @override
  Future<AdminSession?> build() async => null;
  void signedIn() => state = AsyncData(
    AdminSession(
      profile: Profile(
        id: 'admin',
        role: ProfileRole.admin,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    ),
  );
  void signedOut() => state = const AsyncData(null);
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
  int plays = 0;
  final soundCounts = <int>[];
  int stops = 0;
  bool fail = false;
  @override
  Future<void> play({int soundCount = 1}) async {
    plays++;
    soundCounts.add(soundCount);
    if (fail) throw StateError('native effects unavailable');
  }

  @override
  Future<void> stop() async {
    stops++;
  }

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
  bool failList = false;
  int listCalls = 0;
  final detailResponses = <Future<OrderDetail>>[];
  @override
  Future<OrderDetail> getOrderById(String id) async {
    gets++;
    if (detailResponses.isNotEmpty) return detailResponses.removeAt(0);
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
    if (applyPatch) {
      final previous = orders[orderId]!;
      orders[orderId] = _detail(
        orderId,
        status: status,
        scheduled: previous.scheduledFor,
        type: previous.orderType.name,
        fulfillment: previous.fulfillmentType.name,
        locationId: previous.locationId,
        payment: previous.paymentStatus,
      );
    }
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
  }) async {
    listCalls++;
    if (failList) throw const ApiException(message: 'Unavailable');
    return summaries;
  }

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
          scheduledFor: o.scheduledFor,
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
  Future<TodayOrdersState> build() async => TodayOrdersState(
    orders: repo.summaries,
    fullLocationSnapshot: repo.summaries,
    snapshotLocationId: _location.id,
  );
  @override
  Future<void> refresh() async {
    refreshCalls++;
    state = AsyncData(
      TodayOrdersState(
        orders: repo.summaries,
        fullLocationSnapshot: repo.summaries,
        snapshotLocationId: _location.id,
      ),
    );
  }
}

class _Harness {
  _Harness(this.container, this.repo);
  final ProviderContainer container;
  final _Repo repo;
  _Sound get sound => container.read(orderAlertSoundProvider) as _Sound;
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
  String language = 'en',
  bool realToday = false,
  bool preloaded = false,
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
      orderAlertCoordinatorProvider.overrideWith((ref) {
        final feedback = OrderAlertCoordinator(
          ref.read(orderAlertSoundProvider),
          now: tester.binding.clock.now,
        );
        ref.onDispose(feedback.dispose);
        return feedback;
      }),
      if (!realToday) todayOrdersProvider.overrideWith(() => _Today(repo)),
    ],
  );
  if (preloaded) {
    await container.read(todayOrdersProvider.future);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        supportedLocales: AdminLocalizations.supportedLocales,
        localizationsDelegates: const [
          AdminLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
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
  for (final width in [390.0, 768.0, 1366.0]) {
    testWidgets('B.1 silent resolution after content scroll at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = await _pump(tester, scale: 2, language: 'es');
      h.repo.orders['A'] = _detail('A', rich: true, itemCount: 20);
      await h.emit(tester);
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      h.repo.orders['A'] = _detail(
        'A',
        rich: true,
        itemCount: 20,
        status: OrderStatus.confirmed,
      );
      await h.emit(tester);
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(h.unseen, isEmpty);
    });
  }
  for (final change in ['location', 'logout', 'dispose']) {
    for (final delayed in [false, true]) {
      testWidgets(
        'B.1 $change invalidates ${delayed ? "late GET" : "completion"}',
        (tester) async {
          final h = await _pump(tester);
          (h.container.read(authControllerProvider.notifier) as _Auth)
              .signedIn();
          await tester.pumpAndSettle();
          h.repo.orders['A'] = _detail('A');
          await h.emit(tester);
          final late = Completer<OrderDetail>();
          if (delayed) h.repo.detailResponses.add(late.future);
          h.repo.orders['A'] = _detail('A', status: OrderStatus.confirmed);
          await h.container.read(todayOrdersProvider.notifier).refresh();
          await tester.pump();
          if (change == 'location') {
            (h.container.read(currentLocationProvider.notifier) as _Location)
                .clear();
          } else if (change == 'logout') {
            (h.container.read(authControllerProvider.notifier) as _Auth)
                .signedOut();
          } else {
            await tester.pumpWidget(const SizedBox.shrink());
          }
          await tester.pumpAndSettle();
          if (delayed) {
            late.complete(_detail('A', status: OrderStatus.confirmed));
          }
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 4));
          expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
          expect(
            find.byKey(const Key('alert-resolution-message')),
            findsNothing,
          );
          expect(h.repo.patches, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('B.1 X wins before remote resolution and cannot reopen', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.repo.orders['A'] = _detail('A');
    await h.emit(tester);
    await tester.tap(find.byKey(const Key('alert-defer')));
    h.repo.orders['A'] = _detail('A', status: OrderStatus.confirmed);
    await h.emit(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(h.unseen, isEmpty);
    expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
    expect(h.repo.patches, 0);
  });

  for (final failRefresh in [false, true]) {
    testWidgets(
      'B.1 canonical resolution reconciles To-Do; refresh failure=$failRefresh',
      (tester) async {
        final h = await _pump(
          tester,
          realToday: true,
          child: Scaffold(
            body: TodayOrdersView(location: _location, onChangeLocation: () {}),
          ),
        );
        h.repo.orders['A'] = _detail('A');
        await h.emit(tester);
        h.repo.orders['A'] = _detail('A', status: OrderStatus.confirmed);
        // Detail-only refresh proves the board is reconciled by completion.
        h.repo.failList = failRefresh;
        await tester.tap(find.byKey(const Key('alert-refresh')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(h.unseen, isEmpty);
        expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
        final today = h.container.read(todayOrdersProvider).requireValue;
        if (failRefresh) {
          expect(today.refreshError, isNotNull);
        } else {
          expect(today.orders.single.status, OrderStatus.confirmed);
          expect(
            find.descendant(
              of: find.byKey(const Key('todo-column-confirmed')),
              matching: find.text('A'),
            ),
            findsOneWidget,
          );
        }
        expect(h.repo.patches, 0);
      },
    );
  }
  for (final language in ['en', 'es']) {
    for (final status in [
      OrderStatus.confirmed,
      OrderStatus.cancelled,
      OrderStatus.preparing,
      OrderStatus.ready,
      OrderStatus.delivered,
    ]) {
      testWidgets('B.1 pending resolves $status $language with no mutation', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = await _pump(tester, language: language, scale: 2);
        final future = DateTime.now().add(const Duration(days: 7));
        h.repo.orders['A'] = _detail('A', scheduled: future);
        await h.emit(tester);
        h.repo.orders['A'] = _detail('A', status: status, scheduled: future);
        final stops = h.sound.stops;
        await h.container.read(todayOrdersProvider.notifier).refresh();
        await tester.pump();
        await tester.pump();
        final closes =
            status == OrderStatus.confirmed || status == OrderStatus.cancelled;
        // No elapsed visual delay: completion has already updated unseen.
        // Delivered leaves unseen through existing eligibility, but the open
        // presentation remains pinned until explicit acknowledgement.
        final removedFromUnseen = closes || status == OrderStatus.delivered;
        expect(h.unseen, removedFromUnseen ? isEmpty : ['A']);
        expect(h.sound.stops, greaterThan(stops));
        expect(find.byKey(const Key('alert-resolution-message')), findsNothing);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('alert-accept')), findsNothing);
        expect(
          find.byKey(const Key('new-order-bottom-sheet')),
          closes ? findsNothing : findsOneWidget,
        );
        expect(
          find.byKey(const Key('alert-acknowledge')),
          closes ? findsNothing : findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 3));
        expect(h.unseen, removedFromUnseen ? isEmpty : ['A']);
        expect(h.repo.patches, 0);
        expect(h.sound.soundCounts, [3]);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'B.1 queued pending first presented confirmed keeps Acknowledge',
    (tester) async {
      final h = await _pump(tester);
      h.repo.orders['A'] = _detail('A');
      h.repo.orders['B'] = _detail('B');
      await h.emit(tester);
      h.repo.orders['B'] = _detail('B', status: OrderStatus.confirmed);
      await tester.tap(find.byKey(const Key('alert-defer')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      expect(find.byKey(const Key('alert-acknowledge')), findsOneWidget);
      expect(find.byKey(const Key('alert-resolution-message')), findsNothing);
      expect(h.sound.soundCounts, [3, 1]);
      expect(h.unseen, ['B']);
    },
  );

  for (final status in [
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.ready,
    OrderStatus.delivered,
  ]) {
    testWidgets('initially confirmed remains explicit after $status', (
      tester,
    ) async {
      final h = await _pump(tester);
      h.repo.orders['A'] = _detail('A', status: OrderStatus.confirmed);
      await h.emit(tester);
      h.repo.orders['A'] = _detail('A', status: status);
      await tester.tap(find.byKey(const Key('alert-refresh')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsOneWidget);
      expect(find.byKey(const Key('alert-acknowledge')), findsOneWidget);
      expect(find.byKey(const Key('alert-resolution-message')), findsNothing);
      expect(h.repo.patches, 0);
      await tester.tap(find.byKey(const Key('alert-acknowledge')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
    });
  }

  for (final weak in ['403', 'network', 'unknown', 'payment', 'missing-list']) {
    testWidgets('B.1 weak signal $weak never auto completes', (tester) async {
      final h = await _pump(tester);
      h.repo.orders['A'] = _detail('A');
      await h.emit(tester);
      if (weak == '403' || weak == 'network') {
        h.repo.getError = ApiException(
          message: 'Unavailable',
          statusCode: weak == '403' ? 403 : null,
        );
      } else if (weak == 'unknown') {
        h.repo.orders['A'] = _detail('A', status: OrderStatus.unknown);
      } else if (weak == 'payment') {
        h.repo.orders['A'] = _detail('A', payment: PaymentStatus.failed);
      } else {
        final detail = h.repo.orders.remove('A')!;
        h.repo.detailResponses.add(Future.value(detail));
      }
      await h.emit(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsOneWidget);
      expect(find.byKey(const Key('alert-resolution-message')), findsNothing);
      expect(h.repo.patches, 0);
    });
  }

  testWidgets('B.1 404 permits acknowledgement without claiming cancellation', (
    tester,
  ) async {
    final h = await _pump(tester, language: 'es');
    h.repo.orders['A'] = _detail('A');
    await h.emit(tester);
    h.repo.orders.remove('A');
    await h.emit(tester);
    expect(find.text('La orden ya no está disponible'), findsOneWidget);
    expect(find.text('Esta orden ya fue cancelada'), findsNothing);
    await tester.tap(find.byKey(const Key('alert-acknowledge')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
    expect(h.repo.patches, 0);
  });

  testWidgets('B.1 resolution closes Cancel dialog without PATCH', (
    tester,
  ) async {
    final h = await _pump(tester, cancel: true);
    h.repo.orders['A'] = _detail('A');
    await h.emit(tester);
    await tester.tap(find.byKey(const Key('cancel-order-action')));
    await tester.pumpAndSettle();
    h.repo.orders['A'] = _detail('A', status: OrderStatus.confirmed);
    await h.emit(tester);
    expect(find.byKey(const Key('cancel-order-confirm')), findsNothing);
    expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(h.repo.patches, 0);
    expect(h.unseen, isEmpty);
  });

  for (final cancel in [false, true]) {
    testWidgets(
      'B.1 concurrent local ${cancel ? "Cancel" : "Accept"} and late success wins',
      (tester) async {
        final h = await _pump(tester, cancel: cancel);
        h.repo.orders['A'] = _detail('A');
        await h.emit(tester);
        h.repo.holdPatch = Completer<void>();
        if (cancel) {
          await tester.tap(find.byKey(const Key('cancel-order-action')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('cancel-order-confirm')));
        } else {
          await tester.tap(find.byKey(const Key('alert-accept')));
        }
        await tester.pump();
        h.repo.orders['A'] = _detail(
          'A',
          status: cancel ? OrderStatus.cancelled : OrderStatus.confirmed,
        );
        await h.container.read(todayOrdersProvider.notifier).refresh();
        await tester.pump();
        expect(find.byKey(const Key('alert-resolution-message')), findsNothing);
        expect(h.unseen.contains('A'), cancel ? isFalse : isTrue);
        h.repo.holdPatch!.complete();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
        expect(h.repo.patches, 1);
        expect(h.unseen, isEmpty);
      },
    );
  }

  testWidgets(
    'B.1 manual GET superseded by poll cannot resolve from old result',
    (tester) async {
      final h = await _pump(tester);
      h.repo.orders['A'] = _detail('A');
      await h.emit(tester);
      final stale = Completer<OrderDetail>();
      h.repo.detailResponses.add(stale.future);
      await tester.tap(find.byKey(const Key('alert-refresh')));
      await tester.pump();
      await h.container.read(todayOrdersProvider.notifier).refresh();
      await tester.pump();
      stale.complete(_detail('A', status: OrderStatus.confirmed));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('alert-accept')), findsOneWidget);
      expect(find.byKey(const Key('alert-resolution-message')), findsNothing);
      expect(h.unseen, ['A']);
    },
  );

  testWidgets(
    'B.1 Mute then resolution waits in background and revalidates on resume',
    (tester) async {
      final h = await _pump(tester);
      h.repo.orders['A'] = _detail('A');
      await h.emit(tester);
      await tester.tap(find.byKey(const Key('alert-mute')));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      h.repo.orders['A'] = _detail('A', status: OrderStatus.confirmed);
      await h.emit(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(h.unseen, ['A']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(h.unseen, isEmpty);
      expect(h.sound.soundCounts, [3]);
    },
  );

  testWidgets(
    'B.1 resolution advances A B C with existing pause; no late A completion',
    (tester) async {
      final h = await _pump(tester);
      for (final id in ['A', 'B', 'C']) {
        h.repo.orders[id] = _detail(id);
      }
      await h.emit(tester);
      h.repo.orders['A'] = _detail('A', status: OrderStatus.confirmed);
      await h.emit(tester);
      expect(h.unseen, ['B', 'C']);
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
      expect(find.text('B'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(h.unseen, ['B', 'C']);
      await tester.tap(find.byKey(const Key('alert-defer')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('C'), findsOneWidget);
      expect(h.repo.patches, 0);
    },
  );
  setUpAll(PelinesTime.initialize);
  for (final width in [320.0, 390.0, 768.0, 1366.0]) {
    for (final language in ['en', 'es']) {
      testWidgets(
        'bottom sheet modal, content and safe areas $width/$language 2x',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPadding);
          final h = await _pump(
            tester,
            scale: 2,
            language: language,
            cancel: true,
          );
          final delivery = language == 'es';
          h.repo.orders['A'] = _detail(
            'A',
            rich: true,
            itemCount: 20,
            fulfillment: delivery ? 'delivery' : 'pickup',
            type: delivery ? 'catering' : 'online',
            scheduled: DateTime.now().add(const Duration(days: 7)),
          );
          await h.emit(tester);
          final sheet = find.byKey(const Key('new-order-bottom-sheet'));
          final rect = tester.getRect(sheet);
          expect(rect.top, greaterThan(24));
          expect(rect.bottom, closeTo(900, 1));
          expect(rect.width, closeTo(width.clamp(0, 760), 1));
          expect(rect.center.dx, closeTo(width / 2, 1));
          expect(find.byKey(const Key('underlying-draft')), findsOneWidget);
          final route = ModalRoute.of(tester.element(sheet))!;
          expect(route.barrierDismissible, isFalse);
          expect(route.barrierColor, Colors.black54);
          expect(route.opaque, isFalse);
          expect(route.transitionDuration, const Duration(milliseconds: 250));
          final clip = tester.widget<ClipRRect>(
            find.ancestor(of: sheet, matching: find.byType(ClipRRect)).first,
          );
          expect(
            clip.borderRadius,
            const BorderRadius.vertical(top: Radius.circular(24)),
          );
          await tester.tapAt(Offset(width / 2, rect.top / 2));
          await tester.drag(
            find.byKey(const Key('alert-order-number')),
            const Offset(0, 220),
          );
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(sheet, findsOneWidget);
          expect(h.unseen, ['A']);
          expect(h.repo.patches, 0);
          expect(find.text(delivery ? 'CLIENTE' : 'CLIENT'), findsOneWidget);
          expect(
            find.text(delivery ? 'UBICACIÓN DE ENTREGA' : 'PICKUP LOCATION'),
            findsOneWidget,
          );
          expect(
            find.text(delivery ? 'HORA DE ENTREGA' : 'PICKUP TIME'),
            findsOneWidget,
          );
          expect(
            find.text(delivery ? 'TIPO DE ORDEN' : 'ORDER TYPE'),
            findsOneWidget,
          );
          expect(find.text(delivery ? 'CATERING' : 'REGULAR'), findsOneWidget);
          expect(find.text('María Customer'), findsOneWidget);
          expect(find.textContaining('respond'), findsOneWidget);
          expect(
            find.textContaining(
              delivery ? 'Hora del Pacífico' : 'Pacific time',
            ),
            findsOneWidget,
          );
          expect(find.text('2× Item 19'), findsOneWidget);
          expect(find.textContaining('Salsa: Verde'), findsNWidgets(20));
          expect(find.text('Customer note: no onions'), findsOneWidget);
          expect(
            find.text(
              delivery ? 'Valor total de la orden' : 'Total Order Value',
            ),
            findsOneWidget,
          );
          expect(find.text(r'$30.00'), findsOneWidget);
          final total = find.byKey(const Key('alert-total'));
          await tester.ensureVisible(total);
          await tester.pumpAndSettle();
          expect(total.hitTestable(), findsOneWidget);
          for (final key in [
            'alert-accept',
            'cancel-order-action',
            'alert-mute',
            'alert-defer',
          ]) {
            final action = find.byKey(Key(key));
            await tester.ensureVisible(action);
            await tester.pumpAndSettle();
            expect(action.hitTestable(), findsOneWidget);
            expect(
              tester.getSize(action).shortestSide,
              greaterThanOrEqualTo(48),
            );
          }
          expect(
            find.text(delivery ? 'Aceptar orden' : 'Accept order'),
            findsOneWidget,
          );
          expect(
            find.text(delivery ? 'Cancelar orden' : 'Cancel order'),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const Key('alert-defer')));
          await tester.pumpAndSettle();
          expect(sheet, findsNothing);
          expect(h.repo.patches, 0);
          expect(h.repo.orders['A']!.status, OrderStatus.pending);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'short phone with keyboard scrolls actions without overflow or dismiss',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final h = await _pump(tester, scale: 2, language: 'es', cancel: true);
      h.repo.orders['A'] = _detail('A', rich: true, itemCount: 20);
      await h.emit(tester);
      final sheet = find.byKey(const Key('new-order-bottom-sheet'));
      expect(tester.getRect(sheet).bottom, lessThanOrEqualTo(360));
      for (final key in [
        'alert-accept',
        'cancel-order-action',
        'alert-mute',
        'alert-defer',
      ]) {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(find.byKey(Key(key)).hitTestable(), findsOneWidget);
      }
      expect(h.unseen, ['A']);
      expect(h.repo.patches, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    '10.4 Mute keeps fullscreen and unseen with zero PATCH, even on audio failure',
    (tester) async {
      final h = await _pump(tester);
      h.sound.fail = true;
      h.repo.orders['A'] = _detail('A');
      await h.emit(tester);
      expect(h.sound.plays, 1);
      final stops = h.sound.stops;
      await tester.tap(find.byKey(const Key('alert-mute')));
      expect(h.sound.stops, greaterThan(stops));
      await tester.pump(const Duration(seconds: 10));
      expect(h.sound.plays, 1);
      expect(h.repo.patches, 0);
      expect(h.unseen, ['A']);
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsOneWidget);
    },
  );

  testWidgets(
    '10.4 Accept stops before delayed mutation; Mute remains enabled',
    (tester) async {
      final h = await _pump(tester);
      h.repo.orders['A'] = _detail('A');
      await h.emit(tester);
      h.repo.holdPatch = Completer<void>();
      final stops = h.sound.stops;
      await tester.tap(find.byKey(const Key('alert-accept')));
      expect(h.sound.stops, greaterThan(stops));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('alert-mute')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('alert-mute')));
      await tester.pump(const Duration(seconds: 6));
      expect(h.sound.plays, 1);
      expect(h.unseen, ['A']);
      h.repo.holdPatch!.complete();
      await tester.pumpAndSettle();
      expect(h.repo.patches, 1);
      expect(h.unseen, isEmpty);
    },
  );

  testWidgets('10.4 Cancel stops at confirmation, Keep resumes after pause', (
    tester,
  ) async {
    final h = await _pump(tester, cancel: true);
    h.repo.orders['A'] = _detail('A');
    await h.emit(tester);
    final stops = h.sound.stops;
    await tester.tap(find.byKey(const Key('cancel-order-action')));
    expect(h.sound.stops, greaterThan(stops));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(h.sound.plays, 1);
    await tester.tap(find.byKey(const Key('cancel-order-keep')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(h.sound.plays, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(h.sound.plays, 2);
    await tester.tap(find.byKey(const Key('cancel-order-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-order-confirm')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(h.sound.plays, 2);
    expect(h.repo.patches, 1);
  });

  testWidgets(
    '10.4 X stops A immediately; B/C wait and each owns one session',
    (tester) async {
      final h = await _pump(tester);
      h.repo.orders['A'] = _detail('A');
      await h.emit(tester);
      h.repo.orders['B'] = _detail('B');
      h.repo.orders['C'] = _detail('C');
      await h.emit(tester);
      expect(h.sound.plays, 1);
      final stops = h.sound.stops;
      await tester.tap(find.byKey(const Key('alert-defer')));
      expect(h.sound.stops, greaterThan(stops));
      await tester.pumpAndSettle();
      expect(h.unseen, ['B', 'C']);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('A'), findsOneWidget);
      expect(h.sound.plays, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);
      expect(h.sound.plays, 2);
      await tester.tap(find.byKey(const Key('alert-defer')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('C'), findsOneWidget);
      expect(h.sound.plays, 3);
      expect(h.repo.patches, 0);
    },
  );

  testWidgets(
    '10.4 timeout keeps fullscreen; confirmed is initial pulse only',
    (tester) async {
      final h = await _pump(tester);
      h.repo.orders['A'] = _detail('A');
      h.repo.orders['B'] = _detail('B', status: OrderStatus.confirmed);
      await h.emit(tester);
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }
      final plays = h.sound.plays;
      await tester.pump(const Duration(seconds: 10));
      expect(h.sound.plays, plays);
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsOneWidget);
      expect(h.unseen, ['A', 'B']);
      await tester.tap(find.byKey(const Key('alert-defer')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(h.sound.plays, plays + 1);
      await tester.pump(const Duration(seconds: 10));
      expect(h.sound.plays, plays + 1);
    },
  );

  for (final change in ['unpaid', 'missing']) {
    testWidgets(
      '10.4 canonical $change stops while pinned fullscreen remains',
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
        final stops = h.sound.stops;
        await h.emit(tester);
        expect(h.sound.stops, greaterThan(stops));
        await tester.pump(const Duration(seconds: 10));
        expect(h.sound.plays, 1);
        expect(find.byKey(const Key('new-order-bottom-sheet')), findsOneWidget);
      },
    );
  }

  testWidgets('10.4 inactive/background stop; failed resume GET cannot rearm', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.repo.orders['A'] = _detail('A');
    await h.emit(tester);
    final stops = h.sound.stops;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(h.sound.stops, greaterThan(stops));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 10));
    expect(h.sound.plays, 1);
    h.repo.getError = const ApiException(message: 'Network unavailable');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(h.sound.plays, 1);
    h.repo.getError = null;
    await tester.tap(find.byKey(const Key('alert-refresh')));
    await tester.pumpAndSettle();
    expect(h.sound.plays, 2);
  });

  for (final change in ['logout', 'location']) {
    testWidgets('10.4 $change stops and closes fullscreen', (tester) async {
      final h = await _pump(tester);
      (h.container.read(authControllerProvider.notifier) as _Auth).signedIn();
      await tester.pumpAndSettle();
      h.repo.orders['A'] = _detail('A');
      await h.emit(tester);
      final stops = h.sound.stops;
      if (change == 'logout') {
        (h.container.read(authControllerProvider.notifier) as _Auth)
            .signedOut();
      } else {
        (h.container.read(currentLocationProvider.notifier) as _Location)
            .clear();
      }
      await tester.pumpAndSettle();
      expect(h.sound.stops, greaterThan(stops));
      await tester.pump(const Duration(seconds: 20));
      await h.emit(
        tester,
      ); // Even a late snapshot must not reopen after logout.
      expect(h.sound.plays, 1);
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
    });
  }

  for (final (width, height, scale) in [
    (320.0, 740.0, 2.0),
    (768.0, 1024.0, 1.0),
    (1366.0, 768.0, 1.0),
    (1024.0, 600.0, 2.0),
  ]) {
    for (final language in ['en', 'es']) {
      testWidgets('Block 4 detail hierarchy at $width/$scale/$language', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = await _pump(
          tester,
          language: language,
          scale: scale,
          child: const OrderDetailScreen(orderId: 'A'),
        );
        h.repo.orders['A'] = _detail(
          'A',
          status: OrderStatus.confirmed,
          rich: true,
          type: 'catering',
          scheduled: DateTime.now().add(const Duration(days: 7)),
        );
        h.container.invalidate(orderDetailProvider('A'));
        await tester.pumpAndSettle();
        final keys = [
          'detail-order-number',
          'detail-progress',
          'detail-customer',
          'detail-fulfillment',
          'detail-items-totals',
          'detail-customer-notes',
        ];
        for (var i = 0; i < keys.length - 1; i++) {
          expect(
            tester.getTopLeft(find.byKey(Key(keys[i]))).dy,
            lessThan(tester.getTopLeft(find.byKey(Key(keys[i + 1]))).dy),
          );
        }
        expect(find.text('María Customer'), findsOneWidget);
        expect(find.text('2× Tacos de camarón'), findsOneWidget);
        expect(find.textContaining('Salsa: Verde'), findsOneWidget);
        expect(find.textContaining('Salsa aparte'), findsOneWidget);
        expect(find.text('Customer note: no onions'), findsOneWidget);
        expect(find.text('Celebración familiar'), findsWidgets);
        expect(find.text(r'$30.00'), findsOneWidget);
        expect(find.text(r'-$1.00'), findsOneWidget);
        expect(
          find.text(
            language == 'es' ? 'Actualizar progreso' : 'Update Progress',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            language == 'es' ? 'Artículos y totales' : 'Items & Totals',
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.print), findsNothing);
        final action = find.byKey(const Key('order-primary-action'));
        await tester.ensureVisible(action);
        expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
        await tester.ensureVisible(
          find.byKey(const Key('internal-notes-field')),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('internal-notes-field')))
              .controller!
              .text,
          'Kitchen note: call on arrival',
        );
        expect(
          tester.getSize(find.byKey(const Key('detail-customer'))).width,
          lessThanOrEqualTo(768),
        );
        expect(tester.takeException(), isNull);
      });
      testWidgets('Block 4 future alert hierarchy at $width/$scale/$language', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = await _pump(
          tester,
          language: language,
          scale: scale,
          cancel: true,
          realToday: true,
        );
        h.repo.orders['A'] = _detail(
          'A',
          rich: true,
          type: 'catering',
          scheduled: DateTime.now().add(const Duration(days: 7)),
        );
        await h.emit(tester);
        expect(
          find.text(
            language == 'es' ? 'Nueva orden recibida' : 'New order received',
          ),
          findsOneWidget,
        );
        expect(find.text('María Customer'), findsOneWidget);
        expect(find.text('2× Tacos de camarón'), findsOneWidget);
        expect(find.text(r'$30.00'), findsOneWidget);
        expect(
          find.textContaining(
            language == 'es' ? 'Hora del Pacífico' : 'Pacific time',
          ),
          findsOneWidget,
        );
        final accept = find.byKey(const Key('alert-accept'));
        final cancel = find.byKey(const Key('cancel-order-action'));
        await tester.ensureVisible(accept);
        await tester.pumpAndSettle();
        expect(accept.hitTestable(), findsOneWidget);
        await tester.ensureVisible(cancel);
        await tester.pumpAndSettle();
        expect(cancel.hitTestable(), findsOneWidget);
        expect(tester.getSize(accept).height, greaterThanOrEqualTo(48));
        await tester.ensureVisible(find.byKey(const Key('alert-total')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('alert-defer')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('alert-defer')));
        await tester.pumpAndSettle();
        await h.emit(tester);
        expect(h.repo.patches, 0);
        expect(h.repo.orders['A']!.status, OrderStatus.pending);
        expect(h.unseen, isEmpty);
        expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
      });
    }
  }
  testWidgets(
    'preloaded full snapshot baselines before first polling arrival',
    (tester) async {
      final h = await _pump(
        tester,
        realToday: true,
        preloaded: true,
        child: Scaffold(
          body: TodayOrdersView(
            location: _location,
            onChangeLocation: () {},
            webOrders: true,
            initialDateFilter: OrdersDateFilter.upcoming,
          ),
        ),
      );
      expect(
        h.container.read(orderAlertsProvider).requireValue.version,
        StoredOrderAlerts.fullSnapshotVersion,
      );
      final initialCalls = h.repo.listCalls;
      expect(
        (await h.container.read(orderAlertStoreProvider).read(_location.id))!
            .version,
        StoredOrderAlerts.fullSnapshotVersion,
      );
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      h.repo.orders['future'] = _detail(
        'future',
        type: 'catering',
        scheduled: DateTime.now().add(const Duration(days: 7)),
      );
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(h.repo.listCalls, initialCalls + 2);
      expect(h.unseen, ['future']);
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('alert-defer')));
      await tester.pumpAndSettle();
      expect(h.repo.patches, 0);
      expect(h.repo.orders['future']!.status, OrderStatus.pending);
      expect(
        h.container.read(todayOrdersProvider).requireValue.orders,
        isEmpty,
      );
      await h.container.read(calendarOrdersProvider.notifier).refresh();
      await tester.pumpAndSettle();
      final upcoming = h.container.read(calendarOrdersProvider).requireValue;
      expect(upcoming.orders.single.id, 'future');
      expect(upcoming.orders.single.status, OrderStatus.pending);
      await tester.tap(find.byKey(const Key('todo-tab-pending')));
      await tester.pumpAndSettle();
      expect(find.text('future'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('todo-tab-pending')),
          matching: find.text('Waiting · 1'),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(h.unseen, isEmpty);
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
    },
  );
  testWidgets(
    'failed full fetch preserves known/unseen and each refresh uses one request',
    (tester) async {
      final h = await _pump(tester, realToday: true);
      final initial = h.repo.listCalls;
      h.repo.orders['A'] = _detail(
        'A',
        scheduled: DateTime.now().add(const Duration(days: 7)),
      );
      await h.emit(tester);
      expect(h.repo.listCalls, initial + 1);
      final before = h.container.read(orderAlertsProvider).requireValue;
      h.repo.failList = true;
      await h.emit(tester);
      expect(h.repo.listCalls, initial + 2);
      expect(
        h.container.read(orderAlertsProvider).requireValue.knownIds,
        before.knownIds,
      );
      expect(h.unseen, ['A']);
      expect(
        h.container.read(todayOrdersProvider).requireValue.refreshError,
        isNotNull,
      );
    },
  );
  for (final type in ['online', 'catering']) {
    for (final future in [false, true]) {
      for (final fulfillment in ['pickup', 'delivery']) {
        testWidgets('real polling alerts $type future=$future $fulfillment', (
          tester,
        ) async {
          final h = await _pump(tester, realToday: true);
          h.repo.orders['A'] = _detail(
            'A',
            type: type,
            fulfillment: fulfillment,
            scheduled: DateTime.now().add(Duration(days: future ? 7 : 0)),
          );
          await h.emit(tester);
          expect(h.unseen, ['A']);
          expect(
            find.byKey(const Key('new-order-bottom-sheet')),
            findsOneWidget,
          );
          expect(
            h.container.read(todayOrdersProvider).requireValue.orders.length,
            future ? 0 : 1,
          );
          await tester.tap(find.byKey(const Key('alert-defer')));
          await tester.pumpAndSettle();
          await h.emit(tester);
          expect(h.unseen, isEmpty);
          expect(h.repo.patches, 0);
          expect(h.repo.orders['A']!.status, OrderStatus.pending);
          expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
        });
      }
    }
  }

  testWidgets('future defer remains in Upcoming Waiting but never Today', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      realToday: true,
      child: Scaffold(
        body: TodayOrdersView(
          location: _location,
          onChangeLocation: () {},
          initialDateFilter: OrdersDateFilter.upcoming,
          webOrders: true,
        ),
      ),
    );
    h.repo.orders['A'] = _detail(
      'A',
      type: 'catering',
      scheduled: DateTime.now().add(const Duration(days: 7)),
    );
    await h.emit(tester);
    await tester.tap(find.byKey(const Key('alert-defer')));
    await tester.pumpAndSettle();
    await h.container.read(calendarOrdersProvider.notifier).refresh();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('todo-tab-pending')));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('todo-tab-pending')),
        matching: find.text('Waiting · 1'),
      ),
      findsOneWidget,
    );
    expect(h.container.read(todayOrdersProvider).requireValue.orders, isEmpty);
    expect(h.repo.patches, 0);
  });

  testWidgets(
    'future unpaid failed and foreign orders do not alert; payment becoming paid does',
    (tester) async {
      final h = await _pump(tester, realToday: true);
      final date = DateTime.now().add(const Duration(days: 7));
      h.repo.orders['unpaid'] = _detail(
        'unpaid',
        scheduled: date,
        payment: PaymentStatus.unpaid,
      );
      h.repo.orders['failed'] = _detail(
        'failed',
        scheduled: date,
        payment: PaymentStatus.failed,
      );
      h.repo.orders['foreign'] = _detail(
        'foreign',
        scheduled: date,
        locationId: 'other',
      );
      await h.emit(tester);
      expect(h.unseen, isEmpty);
      h.repo.orders['unpaid'] = _detail('unpaid', scheduled: date);
      await h.emit(tester);
      expect(h.unseen, ['unpaid']);
    },
  );

  for (final cancel in [false, true]) {
    testWidgets(
      'future ${cancel ? "Cancel" : "Accept"} reconciles and advances mixed queue',
      (tester) async {
        final h = await _pump(tester, realToday: true, cancel: cancel);
        h.repo.orders['A'] = _detail(
          'A',
          scheduled: DateTime.now().add(const Duration(days: 7)),
        );
        h.repo.orders['B'] = _detail('B');
        await h.emit(tester);
        if (cancel) {
          await tester.tap(find.byKey(const Key('cancel-order-action')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('cancel-order-confirm')));
        } else {
          await tester.tap(find.byKey(const Key('alert-accept')));
        }
        await tester.pumpAndSettle();
        expect(h.repo.patches, 1);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(h.repo.gets, greaterThanOrEqualTo(3));
        expect(
          h.repo.orders['A']!.status,
          cancel ? OrderStatus.cancelled : OrderStatus.confirmed,
        );
        expect(h.unseen, ['B']);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.text('B'), findsOneWidget);
      },
    );
  }

  for (final language in ['en', 'es']) {
    testWidgets(
      'Defer preserves Waiting and stays dismissed after polling ($language)',
      (tester) async {
        final h = await _pump(
          tester,
          language: language,
          child: Scaffold(
            body: TodayOrdersView(location: _location, onChangeLocation: () {}),
          ),
        );
        h.repo.orders['A'] = _detail('A');
        await h.emit(tester);
        final close = find.byKey(const Key('alert-defer'));
        expect(
          find.byTooltip(language == 'en' ? 'Decide later' : 'Decidir después'),
          findsOneWidget,
        );
        expect(tester.getSize(close).shortestSide, greaterThanOrEqualTo(48));
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
        expect(h.unseen, isEmpty);
        expect(h.repo.patches, 0);
        expect(h.repo.orders['A']!.status, OrderStatus.pending);
        expect(h.repo.orders['A']!.paymentStatus, PaymentStatus.paid);
        await tester.tap(find.byKey(const Key('todo-tab-pending')));
        await tester.pumpAndSettle();
        expect(find.text('A'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('todo-tab-pending')),
            matching: find.text(
              language == 'en' ? 'Waiting · 1' : 'En espera · 1',
            ),
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 15));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
        expect(h.repo.patches, 0);
        expect(find.text('A'), findsOneWidget);
      },
    );
  }

  testWidgets('Defer acknowledges only the current queued alert', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.repo.orders['A'] = _detail('A');
    h.repo.orders['B'] = _detail('B');
    await h.emit(tester);
    await tester.tap(find.byKey(const Key('alert-defer')));
    await tester.pumpAndSettle();
    expect(h.unseen, ['B']);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
    expect(find.byKey(const Key('new-order-bottom-sheet')), findsOneWidget);
    expect(
      h.repo.orders.values.every(
        (order) =>
            order.status == OrderStatus.pending &&
            order.paymentStatus == PaymentStatus.paid,
      ),
      isTrue,
    );
    expect(h.repo.patches, 0);
  });
  testWidgets(
    'Accept moves pending from Waiting to Confirmed on To Do and preview advances it',
    (tester) async {
      final h = await _pump(
        tester,
        child: Scaffold(
          body: TodayOrdersView(location: _location, onChangeLocation: () {}),
        ),
      );
      await tester.tap(find.byKey(const Key('todo-tab-pending')));
      await tester.pumpAndSettle();
      h.repo.orders['A'] = _detail('A');
      await h.emit(tester);
      await tester.tap(find.byKey(const Key('alert-accept')));
      await tester.pumpAndSettle();
      expect(h.repo.orders['A']!.status, OrderStatus.confirmed);
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('Waiting · 0'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('todo-column-confirmed')),
          matching: find.text('A'),
        ),
        findsOneWidget,
      );
      final confirmed = find.byKey(const Key('todo-tab-confirmed'));
      await tester.ensureVisible(confirmed);
      await tester.tap(confirmed);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('order-primary-action')),
          matching: find.text('Preparing'),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const Key('order-primary-action')));
      await tester.tap(find.byKey(const Key('order-primary-action')));
      await tester.pumpAndSettle();
      expect(h.repo.orders['A']!.status, OrderStatus.preparing);
      expect(
        find.descendant(
          of: find.byKey(const Key('todo-column-confirmed')),
          matching: find.text('A'),
        ),
        findsNothing,
      );
      final preparing = find.byKey(const Key('todo-tab-preparing'));
      await tester.ensureVisible(preparing);
      await tester.tap(preparing);
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('order-primary-action')),
          matching: find.text('Ready'),
        ),
        findsOneWidget,
      );
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
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('alert-defer')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('alert-acknowledge')), findsNothing);
      expect(find.byKey(const Key('alert-accept')), findsNothing);
      h.repo.getError = null;
      await tester.tap(find.byKey(const Key('alert-refresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
      expect(find.byKey(const Key('alert-resolution-message')), findsNothing);
      expect(h.unseen, isEmpty);
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
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(h.unseen, isEmpty);
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
    expect(find.byKey(const Key('new-order-bottom-sheet')), findsOneWidget);
    expect(
      h.container.read(orderNotesProvider('A')).draft,
      'Preserve these internal notes',
    );
    await tester.tap(find.byKey(const Key('alert-accept')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
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
    testWidgets('Detail progress exposes only the valid $label action', (
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
      expect(action, findsOneWidget);
      expect(find.text(label), findsOneWidget);
      expect(find.text('Accept order'), findsNothing);
      expect(find.byType(DropdownButton<OrderStatus>), findsNothing);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      if (status == OrderStatus.ready) {
        expect(h.repo.patches, 0);
        await tester.tap(find.byKey(const Key('completion-confirm')));
        await tester.pumpAndSettle();
      }
      expect(h.repo.patches, 1);
      expect(h.repo.orders['A']!.status, switch (status) {
        OrderStatus.confirmed => OrderStatus.preparing,
        OrderStatus.preparing => OrderStatus.ready,
        _ => OrderStatus.delivered,
      });
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
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsOneWidget);
      expect(find.text('Existing dialog').hitTestable(), findsNothing);
      expect(h.unseen, ['A']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.unseen, ['A']);
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsOneWidget);
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
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('alert-defer')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('alert-defer')));
      expect(h.unseen, ['A']);
      h.repo.holdPatch!.complete();
      await tester.pumpAndSettle();
      expect(h.repo.patches, 1);
      expect(h.repo.gets, greaterThanOrEqualTo(3));
      expect(h.unseen, isEmpty);
      expect(find.byKey(const Key('new-order-bottom-sheet')), findsNothing);
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
          expect(
            find.byKey(const Key('alert-resolution-message')),
            findsNothing,
          );
          expect(h.unseen, isEmpty);
          expect(h.repo.patches, 1);
        }
      },
    );
  }

  for (final change in ['unpaid', 'missing']) {
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
        expect(find.byKey(const Key('new-order-bottom-sheet')), findsOneWidget);
        expect(find.text('1 of 2'), findsOneWidget);
        expect(find.byKey(const Key('alert-accept')), findsNothing);
        expect(h.repo.patches, 0);
        await tester.tap(find.byKey(const Key('alert-acknowledge')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
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
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
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
