import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/features/analytics/data/analytics_repository.dart';
import 'package:pelines_admin_app/features/analytics/models/analytics_order.dart';
import 'package:pelines_admin_app/features/analytics/providers/analytics_providers.dart';
import 'package:pelines_admin_app/features/analytics/presentation/analytics_screen.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_providers.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/core/time/pelines_time.dart';

import 'analytics_providers_test.dart'
    show FakeAuth, FakeLocation, makeLocation;
import 'order_test_data.dart';

class ScreenRepository implements AnalyticsRepository {
  final requests = <Completer<AnalyticsDataset>>[];
  final locations = <String>[];
  @override
  Future<AnalyticsDataset> getDataset({required String locationId}) {
    locations.add(locationId);
    final request = Completer<AnalyticsDataset>();
    requests.add(request);
    return request.future;
  }
}

class ScreenLocation extends FakeLocation {
  @override
  Future<void> select(Location location) async => setLocation(location.id);
}

class ScreenLocations extends LocationsController {
  @override
  Future<List<Location>> build() async => [
    makeLocation('a'),
    makeLocation('b'),
  ];
}

AnalyticsDataset sample({
  int count = 1,
  String location = 'a',
  String payment = 'paid',
}) => AnalyticsDataset(
  locationId: location,
  orders: List.generate(
    count,
    (i) => AnalyticsOrder.fromJson(
      orderJson(id: '$i', locationId: location, payment: payment)
        ..['createdAt'] = DateTime.now().toUtc().toIso8601String()
        ..['items'] = [
          {
            'id': 'line',
            'productId': 'p',
            'productName': 'Backend Taco',
            'unitPriceCents': 500,
            'quantity': 2,
            'lineTotalCents': 1000,
            'modifiers': [],
          },
        ],
    ),
  ),
);

void main() {
  late ScreenRepository repository;
  late ProviderContainer container;
  Future<void> mount(
    WidgetTester tester, {
    String language = 'en',
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repository = ScreenRepository();
    container = ProviderContainer(
      overrides: [
        analyticsRepositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith(FakeAuth.new),
        currentLocationProvider.overrideWith(ScreenLocation.new),
        locationsProvider.overrideWith(ScreenLocations.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
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
          home: const AnalyticsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('loading then four KPIs, local range change and refresh', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Loading analytics...'), findsOneWidget);
    repository.requests.single.complete(sample());
    await tester.pumpAndSettle();
    for (final label in ['Sales', 'Orders', 'Average Order', 'Items Sold']) {
      expect(find.byKey(Key('analytics-kpi-$label')), findsOneWidget);
    }
    expect(find.text('US\$11.00'), findsNWidgets(2));
    expect(find.text('This period is still in progress.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('analytics-last7Days')));
    await tester.pumpAndSettle();
    expect(repository.requests.length, 1);
    expect(container.read(analyticsRangeProvider).dayCount, 7);
    await tester.tap(find.byKey(const Key('analytics-refresh')));
    await tester.pump();
    expect(repository.requests.length, 2);
    repository.requests.last.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('analytics-refresh-error')), findsOneWidget);
    expect(find.text('US\$11.00'), findsNWidgets(2));
  });

  testWidgets('initial error offers retry without fake zeros', (tester) async {
    await mount(tester);
    repository.requests.single.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Analytics could not be loaded.'), findsOneWidget);
    expect(find.byKey(const Key('analytics-kpi-Sales')), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    repository.requests.last.complete(sample());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('analytics-kpi-Sales')), findsOneWidget);
  });

  testWidgets('empty displays absent average', (tester) async {
    await mount(tester);
    repository.requests.single.complete(sample(count: 0));
    await tester.pumpAndSettle();
    expect(find.text('No eligible orders in this period.'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('Spanish KPIs and truncation metadata', (tester) async {
    await mount(tester, language: 'es', width: 1100);
    repository.requests.single.complete(sample(count: 2000));
    await tester.pumpAndSettle();
    for (final text in [
      'Analíticas',
      'Ventas',
      'Pedidos',
      'Pedido promedio',
      'Artículos vendidos',
      'Actualizar',
      'Los datos pueden estar incompletos',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.textContaining('Pedido más antiguo cargado'), findsOneWidget);
    expect(find.textContaining('Pedidos cargados'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 1100.0]) {
    testWidgets('responsive columns at $width', (tester) async {
      await mount(tester, width: width);
      repository.requests.single.complete(sample());
      await tester.pumpAndSettle();
      final sales = tester.getTopLeft(
        find.byKey(const Key('analytics-kpi-Sales')),
      );
      final orders = tester.getTopLeft(
        find.byKey(const Key('analytics-kpi-Orders')),
      );
      final average = tester.getTopLeft(
        find.byKey(const Key('analytics-kpi-Average Order')),
      );
      if (width == 320) {
        expect(orders.dy, greaterThan(sales.dy));
      } else {
        expect(orders.dy, sales.dy);
        expect(average.dy, width == 1100 ? sales.dy : greaterThan(sales.dy));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('large Spanish text fits narrow phone', (tester) async {
    await mount(tester, width: 320, scale: 2, language: 'es');
    repository.requests.single.complete(sample());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('location picker changes dataset', (tester) async {
    await mount(tester);
    repository.requests.single.complete(sample());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('location-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('b'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(repository.locations, ['a', 'b']);
    repository.requests.last.complete(sample(location: 'b'));
    await tester.pumpAndSettle();
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('Custom picker saves inclusive same-day range without request', (
    tester,
  ) async {
    await mount(tester);
    repository.requests.single.complete(sample());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('analytics-custom')));
    await tester.pumpAndSettle();
    final picker = tester.widget<DateRangePickerDialog>(
      find.byType(DateRangePickerDialog),
    );
    expect(picker.initialDateRange, isNotNull);
    final now = PelinesTime.now();
    final day = DateTime(now.year, now.month, now.day);
    // Return the same calendar result the native picker returns after Save.
    Navigator.of(tester.element(find.byType(DateRangePickerDialog)))
        .pop(DateTimeRange(start: day, end: day));
    await tester.pumpAndSettle();
    expect(container.read(analyticsRangeProvider).dayCount, 1);
    expect(repository.requests.length, 1);
  });
}
