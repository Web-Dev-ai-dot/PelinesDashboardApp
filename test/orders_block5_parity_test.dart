import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/core/time/pelines_time.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/presentation/historical_orders_screen.dart';
import 'package:pelines_admin_app/features/orders/presentation/orders_calendar_screen.dart';
import 'package:pelines_admin_app/features/orders/presentation/calendar_month_grid.dart';
import 'package:pelines_admin_app/features/orders/models/orders_date_filter.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

import 'order_test_data.dart';

final _location = Location(
  id: 'A',
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

class _Repo implements OrdersRepository {
  final now = DateTime.now();
  bool fail = false, empty = false;
  int calls = 0;
  Completer<void>? hold;
  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async {
    calls++;
    await hold?.future;
    if (fail) throw const ApiException(message: 'offline Block 5');
    if (empty) return [];
    return [
      for (final id in ['one', 'two'])
        OrderSummary.fromJson({
          ...orderJson(
            id: id,
            status: (status ?? OrderStatus.pending).name,
            locationId: 'A',
            payment: status == OrderStatus.cancelled && id == 'one'
                ? 'refunded'
                : 'paid',
          ),
          'orderNumber': 'ORD-$id',
          'contactName': 'María Customer',
          'orderType': id == 'one' ? 'catering' : 'online',
          'eventDetails': {'eventName': 'Celebración familiar'},
          'scheduledFor': id == 'one' ? now.toUtc().toIso8601String() : null,
          'createdAt': now
              .subtract(const Duration(days: 90))
              .toUtc()
              .toIso8601String(),
          'deliveredAt': status == OrderStatus.delivered && id == 'one'
              ? now.toUtc().toIso8601String()
              : null,
        }),
    ];
  }

  @override
  Future<OrderDetail> getOrderById(String id) async =>
      orderDetail(id: id, locationId: 'A');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<GoRouter> _mount(
  WidgetTester tester,
  _Repo repo,
  String page, {
  double width = 390,
  double scale = 1,
  String language = 'en',
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    initialLocation: '/$page',
    routes: [
      GoRoute(
        path: '/calendar',
        builder: (_, _) => const OrdersCalendarScreen(),
      ),
      GoRoute(
        path: '/completed',
        builder: (_, _) =>
            const HistoricalOrdersScreen(kind: HistoricalOrdersKind.completed),
      ),
      GoRoute(
        path: '/cancelled',
        builder: (_, _) =>
            const HistoricalOrdersScreen(kind: HistoricalOrdersKind.cancelled),
      ),
      GoRoute(
        path: '/app/orders/:id',
        builder: (_, state) =>
            Scaffold(body: Text('detail ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentLocationProvider.overrideWith(_Current.new),
        ordersRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light,
        locale: Locale(language),
        supportedLocales: AdminLocalizations.supportedLocales,
        localizationsDelegates: const [
          AdminLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return router;
}

void main() {
  setUpAll(PelinesTime.initialize);
  for (final language in ['en', 'es']) {
    for (final (width, scale) in [
      (320.0, 2.0),
      (768.0, 1.0),
      (1366.0, 1.0),
      (1180.0, 2.0),
    ]) {
      for (final page in ['completed', 'cancelled']) {
        testWidgets('$page adaptive hierarchy $width/$scale/$language', (
          tester,
        ) async {
          final router = await _mount(
            tester,
            _Repo(),
            page,
            width: width,
            scale: scale,
            language: language,
          );
          expect(find.byType(DataTable), findsNothing);
          expect(find.byKey(const ValueKey('history-row-one')), findsOneWidget);
          expect(find.text('María Customer'), findsNWidgets(2));
          expect(find.text('Celebración familiar'), findsNothing);
          expect(
            find.byIcon(
              page == 'completed' ? Icons.check_circle : Icons.cancel,
            ),
            findsNWidgets(2),
          );
          expect(
            find.text(language == 'es' ? 'Reembolsado' : 'Refunded'),
            findsNothing,
          );
          expect(find.byKey(const Key('order-primary-action')), findsNothing);
          final view = find.byKey(const ValueKey('history-row-one'));
          await tester.ensureVisible(view);
          await tester.pumpAndSettle();
          expect(tester.getSize(view).height, greaterThanOrEqualTo(48));
          expect(tester.takeException(), isNull);
          await tester.tap(view);
          await tester.pumpAndSettle();
          expect(find.text('detail one'), findsOneWidget);
          router.pop();
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('history-shared-surface')),
            findsOneWidget,
          );
        });
      }
      testWidgets('Calendar month agenda layout $width/$scale/$language', (
        tester,
      ) async {
        final repo = _Repo();
        await _mount(
          tester,
          repo,
          'calendar',
          width: width,
          scale: scale,
          language: language,
        );
        expect(
          tester
              .widget<Semantics>(
                find
                    .ancestor(
                      of: find.byKey(const Key('calendar-view-Today')),
                      matching: find.byType(Semantics),
                    )
                    .first,
              )
              .properties
              .selected,
          isTrue,
        );
        expect(find.byType(CalendarMonthGrid), findsNothing);
        final monthTab = find.byKey(const Key('calendar-view-Month'));
        await tester.ensureVisible(monthTab);
        await tester.tap(monthTab);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Semantics>(
                find
                    .ancestor(of: monthTab, matching: find.byType(Semantics))
                    .first,
              )
              .properties
              .selected,
          isTrue,
        );
        final wide = width - 32 >= 1000 * scale;
        expect(
          find.byKey(const Key('calendar-wide-layout')),
          wide ? findsOneWidget : findsNothing,
        );
        expect(find.byType(CalendarMonthGrid), findsOneWidget);
        expect(
          find.descendant(
            of: monthTab,
            matching: find.text(language == 'es' ? 'Mes' : 'Month'),
          ),
          findsOneWidget,
        );
        final picker = tester.widget<CalendarMonthGrid>(
          find.byType(CalendarMonthGrid),
        );
        // Date selection must change the agenda without an API request.
        final today = picker.selectedDay;
        picker.onDateChanged(today.add(const Duration(days: 1)));
        await tester.pumpAndSettle();
        expect(
          find.text(
            language == 'es'
                ? 'No hay pedidos programados para este día.'
                : 'No orders scheduled for this day.',
          ),
          findsOneWidget,
        );
        expect(find.text('ORD-one'), findsNothing);
        expect(find.text('ORD-two'), findsNothing);
        expect(repo.calls, 1);
        // ASAP belongs to its Pacific operational day, not every day's agenda.
        final asapDay = pacificDate(
          repo.now.subtract(const Duration(days: 90)),
        );
        picker.onDateChanged(
          DateTime(asapDay.year, asapDay.month, asapDay.day),
        );
        await tester.pumpAndSettle();
        expect(find.text('ORD-two'), findsOneWidget);
        expect(find.text('ASAP'), findsOneWidget);
        expect(find.text('ORD-one'), findsNothing);
        expect(repo.calls, 1);
        picker.onDateChanged(today);
        await tester.pumpAndSettle();
        expect(find.text('ORD-two'), findsNothing);
        expect(repo.calls, 1);
        final order = find.text('ORD-one');
        await tester.ensureVisible(order);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(order);
        await tester.pumpAndSettle();
        expect(find.text('detail one'), findsOneWidget);
      });
    }
  }
  for (final page in ['calendar', 'completed', 'cancelled']) {
    testWidgets('$page loading empty and refresh error remain distinct', (
      tester,
    ) async {
      final repo = _Repo()
        ..empty = true
        ..hold = Completer<void>();
      await _mount(tester, repo, page, settle: false);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      repo.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.textContaining(
          page == 'calendar' ? 'No scheduled orders' : 'No $page orders',
        ),
        findsOneWidget,
      );
      repo.fail = true;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.textContaining('offline Block 5'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      repo.fail = false;
      repo.empty = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.textContaining('offline Block 5'), findsNothing);
      expect(find.text('ORD-one'), findsOneWidget);
    });
  }
  testWidgets('Completed Today uses completion instead of placed date', (
    tester,
  ) async {
    final repo = _Repo();
    await _mount(tester, repo, 'completed');
    await tester.tap(find.byKey(const Key('history-date-range')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-range-apply')));
    await tester.pumpAndSettle();
    expect(find.text('ORD-one'), findsOneWidget);
    expect(find.text('ORD-two'), findsNothing);
    expect(repo.calls, 1);
  });
  testWidgets('Cancelled keeps orders across financial states without hidden filters', (
    tester,
  ) async {
    final repo = _Repo();
    await _mount(tester, repo, 'cancelled', width: 1366);
    expect(find.byType(PopupMenuButton<PaymentStatus?>), findsNothing);
    expect(find.text('ORD-one'), findsOneWidget);
    expect(find.text('Refunded'), findsNothing);
    expect(find.text('Paid'), findsNothing);
    expect(repo.calls, 1);
    expect(find.text('ORD-two'), findsOneWidget);
  });
}
