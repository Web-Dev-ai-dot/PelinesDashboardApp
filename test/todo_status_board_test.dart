import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_detail_screen.dart';
import 'package:pelines_admin_app/features/printing/providers/printing_providers.dart';
import 'package:pelines_admin_app/features/printing/application/print_order_service.dart';
import 'package:pelines_admin_app/features/printing/application/ticket_builder.dart';
import 'package:pelines_admin_app/features/printing/models/print_job.dart';

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
import 'package:pelines_admin_app/features/orders/presentation/today_orders_view.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_preview_card.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

import 'order_test_data.dart';
import 'upcoming_sheet_helpers.dart';

import 'package:pelines_admin_app/features/orders/models/orders_date_filter.dart';

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

class _PrintService implements PrintOrderService {
  _PrintService(this.result);
  final PrintJobStatus result;
  bool unavailable = false;
  int calls = 0;
  OrderDetail? received;
  PrintJob? job;
  @override
  Future<PrintJob> queueInitialPrint(OrderDetail order) async {
    calls++;
    received = order;
    if (unavailable) {
      throw const PrintRequestException('Selected printer is not available.');
    }
    return job = PrintJob(
      id: 'job',
      orderId: order.id,
      locationId: order.locationId,
      purpose: PrintPurpose.initial,
      status: result,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      printerId: result == PrintJobStatus.confirmed ? 'fake' : 'printer',
      ticket: const TicketBuilder().build(order),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Printing implements PrintingRuntime {
  _Printing(this.service);
  @override
  final _PrintService service;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements OrdersRepository {
  int listCalls = 0, patches = 0, gets = 0;
  Completer<OrderDetail>? pendingPatch;
  bool failPatch = false;
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
        'items': [],
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

  OrderDetail _detail(String id) => OrderDetail.fromJson(rows[id]!);
  @override
  Future<OrderDetail> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  }) async {
    patches++;
    if (failPatch) {
      throw const ApiException(message: 'Status rejected', statusCode: 422);
    }
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
  Widget? child,
  GoRouter? router,
  _PrintService? printer,
  bool upcoming = false,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentLocationProvider.overrideWith(_Current.new),
        ordersRepositoryProvider.overrideWithValue(repository),
        if (printer != null) ...[
          printingRuntimeProvider.overrideWith(
            (ref) async => _Printing(printer),
          ),
          printJobsProvider(location.id).overrideWith(
            (ref) => Stream.value([if (printer.job != null) printer.job!]),
          ),
        ],
      ],
      child: MaterialApp.router(
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
        routerConfig:
            router ??
            GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => Scaffold(
                    body:
                        child ??
                        TodayOrdersView(
                          webOrders: upcoming,
                          initialDateFilter: upcoming
                              ? OrdersDateFilter.upcoming
                              : OrdersDateFilter.today,
                          location: location,
                          onChangeLocation: () {},
                          showLocationSelector: false,
                        ),
                  ),
                ),
              ],
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder column(String status) => find.byKey(Key('todo-column-$status'));
Finder card(String id) => find.byWidgetPredicate(
  (widget) => widget is OrderPreviewCard && widget.order.id == id,
);
Finder action(String id) => find.descendant(
  of: card(id),
  matching: find.byKey(const Key('order-primary-action')),
);

Future<void> tab(WidgetTester tester, String status) async {
  final target = find.byKey(Key('todo-tab-$status'));
  final tabs = find.byKey(const Key('todo-tabs-scroll'));
  for (
    var attempt = 0;
    attempt < 4 && target.hitTestable().evaluate().isEmpty;
    attempt++
  ) {
    final direction = tester.getCenter(target).dx > tester.getCenter(tabs).dx
        ? -1.0
        : 1.0;
    await tester.fling(tabs, Offset(direction * 100, 0), 1000);
    await tester.pumpAndSettle();
  }
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('To Do Refresh retains the final column and vertical scroll', (
    tester,
  ) async {
    final repo = _Repository(today: true);
    await _mount(tester, repo, width: 390, scale: 2);
    await tab(tester, 'confirmed');
    final vertical = find
        .descendant(of: column('confirmed'), matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(vertical).position;
    position.jumpTo(position.maxScrollExtent);
    final before = position.pixels;
    final board = find.byKey(const Key('todo-board-scroll'));
    final controller = tester.widget<SingleChildScrollView>(board).controller!;
    final offset = controller.offset;
    final calls = repo.listCalls;
    final refresh = tester
        .state<TodayOrdersViewState>(find.byType(TodayOrdersView))
        .refresh();
    await tester.pumpAndSettle();
    await refresh;
    expect(repo.listCalls, greaterThan(calls));
    expect(controller.offset, offset);
    expect(tester.state<ScrollableState>(vertical).position.pixels, before);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('todo-tab-confirmed')))
          .style!
          .side!
          .resolve({})!
          .color,
      PelinesColors.textPrimary,
    );
    expect(
      tester.getRect(column('confirmed')).left,
      closeTo(tester.getRect(board).left, .1),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('slim tab surface retains a 48px effective touch target', (
    tester,
  ) async {
    await _mount(tester, _Repository(today: true));
    final target = find.byKey(const Key('todo-tab-confirmed'));
    final surface = find.descendant(
      of: target,
      matching: find.byType(Material),
    );
    expect(tester.getSize(surface).height, greaterThanOrEqualTo(36));
    expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    final rect = tester.getRect(target);
    await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
    await tester.pumpAndSettle();
    expect(
      tester.widget<OutlinedButton>(target).style!.side!.resolve({})!.color,
      PelinesColors.textPrimary,
    );
    final scroll = tester
        .widget<SingleChildScrollView>(
          find.byKey(const Key('todo-board-scroll')),
        )
        .controller!;
    expect(scroll.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
  testWidgets('To-Do displays only the channel returned by existing Detail', (
    tester,
  ) async {
    final repo = _Repository(today: true);
    repo.rows['pending']!['source'] = 'ios';
    await _mount(tester, repo);
    expect(
      find.descendant(of: card('pending'), matching: find.text('iOS')),
      findsOneWidget,
    );
    expect(find.text('Web'), findsNothing);
    expect(repo.patches, 0);
  });
  for (final upcoming in [false, true]) {
    for (final (result, label) in [
      (PrintJobStatus.submitted, 'Submitted (not physical confirmation)'),
      (PrintJobStatus.confirmed, 'Confirmed (simulated)'),
      (PrintJobStatus.unknown, 'Unknown'),
      (PrintJobStatus.failedBeforeSend, 'Failed before send'),
    ]) {
      testWidgets(
        'Print uses canonical order and preserves $result semantics, upcoming=$upcoming',
        (tester) async {
          final repo = _Repository(today: !upcoming);
          final printer = _PrintService(result);
          await _mount(tester, repo, printer: printer, upcoming: upcoming);
          final pending = find.byKey(const Key('todo-print-pending'));
          expect(tester.widget<OutlinedButton>(pending).onPressed, isNull);
          await tab(tester, 'confirmed');
          final print = find.byKey(const Key('todo-print-confirmed'));
          await tester.ensureVisible(print);
          await tester.pumpAndSettle();
          await tester.tap(print);
          await tester.pumpAndSettle();
          expect(printer.calls, 1);
          expect(printer.received!.id, 'confirmed');
          expect(printer.received!.paymentStatus, PaymentStatus.paid);
          expect(find.text(label), findsOneWidget);
          if (result == PrintJobStatus.confirmed) {
            expect(
              find.text('Simulation only. No physical ticket.'),
              findsOneWidget,
            );
          }
          expect(tester.widget<OutlinedButton>(print).onPressed, isNull);
          expect(repo.patches, 0);
        },
      );
    }
  }
  testWidgets('Print unavailable reports error without claiming success', (
    tester,
  ) async {
    final printer = _PrintService(PrintJobStatus.submitted)..unavailable = true;
    await _mount(tester, _Repository(today: true), printer: printer);
    await tab(tester, 'confirmed');
    final print = find.byKey(const Key('todo-print-confirmed'));
    await tester.ensureVisible(print);
    await tester.tap(print);
    await tester.pumpAndSettle();
    expect(find.text('Selected printer is not available.'), findsOneWidget);
    expect(find.text('Submitted (not physical confirmation)'), findsNothing);
    expect(tester.widget<OutlinedButton>(print).onPressed, isNotNull);
  });
  testWidgets(
    'canonical payment guard blocks PATCH and unpaid is excluded from counts',
    (tester) async {
      final repo = _Repository(today: true);
      repo.rows['confirmed']!['paymentStatus'] = 'unpaid';
      await _mount(tester, repo);
      expect(card('confirmed'), findsNothing);
      expect(find.text('Confirmed · 0'), findsOneWidget);
      repo.rows['pending']!['paymentStatus'] = 'refunded';
      await tester.ensureVisible(action('pending'));
      await tester.tap(action('pending'));
      await tester.pumpAndSettle();
      expect(repo.patches, 0);
      expect(
        find.descendant(of: column('pending'), matching: card('pending')),
        findsOneWidget,
      );
    },
  );
  for (final width in [320.0, 390.0, 768.0, 1366.0]) {
    for (final language in ['en', 'es']) {
      testWidgets(
        'four columns, tab scroll, cards and empty counts $width/$language 2x',
        (tester) async {
          final repo = _Repository(today: true);
          repo.rows.remove('preparing');
          repo.rows['pending']!['scheduledFor'] = null;
          repo.rows['pending']!['items'] = [
            {
              'id': 'food',
              'productName': 'Tacos',
              'quantity': 2,
              'unitPriceCents': 500,
              'lineTotalCents': 1000,
              'modifiers': [
                {
                  'id': 'extra',
                  'groupName': 'Extras',
                  'optionName': 'Guacamole',
                  'priceDeltaCents': 100,
                },
              ],
            },
          ];
          await _mount(
            tester,
            repo,
            width: width,
            scale: 2,
            language: language,
          );
          for (final status in ['pending', 'confirmed', 'preparing', 'ready']) {
            expect(column(status), findsOneWidget);
          }
          for (final status in ['pending', 'confirmed', 'preparing', 'ready']) {
            final target = find.byKey(Key('todo-tab-$status'));
            final button = tester.widget<OutlinedButton>(target);
            expect(button.child, isA<Text>());
            expect(
              find.descendant(
                of: target,
                matching: find.byType(PelinesStateBadge),
              ),
              findsNothing,
            );
            expect(button.style!.shape!.resolve({}), isA<StadiumBorder>());
            final background = button.style!.backgroundColor!.resolve({})!;
            final foreground = button.style!.foregroundColor!.resolve({})!;
            final heading = tester.widget<PelinesStateBadge>(
              find.byKey(Key('todo-column-heading-$status')),
            );
            expect(heading.background, background);
            expect(heading.foreground, foreground);
            expect(heading.dot, isTrue);
            expect(heading.label, endsWith(status == 'preparing' ? '0' : '1'));
            expect(background.a, 1);
            expect(background, switch (status) {
              'pending' => const Color(0xFFFFE4BA),
              'confirmed' => const Color(0xFFC7F3D9),
              'preparing' => const Color(0xFFE8DAFF),
              _ => const Color(0xFFFFD9DC),
            });
            expect(foreground, switch (status) {
              'pending' => const Color(0xFF855300),
              'confirmed' => const Color(0xFF086B3B),
              'preparing' => const Color(0xFF6435A1),
              _ => const Color(0xFFA52D38),
            });
            final a = background.computeLuminance(),
                b = foreground.computeLuminance();
            expect(
              ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05),
              greaterThanOrEqualTo(4.5),
            );
            expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
          }
          expect(find.text('ASAP'), findsOneWidget);
          expect(find.text('2× Tacos'), findsOneWidget);
          expect(find.textContaining('Extras: Guacamole'), findsOneWidget);
          expect(find.text(r'$11.00'), findsWidgets);
          expect(find.text('Celebration pending'), findsOneWidget);
          expect(find.text('REGULAR'), findsWidgets);
          expect(find.text('CATERING'), findsOneWidget);
          expect(find.text('Web'), findsNothing);
          expect(find.byKey(const Key('orders-date-selector')), findsNothing);
          final calls = repo.listCalls;
          for (final status in ['ready', 'preparing', 'confirmed', 'pending']) {
            await tab(tester, status);
            expect(column(status).hitTestable(), findsOneWidget);
            final selected = tester.widget<OutlinedButton>(
              find.byKey(Key('todo-tab-$status')),
            );
            expect(
              selected.style!.side!.resolve({})!.color,
              PelinesColors.textPrimary,
            );
            expect(tester.takeException(), isNull);
          }
          expect(
            find.textContaining(
              language == 'es' ? 'En preparación · 0' : 'Preparing · 0',
            ),
            findsOneWidget,
          );
          final scroll = tester
              .widget<SingleChildScrollView>(
                find.byKey(const Key('todo-board-scroll')),
              )
              .controller!;
          await tester.drag(
            find.byKey(const Key('todo-board-scroll')),
            const Offset(-240, 0),
          );
          await tester.pumpAndSettle();
          expect(scroll.offset, greaterThan(0));
          expect(repo.listCalls, calls);
          expect(repo.patches, 0);
        },
      );
    }
  }

  for (final upcoming in [false, true]) {
    testWidgets(
      'real mutations reconcile across columns; View returns with context, upcoming=$upcoming',
      (tester) async {
        final repo = _Repository(today: !upcoming)
          ..rows.removeWhere((key, _) => key != 'pending');
        final router = GoRouter(
          initialLocation: '/app',
          routes: [
            GoRoute(
              path: '/app',
              builder: (_, _) => Scaffold(
                body: TodayOrdersView(
                  webOrders: upcoming,
                  initialDateFilter: upcoming
                      ? OrdersDateFilter.upcoming
                      : OrdersDateFilter.today,
                  location: location,
                  onChangeLocation: () {},
                  showLocationSelector: false,
                ),
              ),
            ),
            GoRoute(
              path: '/app/orders/:id',
              builder: (_, state) =>
                  OrderDetailScreen(orderId: state.pathParameters['id']!),
            ),
          ],
        );
        addTearDown(router.dispose);
        await _mount(tester, repo, router: router);
        final scheduled = repo.rows['pending']!['scheduledFor'];
        if (upcoming) {
          await tester.enterText(
            find.byType(TextField),
            '  CUSTOMER pending  ',
          );
          await tester.pumpAndSettle();
        }
        for (final (source, target, label) in [
          ('pending', 'confirmed', 'Confirmed'),
          ('confirmed', 'preparing', 'Preparing'),
          ('preparing', 'ready', 'Ready'),
        ]) {
          await tab(tester, source);
          final button = action('pending');
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(
            find.descendant(of: button, matching: find.text(label)),
            findsOneWidget,
          );
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.toString(), '/app');
          expect(
            find.descendant(of: column(source), matching: card('pending')),
            findsNothing,
          );
          expect(
            find.descendant(of: column(target), matching: card('pending')),
            findsOneWidget,
          );
        }
        expect(repo.patches, 3);
        expect(repo.rows['pending']!['scheduledFor'], scheduled);
        if (upcoming) {
          await upcomingType(tester, 'online');
          await upcomingTap(tester, 'upcoming-filters');
          final day = pacificDate(DateTime.parse(scheduled as String));
          await upcomingDate(tester, 'from', day);
          await upcomingDate(tester, 'to', day);
          await upcomingTap(tester, 'upcoming-status-ready');
          await upcomingTap(tester, 'upcoming-sheet-apply');
        }
        await tab(tester, 'ready');
        final view = find.descendant(
          of: card('pending'),
          matching: find.text('View'),
        );
        await tester.ensureVisible(view);
        await tester.pumpAndSettle();
        final scroll = tester
            .widget<SingleChildScrollView>(
              find.byKey(const Key('todo-board-scroll')),
            )
            .controller!;
        final offset = scroll.offset;
        await tester.tap(view);
        await tester.pumpAndSettle();
        expect(find.byType(OrderDetailScreen), findsOneWidget);
        expect(router.canPop(), isTrue);
        router.pop();
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/app');
        expect(scroll.offset, offset);
        if (upcoming) {
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            '  CUSTOMER pending  ',
          );
          expect(find.byKey(const Key('upcoming-sort')), findsOneWidget);
          await upcomingTap(tester, 'upcoming-sort');
          expect(
            tester
                .widget<RadioGroup<OrderType?>>(
                  find.byType(RadioGroup<OrderType?>),
                )
                .groupValue,
            OrderType.online,
          );
          await upcomingDismiss(tester);
          await upcomingTap(tester, 'upcoming-filters');
          expect(
            tester
                .widget<RadioGroup<OrderStatus?>>(
                  find.byType(RadioGroup<OrderStatus?>),
                )
                .groupValue,
            OrderStatus.ready,
          );
          expect(find.textContaining('Tomorrow'), findsNothing);
          expect(find.textContaining('No end date'), findsNothing);
          await upcomingDismiss(tester);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'busy prevents double submit and does not move before reconciliation',
    (tester) async {
      final repo = _Repository(today: true)
        ..pendingPatch = Completer<OrderDetail>();
      await _mount(tester, repo);
      await tester.ensureVisible(action('pending'));
      await tester.tap(action('pending'));
      await tester.pump();
      await tester.tap(action('pending'));
      await tester.pump();
      expect(repo.patches, 1);
      expect(tester.widget<FilledButton>(action('pending')).onPressed, isNull);
      expect(
        find.descendant(of: column('pending'), matching: card('pending')),
        findsOneWidget,
      );
      repo.rows['pending']!['status'] = 'confirmed';
      repo.pendingPatch!.complete(repo._detail('pending'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: column('confirmed'), matching: card('pending')),
        findsOneWidget,
      );
    },
  );

  testWidgets('failed status stays in source column with error and retry', (
    tester,
  ) async {
    final repo = _Repository(today: true)..failPatch = true;
    await _mount(tester, repo);
    await tester.ensureVisible(action('pending'));
    await tester.tap(action('pending'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: column('pending'), matching: card('pending')),
      findsOneWidget,
    );
    expect(find.textContaining('Status rejected'), findsOneWidget);
    expect(repo.patches, 1);
  });

  testWidgets(
    'Ready preserves pickup confirmation and removes only after terminal reconciliation',
    (tester) async {
      final repo = _Repository(today: true)
        ..rows.removeWhere((key, _) => key != 'ready');
      await _mount(tester, repo);
      await tab(tester, 'ready');
      await tester.ensureVisible(action('ready'));
      expect(
        find.descendant(
          of: action('ready'),
          matching: find.text('Mark picked up'),
        ),
        findsOneWidget,
      );
      await tester.tap(action('ready'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm pickup?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('completion-cancel')));
      await tester.pumpAndSettle();
      expect(repo.patches, 0);
      await tester.tap(action('ready'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('completion-confirm')));
      await tester.pumpAndSettle();
      expect(repo.rows['ready']!['status'], 'delivered');
      expect(
        find.descendant(of: column('ready'), matching: card('ready')),
        findsNothing,
      );
      expect(
        find.descendant(of: column('delivered'), matching: card('ready')),
        findsOneWidget,
      );
      expect(find.text('Picked Up · 1'), findsOneWidget);
      final pickedBadge = tester
          .widgetList<PelinesStateBadge>(
            find.descendant(
              of: card('ready'),
              matching: find.byType(PelinesStateBadge),
            ),
          )
          .singleWhere((badge) => badge.label == 'PICKED UP');
      expect(pickedBadge.background, PelinesColors.border);
      expect(pickedBadge.foreground, PelinesColors.textPrimary);
      await tab(tester, 'delivered');
      expect(action('ready'), findsNothing);
      expect(find.text('Ready · 0'), findsOneWidget);
      expect(repo.patches, 1);
    },
  );
}
