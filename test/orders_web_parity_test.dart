import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/app/theme/pelines_components.dart';
import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/models/orders_date_filter.dart';
import 'package:pelines_admin_app/features/orders/presentation/today_orders_view.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_preview_card.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

import 'order_test_data.dart';

final location = Location(
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
  Future<Location?> build() async => location;
}

class _Repository implements OrdersRepository {
  int listCalls = 0, patches = 0, gets = 0;
  Completer<OrderDetail>? pendingPatch;
  final rows = <String, Map<String, dynamic>>{};
  _Repository({bool today = false}) {
    for (final status in [
      OrderStatus.pending,
      OrderStatus.confirmed,
      OrderStatus.preparing,
      OrderStatus.ready,
    ]) {
      rows[status.name] = {
        ...orderJson(id: status.name, status: status.name),
        'orderNumber': 'ORD-${status.name}',
        'orderType': status == OrderStatus.confirmed ? 'catering' : 'online',
        'contactName': 'Customer ${status.name}',
        'scheduledFor': DateTime.now()
            .add(Duration(days: today ? 0 : 2))
            .toUtc()
            .toIso8601String(),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'eventDetails': {'eventName': 'Celebration ${status.name}'},
        'items': [
          {'quantity': 3},
        ],
      };
    }
  }
  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async {
    listCalls++;
    return rows.values.map(OrderSummary.fromJson).toList();
  }

  @override
  Future<OrderDetail> getOrderById(String id) async {
    gets++;
    return _detail(id);
  }

  OrderDetail _detail(String id) =>
      OrderDetail.fromJson({...rows[id]!, 'items': <dynamic>[]});
  @override
  Future<OrderDetail> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  }) async {
    patches++;
    if (pendingPatch != null) return pendingPatch!.future;
    rows[orderId]!['status'] = status.name;
    return _detail(orderId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(
  WidgetTester tester,
  _Repository repository, {
  double width = 390,
  double scale = 1,
  String language = 'en',
  bool upcoming = true,
  Widget? child,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentLocationProvider.overrideWith(_Current.new),
        ordersRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: Locale(language),
        supportedLocales: AdminLocalizations.supportedLocales,
        localizationsDelegates: const [
          AdminLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body:
              child ??
              TodayOrdersView(
                location: location,
                onChangeLocation: () {},
                showLocationSelector: false,
                webOrders: upcoming,
                initialDateFilter: upcoming
                    ? OrdersDateFilter.upcoming
                    : OrdersDateFilter.today,
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> status(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(ChoiceChip, label);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide board groups only real states and scrolls to Ready', (
    tester,
  ) async {
    await _mount(tester, _Repository(), width: 1100);
    await status(tester, 'All');
    expect(find.byKey(const Key('orders-column-pending')), findsOneWidget);
    final board = find.byKey(const Key('orders-board'));
    await tester.ensureVisible(board);
    await tester.drag(board, const Offset(-850, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('orders-column-ready')), findsOneWidget);
    expect(find.text('ORD-ready'), findsOneWidget);
    expect(find.byKey(const Key('orders-column-picked_up')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (state, payment) in [
    ('pending', 'unpaid'),
    ('confirmed', 'failed'),
    ('delivered', 'paid'),
    ('cancelled', 'paid'),
    ('unknown', 'paid'),
  ]) {
    testWidgets('preview has no unsafe action for $state/$payment', (
      tester,
    ) async {
      final repository = _Repository();
      final order = OrderSummary.fromJson({
        ...repository.rows['pending']!,
        'status': state,
        'paymentStatus': payment,
      });
      await _mount(
        tester,
        repository,
        child: SingleChildScrollView(child: OrderPreviewCard(order: order)),
      );
      expect(find.byKey(const Key('order-primary-action')), findsNothing);
      expect(find.text('View'), findsOneWidget);
      expect(repository.patches, 0);
      expect(repository.gets, 0);
      expect(tester.takeException(), isNull);
    });
  }
  for (final (width, scale, language) in [
    (320.0, 2.0, 'es'),
    (390.0, 1.0, 'en'),
    (768.0, 1.0, 'en'),
    (1024.0, 2.0, 'es'),
    (1400.0, 1.0, 'en'),
  ]) {
    testWidgets('Upcoming adapts cards/board at $width/$scale/$language', (
      tester,
    ) async {
      final repository = _Repository();
      repository.rows['confirmed']!['contactName'] = 'Customer with a long name that must wrap without hiding operational information';
      await _mount(
        tester,
        repository,
        width: width,
        scale: scale,
        language: language,
      );
      expect(
        tester
            .widget<PopupMenuButton<OrdersDateFilter>>(
              find.byKey(const Key('orders-date-selector')),
            )
            .initialValue,
        OrdersDateFilter.upcoming,
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(
                ChoiceChip,
                language == 'es' ? 'Confirmado' : 'Confirmed',
              ),
            )
            .selected,
        isTrue,
      );
      expect(find.byType(PelinesFilterBar), findsOneWidget);
      expect(find.byKey(const Key('waiting-count')), findsOneWidget);
      expect(
        find.byKey(const Key('orders-board')),
        width >= 1000 * scale ? findsOneWidget : findsNothing,
      );
      if (width < 1000 * scale) {
        final count = width >= 720 * scale ? 2 : 1;
        expect(find.byKey(Key('upcoming-cards-$count')), findsOneWidget);
      }
      final card = find.byType(OrderPreviewCard).first;
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (w) => w is PelinesStateBadge && w.dot,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.byType(PelinesStateBadge)),
        findsNWidgets(3),
      );
      final action = find.descendant(
        of: card,
        matching: find.byKey(const Key('order-primary-action')),
      );
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'search and type compose locally without requests or losing date/status',
    (tester) async {
      final repository = _Repository();
      await _mount(tester, repository);
      final calls = repository.listCalls;
      await tester.enterText(find.byType(TextField), 'missing customer');
      await tester.pumpAndSettle();
      expect(find.byType(OrderPreviewCard), findsNothing);
      await tester.enterText(find.byType(TextField), 'Celebration confirmed');
      await tester.pumpAndSettle();
      expect(find.byType(OrderPreviewCard), findsOneWidget);
      final type = find.byType(DropdownButton<OrderType>);
      await tester.tap(type);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regular').last);
      await tester.pumpAndSettle();
      expect(find.byType(OrderPreviewCard), findsNothing);
      await tester.tap(type);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Catering').last);
      await tester.pumpAndSettle();
      expect(find.byType(OrderPreviewCard), findsOneWidget);
      expect(repository.listCalls, calls);
      expect(repository.patches, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('To Do has four status columns without date or search filters', (
    tester,
  ) async {
    await _mount(
      tester,
      _Repository(today: true),
      width: 1400,
      upcoming: false,
    );
    expect(find.byKey(const Key('orders-date-selector')), findsNothing);
    expect(find.byKey(const Key('orders-search')), findsNothing);
    expect(find.byKey(const Key('orders-board')), findsNothing);
    for (final status in ['pending', 'confirmed', 'preparing', 'ready']) {
      expect(find.byKey(Key('todo-column-$status')), findsOneWidget);
    }
    expect(find.text('ORD-pending'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final entry in [
    (OrderStatus.pending, 'Accept order', PelinesColors.successForeground),
    (OrderStatus.confirmed, 'Start preparing', PelinesColors.successForeground),
    (OrderStatus.preparing, 'Mark ready', PelinesColors.preparing),
    (OrderStatus.ready, 'Mark picked up', PelinesColors.blue),
  ]) {
    testWidgets(
      'preview keeps valid ${entry.$1.name} action with semantic color',
      (tester) async {
        final repository = _Repository();
        final order = OrderSummary.fromJson(repository.rows[entry.$1.name]!);
        await _mount(
          tester,
          repository,
          child: SingleChildScrollView(child: OrderPreviewCard(order: order)),
        );
        final button = find.byKey(const Key('order-primary-action'));
        expect(
          find.descendant(of: button, matching: find.text(entry.$2)),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(button)
              .style!
              .backgroundColor!
              .resolve({}),
          entry.$3,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'styled Accept still waits for canonical mutation and blocks double tap',
    (tester) async {
      final repository = _Repository()..pendingPatch = Completer<OrderDetail>();
      final order = OrderSummary.fromJson(repository.rows['pending']!);
      await _mount(
        tester,
        repository,
        child: SingleChildScrollView(child: OrderPreviewCard(order: order)),
      );
      final button = find.byKey(const Key('order-primary-action'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      expect(repository.patches, 1);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      repository.rows['pending']!['status'] = 'confirmed';
      repository.pendingPatch!.complete(repository._detail('pending'));
      await tester.pumpAndSettle();
      expect(find.text('Start preparing'), findsOneWidget);
      expect(repository.gets, greaterThanOrEqualTo(2));
      expect(tester.takeException(), isNull);
    },
  );
}
