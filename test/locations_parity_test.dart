import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/features/locations/data/locations_repository.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/presentation/business_hours_screen.dart';
import 'package:pelines_admin_app/features/locations/presentation/closure_form_screen.dart';
import 'package:pelines_admin_app/features/locations/presentation/store_operations_screen.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';

Location location({
  bool accepting = true,
  String id = 'a',
  bool invalidHours = false,
  bool invalidClosures = false,
}) => Location(
  id: id,
  name: 'Backend Location $id',
  slug: 'slug-$id',
  address: '123 Backend Street',
  phone: '+1 503 123 4567',
  isActive: true,
  isAcceptingOrders: accepting,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  hoursJson: invalidHours
      ? {'mon': 'invalid'}
      : {
          for (final day in ['mon', 'tue', 'wed', 'thu', 'fri', 'sat'])
            day: {'open': '09:00', 'close': '17:00'},
          'sun': null,
        },
  hoursExtrasJson: {
    'closures': invalidClosures
        ? ['invalid']
        : [
            {
              'id': 'closure-a',
              'reason': 'Backend maintenance',
              'notes': 'Backend notes',
              'start': '2026-11-01',
              'end': '2026-11-02',
              'active': true,
            },
          ],
  },
);

class Repo implements LocationsRepository {
  Location value = location();
  int writes = 0;
  Completer<void>? hold;
  @override
  Future<List<Location>> getLocations() async => [value];
  @override
  Future<Location> getLocation(String id) async => value;
  @override
  Future<Location> setAcceptingOrders(String id, bool accepting) async {
    writes++;
    await hold?.future;
    return value = location(id: id, accepting: accepting);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Current extends CurrentLocationController {
  @override
  Future<Location?> build() =>
      ref.watch(locationsRepositoryProvider).getLocation('a');
  void change(Location next) => state = AsyncData(next);
}

Future<GoRouter> mount(
  WidgetTester tester,
  Repo repo, {
  String lang = 'en',
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/app/store/locations',
    routes: [
      GoRoute(
        path: '/app/store/locations',
        builder: (_, _) => const StoreOperationsScreen(
          section: StoreOperationsSection.locations,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        locationsRepositoryProvider.overrideWithValue(repo),
        currentLocationProvider.overrideWith(Current.new),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light,
        locale: Locale(lang),
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
  await tester.pumpAndSettle();
  return router;
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isNotEmpty) {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 20 && target.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget);
}

void main() {
  for (final lang in ['en', 'es']) {
    for (final size in [
      (390.0, 1.0),
      (800.0, 1.0),
      (1440.0, 1.0),
      (320.0, 2.0),
      (800.0, 2.0),
    ]) {
      testWidgets(
        'Locations real data, isolated controls and layout $lang $size',
        (tester) async {
          final router = await mount(
            tester,
            Repo(),
            lang: lang,
            width: size.$1,
            scale: size.$2,
          );
          expect(
            router.routeInformationProvider.value.uri.path,
            '/app/store/locations',
          );
          expect(
            find.text(lang == 'en' ? 'Locations' : 'Ubicaciones'),
            findsOneWidget,
          );
          expect(
            find.text('Backend Location a · 123 Backend Street'),
            findsOneWidget,
          );
          expect(find.text('+1 503 123 4567'), findsOneWidget);
          expect(
            find.text(lang == 'en' ? 'Online Ordering' : 'Pedidos en línea'),
            findsOneWidget,
          );
          for (final key in [
            'edit-auto-accept',
            'edit-regular-delivery',
            'edit-catering-delivery',
          ]) {
            expect(find.byKey(Key(key)), findsNothing);
          }
          final hours = find.byKey(const Key('edit-business-hours'));
          await reveal(tester, hours);
          for (final day in ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']) {
            expect(find.byKey(ValueKey('location-hours-$day')), findsOneWidget);
          }
          expect(find.text(lang == 'en' ? 'Monday' : 'Lunes'), findsOneWidget);
          expect(
            find.text(lang == 'en' ? 'Closed' : 'Cerrado'),
            findsOneWidget,
          );
          expect(tester.getSize(hours).height, greaterThanOrEqualTo(48));
          final closure = find.byKey(const Key('closure-closure-a'));
          await reveal(tester, closure);
          expect(find.text('Backend maintenance'), findsOneWidget);
          expect(find.textContaining('Backend notes'), findsOneWidget);
          expect(find.textContaining('2026'), findsOneWidget);
          final add = find.byKey(const Key('add-closure'));
          await reveal(tester, add);
          expect(tester.getSize(add).height, greaterThanOrEqualTo(48));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('Locations reuses Hours and Closure editors with guards', (
    tester,
  ) async {
    await mount(tester, Repo());
    final hours = find.byKey(const Key('edit-business-hours'));
    await reveal(tester, hours);
    await tester.tap(hours);
    await tester.pumpAndSettle();
    expect(find.byType(BusinessHoursScreen), findsOneWidget);
    final day = find.byKey(const Key('business-day-0'));
    await reveal(tester, day);
    await tester.tap(day);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('locations-content')), findsOneWidget);
    final closure = find.byKey(const Key('closure-closure-a'));
    await reveal(tester, closure);
    await tester.tap(closure);
    await tester.pumpAndSettle();
    final editor = tester.widget<ClosureFormScreen>(
      find.byType(ClosureFormScreen),
    );
    expect(editor.location.id, 'a');
    expect(editor.closure!.id, 'closure-a');
    await tester.pageBack();
    await tester.pumpAndSettle();
    final add = find.byKey(const Key('add-closure'));
    await reveal(tester, add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ClosureFormScreen>(find.byType(ClosureFormScreen)).closure,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Locations pause requires confirmation and disables while saving',
    (tester) async {
      final repo = Repo()..hold = Completer<void>();
      await mount(tester, repo, lang: 'es');
      final toggle = find.byKey(const Key('accepting-orders-switch'));
      await reveal(tester, toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        find.text('¿Pausar pedidos en línea para Backend Location a?'),
        findsOneWidget,
      );
      expect(repo.writes, 0);
      await tester.tap(find.byKey(const Key('accepting-orders-cancel')));
      await tester.pumpAndSettle();
      expect(repo.writes, 0);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accepting-orders-confirm')));
      await tester.pump();
      await tester.pump();
      expect(repo.writes, 1);
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
      repo.hold!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Locations respects selected location and explicit malformed data',
    (tester) async {
      final repo = Repo()
        ..value = location(invalidHours: true, invalidClosures: true);
      await mount(tester, repo);
      await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unsupported business hours'), findsOneWidget);
      expect(find.textContaining('unsupported format'), findsOneWidget);
      expect(find.text('No temporary closures.'), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StoreOperationsScreen)),
      );
      (container.read(currentLocationProvider.notifier) as Current).change(
        location(id: 'b'),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
      await tester.pumpAndSettle();
      expect(
        find.text('Backend Location b · 123 Backend Street'),
        findsOneWidget,
      );
      expect(
        find.text('Backend Location a · 123 Backend Street'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
