import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:pelines_admin_app/app/navigation/navigation_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/l10n/locale_controller.dart';
import 'package:pelines_admin_app/app/l10n/language_toggle.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/app/navigation/admin_navigation.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_providers.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_controller.dart';
import 'package:pelines_admin_app/features/auth/models/admin_session.dart';
import 'package:pelines_admin_app/features/account/models/profile.dart';
import 'package:pelines_admin_app/features/account/presentation/admin_home_screen.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';
import 'package:pelines_admin_app/features/locations/presentation/pelines_location_selector.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/locations/data/location_selection_store.dart';

class _NavigationStore implements NavigationPreferencesStore {
  bool? value;
  @override
  Future<bool?> readCollapsed() async => value;
  @override
  Future<void> writeCollapsed(bool collapsed) async {
    value = collapsed;
  }
}

class _DelayedNavigationStore extends _NavigationStore {
  final read = Completer<bool?>();
  final firstWrite = Completer<void>();
  final writes = <bool>[];
  @override
  Future<bool?> readCollapsed() => read.future;
  @override
  Future<void> writeCollapsed(bool collapsed) async {
    writes.add(collapsed);
    if (writes.length == 1) await firstWrite.future;
    value = collapsed;
  }
}

class _LanguageStore implements LanguageStore {
  String value = 'en';
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String language) async {
    value = language;
  }
}

class _Today extends TodayOrdersController {
  @override
  Future<TodayOrdersState> build() async => const TodayOrdersState(orders: []);
}

class _Calendar extends CalendarOrdersController {
  @override
  Future<HistoricalOrdersState> build() async =>
      const HistoricalOrdersState(orders: []);
}

Location _location(String id, {bool active = true}) => Location(
  id: id,
  name: id,
  slug: id,
  address: '123 Main St, $id, OR 97060',
  isActive: active,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  isAcceptingOrders: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _Locations extends LocationsController {
  @override
  Future<List<Location>> build() async => [
    _location('Troutdale'),
    _location('Tualatin'),
    _location('Inactive', active: false),
  ];
}

class _SelectionStore implements LocationSelectionStore {
  String? value = 'Troutdale';
  @override
  Future<String?> readLocationId() async => value;
  @override
  Future<void> writeLocationId(String id) async {
    value = id;
  }

  @override
  Future<void> clearLocationId() async {
    value = null;
  }
}

class _Auth extends AuthController {
  int signOutCalls = 0;
  @override
  Future<AdminSession?> build() async => AdminSession(
    email: 'employee@pelines.test',
    profile: Profile(
      id: 'admin',
      role: ProfileRole.admin,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  );
  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

GoRouter _router({
  String initial = '/app',
  bool realOrders = false,
  AdminNavigationController? controller,
}) {
  final navigation = controller ?? AdminNavigationController();
  return GoRouter(
    initialLocation: initial,
    routes: [
      ShellRoute(
        observers: [navigation],
        builder: (context, state, child) => AdminNavigationShell(
          controller: navigation,
          path: state.uri.path,
          upcoming: state.uri.queryParameters['view'] == 'upcoming',
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/app',
            builder: (_, state) => realOrders
                ? AdminHomeScreen(
                    upcoming: state.uri.queryParameters['view'] == 'upcoming',
                  )
                : const _Page('Orders'),
            routes: [
              for (final destination in AdminDestination.values.where(
                (d) => d != AdminDestination.orders,
              ))
                GoRoute(
                  path: destination.path.substring(5),
                  builder: (_, _) => _Page(destination.label),
                  routes: destination == AdminDestination.menu
                      ? [
                          GoRoute(
                            path: 'edit',
                            builder: (_, _) => const _Draft(),
                          ),
                        ]
                      : [],
                ),
              GoRoute(
                path: 'orders/:id',
                builder: (_, _) => const _Page('Order Detail'),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _Page extends StatelessWidget {
  const _Page(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AdminAppBar(title: Text(title)),
    body: Center(
      child: FilledButton(
        key: const Key('open-draft'),
        onPressed: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const _Draft())),
        child: const Text('Edit draft'),
      ),
    ),
  );
}

class _Draft extends StatelessWidget {
  const _Draft();
  @override
  Widget build(BuildContext context) => AdminPopScope<void>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Discard changes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard == true && context.mounted) Navigator.pop(context);
    },
    child: Scaffold(
      appBar: const AdminAppBar(title: Text('Draft')),
      body: TextField(
        controller: null,
        decoration: const InputDecoration(labelText: 'Draft text'),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  GoRouter router, {
  double scale = 1,
  _SelectionStore? selectionStore,
  _LanguageStore? languageStore,
  _Auth? auth,
  NavigationPreferencesStore? navigationStore,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        navigationPreferencesStoreProvider.overrideWithValue(
          navigationStore ?? _NavigationStore(),
        ),
        languageStoreProvider.overrideWithValue(
          languageStore ?? _LanguageStore(),
        ),
        locationsProvider.overrideWith(_Locations.new),
        todayOrdersProvider.overrideWith(_Today.new),
        calendarOrdersProvider.overrideWith(_Calendar.new),
        locationSelectionStoreProvider.overrideWithValue(
          selectionStore ?? _SelectionStore(),
        ),
        authControllerProvider.overrideWith(() => auth ?? _Auth()),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          locale: ref.watch(localeProvider),
          supportedLocales: AdminLocalizations.supportedLocales,
          localizationsDelegates: const [
            AdminLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _showDestination(WidgetTester tester, String name) async {
  final scroll = find
      .descendant(
        of: find.byKey(const Key('admin-navigation-list')),
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(scroll).position.jumpTo(0);
  await tester.pumpAndSettle();
  final button = find.byKey(Key('nav-$name'));
  if (find.byKey(const Key('admin-rail')).evaluate().isNotEmpty &&
      name != 'orders') {
    final group =
        ['upcoming', 'calendar', 'completed', 'cancelled'].contains(name)
        ? 'orders'
        : ['analytics', 'account'].contains(name)
        ? name
        : 'store';
    if (button.evaluate().isEmpty) {
      final header = find.byKey(Key('nav-group-$group'));
      await tester.scrollUntilVisible(header, 150, scrollable: scroll);
      await tester.tap(header);
      await tester.pumpAndSettle();
    }
    await Scrollable.ensureVisible(tester.element(button), alignment: .5);
    await tester.pumpAndSettle();
    return;
  }
  if (find.byKey(const Key('admin-rail')).evaluate().isEmpty &&
      button.evaluate().isEmpty) {
    final group =
        [
          'orders',
          'upcoming',
          'calendar',
          'completed',
          'cancelled',
        ].contains(name)
        ? 'orders'
        : ['analytics', 'account'].contains(name)
        ? name
        : 'store';
    final header = find.byKey(Key('nav-group-$group'));
    await tester.scrollUntilVisible(header, 150, scrollable: scroll);
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    // Scrolling can rebuild an already-expanded group previously offscreen.
    if (button.evaluate().isEmpty) {
      await tester.tap(header);
      await tester.pumpAndSettle();
    }
  }
  await tester.scrollUntilVisible(button, 150, scrollable: scroll);
  await Scrollable.ensureVisible(tester.element(button), alignment: .5);
  await tester.pumpAndSettle();
}

Future<void> _tapDestination(WidgetTester tester, String name) async {
  await _showDestination(tester, name);
  await tester.tap(find.byKey(Key('nav-$name')));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'navigation uses local SharedPreferences and restores its value',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalNavigationPreferencesStore();
      expect(await store.readCollapsed(), null);
      await store.writeCollapsed(true);
      expect(await LocalNavigationPreferencesStore().readCollapsed(), true);
      await store.writeCollapsed(false);
      expect(await LocalNavigationPreferencesStore().readCollapsed(), false);
      SharedPreferences.setMockInitialValues({});
    },
  );
  test(
    'late load cannot override manual choice; rapid writes stay ordered',
    () async {
      final store = _DelayedNavigationStore();
      final container = ProviderContainer(
        overrides: [
          navigationPreferencesStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(navigationCollapsedProvider), null);
      final controller = container.read(navigationCollapsedProvider.notifier);
      final first = controller.select(true);
      final last = controller.select(false);
      store.read.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(navigationCollapsedProvider), false);
      expect(store.writes, [true]);
      store.firstWrite.complete();
      await Future.wait([first, last]);
      expect(store.writes, [true, false]);
      expect(store.value, false);
    },
  );
  testWidgets(
    'manual preference survives widths and remount; phone ignores it',
    (tester) async {
      final store = _NavigationStore();
      final router = _router(initial: '/app?view=upcoming');
      addTearDown(router.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      await _pump(tester, router, navigationStore: store);
      expect(find.byKey(const Key('admin-sidebar')), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin-toggle-navigation')));
      await tester.pumpAndSettle();
      expect(store.value, true);
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/app?view=upcoming',
      );
      await tester.binding.setSurfaceSize(const Size(768, 1000));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-rail')), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin-toggle-navigation')));
      await tester.pumpAndSettle();
      expect(store.value, false);
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-sidebar')), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin-toggle-navigation')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, router, navigationStore: store);
      expect(find.byKey(const Key('admin-rail')), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-rail')), findsNothing);
      await tester.tap(find.byKey(const Key('admin-open-drawer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-toggle-navigation')), findsNothing);
      expect(find.byKey(const Key('nav-group-orders')), findsOneWidget);
      expect(find.byKey(const Key('nav-upcoming')), findsOneWidget);
      expect(store.value, true);
    },
  );
  for (final width in [768.0, 1024.0, 1366.0]) {
    for (final language in ['en', 'es']) {
      testWidgets(
        'five rail categories and all touch flyouts $width/$language 2x',
        (tester) async {
          await tester.binding.setSurfaceSize(
            Size(width, width == 1024 ? 768 : 1024),
          );
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final router = _router(initial: '/app?view=upcoming');
          addTearDown(router.dispose);
          await _pump(
            tester,
            router,
            scale: 2,
            navigationStore: _NavigationStore()..value = true,
            languageStore: _LanguageStore()..value = language,
          );
          const groups = {
            'orders': ['upcoming', 'calendar', 'completed', 'cancelled'],
            'analytics': ['analytics'],
            'store': [
              'menu',
              'regularMenu',
              'operations',
              'promotions',
              'pickup',
              'delivery',
              'printing',
            ],
            'account': ['account'],
          };
          final positions = <double>[];
          final semantics = tester.ensureSemantics();
          await tester.pump();
          for (final id in [
            'orders',
            'group-orders',
            'group-analytics',
            'group-store',
            'group-account',
          ]) {
            final finder = find.byKey(Key('nav-$id'));
            positions.add(tester.getTopLeft(finder).dy);
            expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
            expect(tester.getSize(finder).width, greaterThanOrEqualTo(48));
            expect(tester.widget<IconButton>(finder).tooltip, isNotEmpty);
            expect(
              tester
                  .getSemantics(find.byKey(Key('nav-semantics-$id')))
                  .getSemanticsData()
                  .label,
              contains(tester.widget<IconButton>(finder).tooltip!),
            );
          }
          expect(positions, orderedEquals([...positions]..sort()));
          semantics.dispose();
          expect(find.byTooltip('employee@pelines.test'), findsOneWidget);
          for (final entry in groups.entries) {
            await tester.tap(find.byKey(Key('nav-group-${entry.key}')));
            await tester.pumpAndSettle();
            final header = find.byKey(Key('nav-flyout-${entry.key}'));
            expect(header.hitTestable(), findsOneWidget);
            final title = tester.widget<Text>(
              find.descendant(of: header, matching: find.byType(Text)),
            );
            expect(
              title.data,
              tester
                  .widget<IconButton>(find.byKey(Key('nav-group-${entry.key}')))
                  .tooltip,
            );
            expect(title.style!.color, PelinesColors.textSecondary);
            expect(title.style!.fontWeight, FontWeight.w600);
            final headerSemantics = tester.ensureSemantics();
            try {
              await tester.pump();
              final data = tester.getSemantics(header).getSemanticsData();
              expect(data.flagsCollection.isHeader, isTrue);
              expect(data.flagsCollection.isButton, isFalse);
              expect(data.hasAction(SemanticsAction.tap), isFalse);
            } finally {
              headerSemantics.dispose();
            }
            expect(
              find.descendant(of: header, matching: find.byType(MouseRegion)),
              findsNothing,
            );
            await tester.tap(header);
            await tester.pumpAndSettle();
            expect(header, findsOneWidget);
            expect(
              router.routeInformationProvider.value.uri.toString(),
              '/app?view=upcoming',
            );
            final ys = <double>[];
            for (final id in entry.value) {
              final item = find.byKey(Key('nav-$id'));
              expect(item, findsOneWidget);
              ys.add(tester.getTopLeft(item).dy);
              expect(tester.getSize(item).height, greaterThanOrEqualTo(48));
              await Scrollable.ensureVisible(tester.element(item));
              await tester.pumpAndSettle();
              expect(item.hitTestable(), findsOneWidget);
              final rect = tester.getRect(item);
              expect(rect.left, greaterThanOrEqualTo(76));
              expect(rect.right, lessThanOrEqualTo(width));
            }
            expect(ys, orderedEquals([...ys]..sort()));
            expect(
              router.routeInformationProvider.value.uri.toString(),
              '/app?view=upcoming',
            );
            await tester.tapAt(Offset(width - 20, 600));
            await tester.pumpAndSettle();
            expect(find.byKey(Key('nav-flyout-${entry.key}')), findsNothing);
            expect(tester.takeException(), isNull);
          }
          await _tapDestination(tester, 'pickup');
          expect(
            router.routeInformationProvider.value.uri.path,
            '/app/store/pickup-settings',
          );
          expect(find.byKey(const Key('nav-flyout-store')), findsNothing);
          await _showDestination(tester, 'pickup');
          final selected = find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.selected == true,
          );
          for (final id in ['group-store', 'pickup']) {
            expect(
              find.descendant(
                of: selected,
                matching: find.byKey(Key('nav-$id')),
              ),
              findsOneWidget,
            );
          }
        },
      );
    }
  }
  testWidgets('hover, group switching, Escape and keyboard activation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = _router();
    addTearDown(router.dispose);
    await _pump(
      tester,
      router,
      navigationStore: _NavigationStore()..value = true,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1000, 700));
    await mouse.moveTo(
      tester.getCenter(find.byKey(const Key('nav-group-orders'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-flyout-orders')), findsOneWidget);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const Key('nav-group-store'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-flyout-orders')), findsNothing);
    expect(find.byKey(const Key('nav-flyout-store')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-flyout-store')), findsNothing);
    await mouse.removePointer();
    final focus = find
        .descendant(
          of: find.byKey(const Key('nav-group-account')),
          matching: find.byType(Focus),
        )
        .first;
    tester.widget<Focus>(focus).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-flyout-account')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/app/account');
    expect(find.byKey(const Key('nav-flyout-account')), findsNothing);
  });
  testWidgets(
    'collapsed location and logout keep current providers and guards',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(768, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = _router(initial: '/app/menu/catering/edit');
      addTearDown(router.dispose);
      final location = _SelectionStore();
      final auth = _Auth();
      await _pump(tester, router, selectionStore: location, auth: auth);
      await tester.enterText(find.byType(TextField), 'Keep draft');
      await tester.tap(find.byKey(const Key('location-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(location.value, 'Troutdale');
      await tester.tap(find.byKey(const Key('location-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Tualatin'));
      await tester.pumpAndSettle();
      expect(location.value, 'Tualatin');
      expect(find.byTooltip('Tualatin'), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logout-confirm')));
      await tester.pumpAndSettle();
      expect(auth.signOutCalls, 1);
    },
  );
  for (final lang in ['en', 'es']) {
    testWidgets('Store exact order, labels and navigation $lang', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = _router();
      addTearDown(router.dispose);
      await _pump(
        tester,
        router,
        languageStore: _LanguageStore()..value = lang,
      );
      const destinations = [
        AdminDestination.menu,
        AdminDestination.regularMenu,
        AdminDestination.operations,
        AdminDestination.promotions,
        AdminDestination.pickup,
        AdminDestination.delivery,
        AdminDestination.printing,
      ];
      final labels = lang == 'en'
          ? [
              'Catering Menu',
              'Regular Menu',
              'Locations',
              'Promotions',
              'Pickup Settings',
              'Delivery Settings',
              'Printer Settings',
            ]
          : [
              'Menú de catering',
              'Menú regular',
              'Ubicaciones',
              'Promociones',
              'Configuración de pickup',
              'Configuración de entrega',
              'Configuración de impresora',
            ];
      await _showDestination(tester, 'menu');
      final positions = [
        for (final d in destinations)
          tester.getTopLeft(find.byKey(Key('nav-${d.name}'))).dy,
      ];
      for (var i = 1; i < positions.length; i++) {
        expect(positions[i], greaterThan(positions[i - 1]));
      }
      for (var i = 0; i < destinations.length; i++) {
        final d = destinations[i];
        final item = find.byKey(Key('nav-${d.name}'));
        expect(
          find.descendant(of: item, matching: find.text(labels[i])),
          findsOneWidget,
        );
        await _tapDestination(tester, d.name);
        expect(router.routeInformationProvider.value.uri.path, d.path);
        expect(AdminDestination.forPath(d.path), d);
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Store Operations'), findsNothing);
    });
  }
  for (final width in [390.0, 1180.0]) {
    for (final language in ['en', 'es']) {
      testWidgets(
        'Analytics and Account groups toggle without navigating at $width/$language',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final router = _router();
          addTearDown(router.dispose);
          await _pump(
            tester,
            router,
            scale: 2,
            languageStore: _LanguageStore()..value = language,
          );
          if (width < 600) {
            await tester.tap(find.byKey(const Key('admin-open-drawer')));
            await tester.pumpAndSettle();
          }
          for (final name in ['analytics', 'account']) {
            final header = find.byKey(Key('nav-group-$name'));
            final child = find.byKey(Key('nav-$name'));
            final scroll = find
                .descendant(
                  of: find.byKey(const Key('admin-navigation-list')),
                  matching: find.byType(Scrollable),
                )
                .first;
            await tester.scrollUntilVisible(header, 150, scrollable: scroll);
            await Scrollable.ensureVisible(
              tester.element(header),
              alignment: .2,
            );
            await tester.pumpAndSettle();
            final previous = router.routeInformationProvider.value.uri;
            expect(child, findsNothing);
            expect(
              find.descendant(
                of: header,
                matching: find.byIcon(Icons.expand_more),
              ),
              findsOneWidget,
            );
            await tester.tap(header);
            await tester.pumpAndSettle();
            expect(router.routeInformationProvider.value.uri, previous);
            expect(
              find.descendant(
                of: header,
                matching: find.byIcon(Icons.expand_less),
              ),
              findsOneWidget,
            );
            expect(child, findsOneWidget);
            final label = name == 'analytics'
                ? (language == 'es' ? 'Analíticas' : 'Analytics')
                : (language == 'es' ? 'Mi perfil' : 'My Profile');
            expect(
              find.descendant(of: child, matching: find.text(label)),
              findsOneWidget,
            );
            await tester.tap(header);
            await tester.pumpAndSettle();
            expect(child, findsNothing);
            expect(router.routeInformationProvider.value.uri, previous);
            await _tapDestination(tester, name);
            expect(
              router.routeInformationProvider.value.uri.path,
              '/app/$name',
            );
            if (width < 600) {
              expect(find.byType(Drawer).hitTestable(), findsNothing);
              await tester.tap(find.byKey(const Key('admin-open-drawer')));
              await tester.pumpAndSettle();
            }
            await _showDestination(tester, name);
            final selected = find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.selected == true,
            );
            expect(
              find.descendant(of: selected, matching: child),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: header,
                matching: find.byIcon(Icons.expand_less),
              ),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
  test('location locality never displays a street or invents a state', () {
    expect(
      locationCityState('123 Main St, Troutdale, OR 97060'),
      'Troutdale, OR',
    );
    expect(
      locationCityState('456 Main St\nTualatin, OR 97062, USA'),
      'Tualatin, OR',
    );
    expect(locationCityState('123 Main St'), isNull);
    expect(locationCityState(null), isNull);
  });

  for (final (width, scale) in [
    (320.0, 1.0),
    (390.0, 1.0),
    (390.0, 2.0),
    (599.0, 2.0),
  ]) {
    testWidgets(
      'compact phone drawer geometry hierarchy and dismiss at $width/$scale',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final router = _router();
        addTearDown(router.dispose);
        final auth = _Auth();
        final language = _LanguageStore()..value = 'es';
        await _pump(
          tester,
          router,
          scale: scale,
          languageStore: language,
          auth: auth,
        );
        await tester.tap(find.byKey(const Key('admin-open-drawer')));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(Drawer)).width, 280);
        expect(tester.getSize(find.byKey(const Key('admin-logo'))).height, 40);
        expect(find.text('Pelines Troutdale'), findsOneWidget);
        expect(find.text('Troutdale, OR'), findsOneWidget);
        expect(find.text('123 Main St, Troutdale, OR 97060'), findsNothing);
        final keys = [
          'nav-orders',
          'nav-group-orders',
          'nav-group-analytics',
          'nav-group-store',
          'nav-group-account',
        ];
        for (var i = 1; i < keys.length; i++) {
          expect(
            tester.getTopLeft(find.byKey(Key(keys[i]))).dy,
            greaterThan(tester.getTopLeft(find.byKey(Key(keys[i - 1]))).dy),
          );
        }
        for (final label in [
          'Por hacer',
          'Órdenes',
          'Analíticas',
          'Tienda',
          'Cuenta',
          'Cerrar sesión',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        for (final key in [
          'nav-orders',
          'nav-group-orders',
          'admin-close-drawer',
          'admin-sign-out',
        ]) {
          expect(
            tester.getSize(find.byKey(Key(key))).height,
            greaterThanOrEqualTo(48),
          );
        }
        if (scale == 1) {
          expect(
            tester.getSize(find.byKey(const Key('nav-surface-orders'))).height,
            36,
          );
          expect(
            tester
                .getSize(find.byKey(const Key('nav-surface-sign-out')))
                .height,
            36,
          );
        }
        final surface = tester.widget<Ink>(
          find.byKey(const Key('nav-surface-orders')),
        );
        expect(
          (surface.decoration! as BoxDecoration).color,
          AppTheme.light.colorScheme.primaryContainer,
        );
        await tester.tap(find.byKey(const Key('nav-group-orders')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('nav-submenu-orders')), findsOneWidget);
        for (final label in [
          'Próximas',
          'Calendario',
          'Completadas',
          'Canceladas',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        await tester.tap(find.byKey(const Key('admin-close-drawer')));
        await tester.pumpAndSettle();
        expect(find.byType(Drawer).hitTestable(), findsNothing);
        expect(router.routeInformationProvider.value.uri.path, '/app');
        await tester.tap(find.byKey(const Key('admin-open-drawer')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('admin-sign-out')));
        await tester.pumpAndSettle();
        expect(auth.signOutCalls, 0);
        await tester.tap(find.byKey(const Key('logout-confirm')));
        await tester.pumpAndSettle();
        expect(auth.signOutCalls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Upcoming and To Do reuse Orders with its existing date filter', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = _router(realOrders: true);
    addTearDown(router.dispose);
    await _pump(tester, router);
    final date = find.byKey(const Key('upcoming-filters'));
    expect(date, findsNothing);
    await tester.tap(find.byKey(const Key('admin-open-drawer')));
    await tester.pumpAndSettle();
    await _tapDestination(tester, 'upcoming');
    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/app?view=upcoming',
    );
    expect(find.byType(AdminHomeScreen), findsOneWidget);
    expect(date, findsOneWidget);
    await tester.tap(find.byKey(const Key('admin-open-drawer')));
    await tester.pumpAndSettle();
    await _tapDestination(tester, 'orders');
    expect(router.routeInformationProvider.value.uri.toString(), '/app');
    expect(date, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 768.0]) {
    for (final language in ['en', 'es']) {
      testWidgets('Upcoming title and controls at $width/2x/$language', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final router = _router(realOrders: true, initial: '/app?view=upcoming');
        addTearDown(router.dispose);
        await _pump(
          tester,
          router,
          scale: 2,
          languageStore: _LanguageStore()..value = language,
        );
        expect(
          find.descendant(
            of: find.byType(AdminAppBar),
            matching: find.text(language == 'es' ? 'Próximas' : 'Upcoming'),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('orders-header-refresh')), findsOneWidget);
        expect(find.byKey(const Key('orders-search')), findsOneWidget);
        expect(find.byKey(const Key('upcoming-filters')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('Upcoming shortcut honors an existing draft guard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = _router(initial: '/app/menu/catering/edit');
    addTearDown(router.dispose);
    await _pump(tester, router);
    await tester.enterText(find.byType(TextField), 'Keep draft');
    await tester.tap(find.byKey(const Key('admin-open-drawer')));
    await tester.pumpAndSettle();
    await _tapDestination(tester, 'upcoming');
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/app/menu/catering/edit',
    );
    expect(find.text('Keep draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final (width, scale) in [
    (320.0, 2.0),
    (768.0, 2.0),
    (1180.0, 1.0),
    (1440.0, 2.0),
  ]) {
    testWidgets(
      'web shell logo context dimensions and topbar at $width/$scale',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final router = _router();
        addTearDown(router.dispose);
        await _pump(tester, router, scale: scale);
        expect(
          tester.getSize(find.byKey(const Key('admin-topbar'))).height,
          greaterThanOrEqualTo(56),
        );
        expect(find.byType(LanguageToggle), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('admin-topbar')),
            matching: find.byKey(const Key('location-selector')),
          ),
          findsNothing,
        );
        if (width < 600) {
          await tester.tap(find.byKey(const Key('admin-open-drawer')));
          await tester.pumpAndSettle();
          expect(tester.getSize(find.byType(Drawer)).width, 280);
        } else {
          final key = width < 900 ? 'admin-rail' : 'admin-sidebar';
          expect(
            tester.getSize(find.byKey(Key(key))).width,
            width < 900 ? 76 : 260,
          );
        }
        expect(find.byKey(const Key('admin-logo')), findsOneWidget);
        if (width >= 900) {
          expect(find.text('employee@pelines.test'), findsOneWidget);
          expect(find.byKey(const Key('nav-group-orders')), findsOneWidget);
          expect(find.byKey(const Key('nav-printing')), findsNothing);
          await _showDestination(tester, 'printing');
          expect(find.byKey(const Key('nav-group-store')), findsOneWidget);
          expect(
            find.byKey(const Key('nav-printing')).hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const Key('admin-toggle-navigation')));
          await tester.pumpAndSettle();
          expect(tester.getSize(find.byKey(const Key('admin-rail'))).width, 76);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'shell location selection reuses persistence and excludes inactive locations',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = _router();
      addTearDown(router.dispose);
      final store = _SelectionStore();
      await _pump(tester, router, selectionStore: store);
      await tester.tap(find.byKey(const Key('location-selector')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListTile>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is ListTile &&
                    widget.title is Text &&
                    (widget.title! as Text).data == 'Inactive',
              ),
            )
            .onTap,
        isNull,
      );
      await tester.tap(find.widgetWithText(ListTile, 'Tualatin'));
      await tester.pumpAndSettle();
      expect(store.value, 'Tualatin');
      expect(find.text('Tualatin'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, '/app');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'location and logout honor the draft guard before changing context',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = _router(initial: '/app/menu/catering/edit');
      addTearDown(router.dispose);
      final store = _SelectionStore();
      final auth = _Auth();
      await _pump(tester, router, selectionStore: store, auth: auth);
      await tester.enterText(find.byType(TextField), 'Keep context');
      await tester.tap(find.byKey(const Key('location-selector')));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(store.value, 'Troutdale');
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.byKey(const Key('admin-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logout-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(auth.signOutCalls, 0);
      expect(find.text('Keep context'), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logout-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(auth.signOutCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('topbar language choice persists across remount', (tester) async {
    final store = _LanguageStore();
    final router = _router();
    addTearDown(router.dispose);
    await _pump(tester, router, languageStore: store);
    await tester.tap(find.byKey(const Key('language-es')));
    await tester.pumpAndSettle();
    expect(store.value, 'es');
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, router, languageStore: store);
    expect(find.byTooltip('Idioma'), findsOneWidget);
    await _showDestination(tester, 'calendar');
    expect(find.text('Calendario'), findsOneWidget);
  });
  test(
    'Analytics is between Orders and Calendar and resolves its selected state',
    () {
      expect(AdminDestination.values.take(3), [
        AdminDestination.orders,
        AdminDestination.analytics,
        AdminDestination.calendar,
      ]);
      expect(
        AdminDestination.forPath('/app/analytics'),
        AdminDestination.analytics,
      );
      expect(
        AdminDestination.forPath('/app/analytics?range=7'),
        AdminDestination.analytics,
      );
    },
  );
  for (final width in [390.0, 768.0, 1366.0]) {
    testWidgets('Orders Analytics Calendar uses shared navigation at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = _router();
      addTearDown(router.dispose);
      await _pump(tester, router, scale: width == 768 ? 2 : 1);
      Future<void> openDrawer() async {
        if (width < 600) {
          await tester.tap(find.byKey(const Key('admin-open-drawer')));
          await tester.pumpAndSettle();
        }
      }

      await openDrawer();
      await _tapDestination(tester, 'analytics');
      expect(router.routeInformationProvider.value.uri.path, '/app/analytics');
      await openDrawer();
      await _showDestination(tester, 'analytics');
      final selected = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.selected == true,
      );
      expect(
        find.descendant(
          of: selected,
          matching: find.byKey(const Key('nav-analytics')),
        ),
        findsOneWidget,
      );
      if (width >= 600) {
        await tester.tap(find.byKey(const Key('admin-toggle-navigation')));
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/app/analytics',
        );
      }
      await _tapDestination(tester, 'calendar');
      expect(
        router.routeInformationProvider.value.uri.path,
        '/app/orders/calendar',
      );
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [390.0, 768.0, 1366.0]) {
    testWidgets('topbar language changes immediately at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = _router();
      addTearDown(router.dispose);
      await _pump(tester, router, scale: width == 768 ? 2 : 1);
      expect(
        find.descendant(
          of: find.byKey(const Key('admin-topbar')),
          matching: find.byType(LanguageToggle),
        ),
        findsOneWidget,
      );
      for (final language in ['en', 'es', 'en']) {
        await tester.tap(find.byKey(Key('language-$language')));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/app');
        expect(
          find.byTooltip(language == 'es' ? 'Idioma' : 'Language'),
          findsOneWidget,
        );
        if (width < 600) {
          await tester.tap(find.byKey(const Key('admin-open-drawer')));
          await tester.pumpAndSettle();
        }
        for (final destination in AdminDestination.values) {
          await _showDestination(tester, destination.name);
          final item = find.byKey(Key('nav-${destination.name}'));
          final label = destination == AdminDestination.orders
              ? tr(tester.element(item), 'To Do')
              : destination == AdminDestination.account
              ? tr(tester.element(item), 'My Profile')
              : destination.localizedLabel(tester.element(item));
          if (find.byKey(const Key('admin-rail')).evaluate().isNotEmpty &&
              destination == AdminDestination.orders) {
            expect(find.byTooltip(label), findsOneWidget);
          } else {
            expect(
              find.descendant(of: item, matching: find.text(label)),
              findsOneWidget,
            );
          }
        }
        expect(tester.takeException(), isNull);
        if (width < 600) {
          Navigator.of(tester.element(find.byKey(const Key('admin-drawer'))))
              .pop();
          await tester.pumpAndSettle();
        }
      }
    });
  }
  testWidgets('phone drawer control stays left and preserves Back', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = _router(initial: '/app/menu/catering/edit');
    addTearDown(router.dispose);
    await _pump(tester, router);
    final drawer = find.byKey(const Key('admin-open-drawer'));
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    expect(find.byTooltip('Open navigation'), findsOneWidget);
    expect(tester.getCenter(drawer).dx, lessThan(56));
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(drawer);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-drawer')).hitTestable(), findsOneWidget);
    Navigator.of(tester.element(find.byType(Drawer))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/app/menu/catering/edit',
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [600.0, 1024.0]) {
    testWidgets('left panel toggle preserves draft and route at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = _router(initial: '/app/menu/catering/edit');
      addTearDown(router.dispose);
      await _pump(tester, router, scale: 2);
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      await tester.pump();
      final toggle = find.byKey(const Key('admin-toggle-navigation'));
      final initiallyRail = width < 900;
      expect(
        find.byIcon(
          initiallyRail ? Icons.view_sidebar_outlined : Icons.view_sidebar,
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.menu_rounded), findsNothing);
      expect(tester.getCenter(toggle).dx, lessThan(initiallyRail ? 76 : 260));
      expect(
        find.byTooltip(
          initiallyRail ? 'Expand navigation' : 'Collapse navigation',
        ),
        findsOneWidget,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        find.byIcon(
          initiallyRail ? Icons.view_sidebar : Icons.view_sidebar_outlined,
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(Key(initiallyRail ? 'admin-sidebar' : 'admin-rail')),
        findsOneWidget,
      );
      expect(
        find.byTooltip(
          initiallyRail ? 'Collapse navigation' : 'Expand navigation',
        ),
        findsOneWidget,
      );
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/app/menu/catering/edit',
      );
      final selected = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.selected == true,
      );
      await _showDestination(tester, 'menu');
      expect(
        find.descendant(
          of: selected,
          matching: find.byKey(const Key('nav-menu')),
        ),
        findsOneWidget,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key(initiallyRail ? 'admin-rail' : 'admin-sidebar')),
        findsOneWidget,
      );
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'explicit paths select their section and respect segment boundaries',
    () {
      for (final destination in AdminDestination.values) {
        expect(AdminDestination.forPath(destination.path), destination);
      }
      expect(
        AdminDestination.forPath(
          '/app/menu/store/categories/a/products/b/edit',
        ),
        AdminDestination.regularMenu,
      );
      expect(
        AdminDestination.forPath('/app/promotions/a/edit'),
        AdminDestination.promotions,
      );
      expect(
        AdminDestination.forPath('/app/store-operations/hours'),
        AdminDestination.operations,
      );
      expect(
        AdminDestination.forPath('/app/orders/order-id'),
        AdminDestination.orders,
      );
      expect(
        AdminDestination.forPath('/app/orders/calendar?date=2026-09-12'),
        AdminDestination.calendar,
      );
    },
  );

  for (final (width, scale, variant) in <(double, double, String)>[
    (390, 1, 'drawer'),
    (600, 1, 'rail'),
    (768, 2, 'rail'),
    (1024, 1, 'sidebar'),
    (1366, 1, 'sidebar'),
  ]) {
    testWidgets(
      '$variant at $width / $scale exposes all destinations and footer',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final router = _router();
        addTearDown(router.dispose);
        await _pump(tester, router, scale: scale);
        if (variant == 'drawer') {
          expect(find.byKey(const Key('admin-sidebar')), findsNothing);
          expect(find.byKey(const Key('admin-rail')), findsNothing);
          await tester.tap(find.byKey(const Key('admin-open-drawer')));
          await tester.pumpAndSettle();
        }
        expect(find.byKey(Key('admin-$variant')), findsOneWidget);
        for (final destination in AdminDestination.values) {
          final item = find.byKey(Key('nav-${destination.name}'));
          await _showDestination(tester, destination.name);
          await Scrollable.ensureVisible(tester.element(item), alignment: 0.5);
          await tester.pumpAndSettle();
          expect(item.hitTestable(), findsOneWidget);
          expect(tester.getSize(item).height, greaterThanOrEqualTo(48));
          expect(tester.takeException(), isNull);
        }
        expect(
          find.byKey(const Key('admin-sign-out')).hitTestable(),
          findsOneWidget,
        );
        expect(find.byKey(const Key('admin-sign-out-divider')), findsOneWidget);
        await tester.tap(find.byKey(const Key('admin-sign-out')));
        await tester.pumpAndSettle();
        expect(find.text('Log out?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('logout-cancel')));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/app');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final imperative in [false, true]) {
    testWidgets(
      '${imperative ? 'imperative' : 'declarative'} draft protects section changes',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1024, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final router = _router(
          initial: imperative
              ? '/app/menu/catering'
              : '/app/menu/catering/edit',
        );
        addTearDown(router.dispose);
        await _pump(tester, router);
        if (imperative) {
          await tester.tap(find.byKey(const Key('open-draft')));
          await tester.pumpAndSettle();
        }
        await tester.enterText(
          find.byType(TextField),
          'Unsaved restaurant draft',
        );
        final selected = find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.selected == true,
        );
        expect(
          find.descendant(
            of: selected,
            matching: find.byKey(const Key('nav-menu')),
          ),
          findsOneWidget,
        );
        await _tapDestination(tester, 'calendar');
        expect(find.text('Discard changes?'), findsOneWidget);
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();
        expect(find.text('Unsaved restaurant draft'), findsOneWidget);
        expect(
          router.routeInformationProvider.value.uri.path,
          imperative ? '/app/menu/catering' : '/app/menu/catering/edit',
        );
        await _tapDestination(tester, 'calendar');
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/app/orders/calendar',
        );
        expect(
          find.descendant(
            of: selected,
            matching: find.byKey(const Key('nav-calendar')),
          ),
          findsOneWidget,
        );
        expect(find.text('Draft'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
