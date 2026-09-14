import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/l10n/locale_controller.dart';
import 'package:pelines_admin_app/app/l10n/language_toggle.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/app/navigation/admin_navigation.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';

class _LanguageStore implements LanguageStore {
  @override
  Future<String?> read() async => 'en';
  @override
  Future<void> write(String language) async {}
}

GoRouter _router({
  String initial = '/app',
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
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/app',
            builder: (_, _) => const _Page('Orders'),
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
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [languageStoreProvider.overrideWithValue(_LanguageStore())],
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

Future<void> _tapDestination(WidgetTester tester, String name) async {
  final button = find.byKey(Key('nav-$name'));
  await tester.scrollUntilVisible(
    button,
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [390.0, 768.0, 1366.0]) {
    testWidgets(
      'navigation EN ES updates immediately with Language after Account at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final router = _router();
        addTearDown(router.dispose);
        await _pump(tester, router, scale: width == 768 ? 2 : 1);
        if (width < 600) {
          await tester.tap(find.byKey(const Key('admin-open-drawer')));
          await tester.pumpAndSettle();
        }
        const esLabels = [
          'Pedidos',
          'Calendario',
          'Completados',
          'Cancelados',
          'Menú',
          'Operaciones de tienda',
          'Promociones',
          'Configuración de impresora',
          'Cuenta',
        ];
        for (final language in ['en', 'es', 'en']) {
          final toggle = find.byKey(Key('language-$language'));
          final navigationScroll = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          navigationScroll.position.jumpTo(
            navigationScroll.position.maxScrollExtent,
          );
          await tester.pumpAndSettle();
          await Scrollable.ensureVisible(
            tester.element(toggle),
            alignment: 0.5,
          );
          await tester.pumpAndSettle();
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          // Spanish labels can increase the list extent with enlarged text.
          navigationScroll.position.jumpTo(
            navigationScroll.position.maxScrollExtent,
          );
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/app');
          expect(
            find.byTooltip(language == 'es' ? 'Idioma' : 'Language'),
            findsOneWidget,
          );
          final account = find.byKey(const Key('nav-account'));
          final section = find.byType(LanguageToggle);
          expect(
            tester.getRect(account).bottom,
            lessThanOrEqualTo(tester.getRect(section).top),
          );
          final divider = find.byKey(const Key('admin-sign-out-divider'));
          expect(
            tester.getRect(section).bottom,
            lessThanOrEqualTo(tester.getRect(divider).top + 1),
          );
          final signOut = find.byKey(const Key('admin-sign-out'));
          expect(
            find.descendant(
              of: signOut,
              matching: find.text(
                language == 'es' ? 'Cerrar sesión' : 'Sign Out',
              ),
            ),
            findsOneWidget,
          );
          expect(
            tester.getRect(divider).bottom,
            lessThanOrEqualTo(tester.getRect(signOut).top),
          );
          for (var i = AdminDestination.values.length - 1; i >= 0; i--) {
            final destination = AdminDestination.values[i];
            final item = find.byKey(Key('nav-${destination.name}'));
            await tester.scrollUntilVisible(
              item,
              -160,
              scrollable: find
                  .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            expect(
              find.descendant(
                of: item,
                matching: find.text(
                  language == 'es' ? esLabels[i] : destination.label,
                ),
              ),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
  testWidgets('phone drawer control stays left and preserves Back', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = _router(initial: '/app/menu/edit');
    addTearDown(router.dispose);
    await _pump(tester, router);
    final drawer = find.byKey(const Key('admin-open-drawer'));
    expect(find.byIcon(Icons.view_sidebar_outlined), findsOneWidget);
    expect(find.byIcon(Icons.menu_rounded), findsNothing);
    expect(find.byTooltip('Open navigation'), findsOneWidget);
    expect(tester.getCenter(drawer).dx, lessThan(56));
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(drawer);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-drawer')).hitTestable(), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const Key('nav-orders')))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/app/menu/edit');
    expect(tester.takeException(), isNull);
  });

  for (final width in [600.0, 1024.0]) {
    testWidgets('left panel toggle preserves draft and route at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = _router(initial: '/app/menu/edit');
      addTearDown(router.dispose);
      await _pump(tester, router, scale: 2);
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      await tester.pump();
      final toggle = find.byKey(const Key('admin-toggle-navigation'));
      final initiallyRail = width < 840;
      expect(
        find.byIcon(
          initiallyRail ? Icons.view_sidebar_outlined : Icons.view_sidebar,
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.menu_rounded), findsNothing);
      expect(tester.getCenter(toggle).dx, lessThan(initiallyRail ? 120 : 232));
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
      expect(router.routeInformationProvider.value.uri.path, '/app/menu/edit');
      final selected = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.selected == true,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('nav-menu')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
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
        AdminDestination.menu,
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
          await tester.scrollUntilVisible(
            item,
            150,
            scrollable: find.byType(Scrollable).first,
          );
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
          initial: imperative ? '/app/menu' : '/app/menu/edit',
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
          imperative ? '/app/menu' : '/app/menu/edit',
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
