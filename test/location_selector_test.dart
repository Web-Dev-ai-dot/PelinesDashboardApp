import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/features/locations/presentation/pelines_location_context.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';
import 'package:pelines_admin_app/app/navigation/admin_navigation.dart';
import 'package:pelines_admin_app/features/account/presentation/admin_home_screen.dart';
import 'package:pelines_admin_app/features/locations/data/location_selection_store.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

Location _location(String id, String name, {bool active = true}) => Location(
  id: id,
  name: name,
  slug: id,
  address: '25627 SE Stark St, a long address with additional location context, Troutdale, OR 97060',
  isActive: active,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  isAcceptingOrders: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
final _locations = [
  _location('first', 'Troutdale restaurant with a very long location name'),
  _location('second', 'Tualatin'),
  _location('inactive', 'Inactive restaurant', active: false),
];

class _Locations extends LocationsController {
  @override
  Future<List<Location>> build() async => _locations;
}

class _Orders extends TodayOrdersController {
  int refreshCalls = 0;
  @override
  Future<void> refresh() async => refreshCalls++;
  @override
  Future<TodayOrdersState> build() async => const TodayOrdersState(orders: []);
}

class _Store implements LocationSelectionStore {
  String? value = 'first';
  @override
  Future<String?> readLocationId() async => value;
  @override
  Future<void> writeLocationId(String id) async => value = id;
  @override
  Future<void> clearLocationId() async => value = null;
}

void main() {
  for (final width in [320.0, 390.0, 768.0, 1180.0]) {
    for (final language in ['en', 'es']) {
      testWidgets(
        'read-only context and navigation-only selector at $width/$language',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final store = _Store();
          final container = ProviderContainer(
            overrides: [
              locationsProvider.overrideWith(_Locations.new),
              locationSelectionStoreProvider.overrideWithValue(store),
              todayOrdersProvider.overrideWith(_Orders.new),
            ],
          );
          addTearDown(container.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
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
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
                home: AdminNavigationShell(
                  controller: AdminNavigationController(),
                  path: '/app',
                  child: const AdminHomeScreen(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final context = find.byType(PelinesLocationContext);
          expect(context, findsOneWidget);
          expect(
            find.descendant(of: context, matching: find.byType(InkWell)),
            findsNothing,
          );
          expect(
            find.descendant(
              of: context,
              matching: find.byType(GestureDetector),
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: context,
              matching: find.byIcon(Icons.expand_more),
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: context,
              matching: find.textContaining(
                _locations.first.name,
                findRichText: true,
              ),
            ),
            findsWidgets,
          );
          expect(
            find.descendant(
              of: context,
              matching: find.textContaining(
                '25627 SE Stark St',
                findRichText: true,
              ),
            ),
            findsWidgets,
          );
          expect(
            find.descendant(
              of: find.byKey(const Key('admin-topbar')),
              matching: find.byKey(const Key('location-selector')),
            ),
            findsNothing,
          );
          expect(
            find.byKey(const Key('language-en')),
            width < 600 ? findsNothing : findsOneWidget,
          );
          expect(
            find.byKey(const Key('language-es')),
            width < 600 ? findsNothing : findsOneWidget,
          );
          await tester.tap(context);
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsNothing);
          expect(store.value, 'first');
          if (width < 600) {
            expect(find.byKey(const Key('location-selector')), findsNothing);
            await tester.tap(find.byKey(const Key('admin-open-drawer')));
            await tester.pumpAndSettle();
          }
          final navigation = find.byKey(
            Key(
              width < 600
                  ? 'admin-drawer'
                  : width < 900
                  ? 'admin-rail'
                  : 'admin-sidebar',
            ),
          );
          final selector = find.descendant(
            of: navigation,
            matching: find.byKey(const Key('location-selector')),
          );
          expect(selector, findsOneWidget);
          expect(tester.getSize(selector).height, greaterThanOrEqualTo(48));
          await tester.tap(selector);
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsNothing);
          final options = find.byKey(const Key('navigation-location-list'));
          final panel = find.byKey(const Key('navigation-location-panel'));
          final surface = tester.widget<Material>(panel);
          expect(surface.color, PelinesColors.card);
          final shape = surface.shape! as RoundedRectangleBorder;
          expect(shape.side.color, PelinesColors.border);
          expect(shape.side.width, 1);
          expect(
            shape.borderRadius,
            BorderRadius.circular(PelinesRadius.pageCard),
          );
          final panelRect = tester.getRect(panel);
          final optionsRect = tester.getRect(options);
          expect(
            panelRect.top -
                tester
                    .getRect(find.byKey(const Key('location-selector')))
                    .bottom,
            8,
          );
          expect(optionsRect.left - panelRect.left, 8);
          expect(panelRect.right - optionsRect.right, 8);
          expect(optionsRect.top - panelRect.top, 8);
          expect(panelRect.bottom - optionsRect.bottom, 8);
          final rows = find.descendant(
            of: options,
            matching: find.byType(ListTile),
          );
          expect(rows, findsNWidgets(_locations.length));
          for (final row in rows.evaluate()) {
            final tile = row.widget as ListTile;
            expect(tile.subtitle, isNull);
            expect((tile.title! as Text).maxLines, 1);
            expect(
              tester.getSize(find.byWidget(tile)).height,
              greaterThanOrEqualTo(48),
            );
          }
          expect(
            find.descendant(
              of: options,
              matching: find.text(_locations.first.name),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: options,
              matching: find.textContaining('25627 SE Stark'),
            ),
            findsNothing,
          );
          final active = tester.widget<ListTile>(rows.first);
          expect(active.selected, isTrue);
          expect((active.trailing! as Icon).icon, Icons.check_circle);
          expect(
            tester.getRect(find.byKey(const Key('nav-orders'))).top -
                panelRect.bottom,
            greaterThanOrEqualTo(16),
          );
          final sheetScroll = find
              .descendant(
                of: find.byKey(const Key('admin-navigation-list')),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            find.text('Inactive restaurant'),
            150,
            scrollable: sheetScroll,
          );
          expect(
            tester
                .widget<ListTile>(
                  find.widgetWithText(ListTile, 'Inactive restaurant'),
                )
                .onTap,
            isNull,
          );
          await tester.scrollUntilVisible(
            find.text('Tualatin'),
            -150,
            scrollable: sheetScroll,
          );
          final nextLocation = find.widgetWithText(ListTile, 'Tualatin');
          await Scrollable.ensureVisible(
            tester.element(nextLocation),
            alignment: .5,
          );
          await tester.pumpAndSettle();
          await tester.tap(nextLocation);
          await tester.pumpAndSettle();
          expect(store.value, 'second');
          expect(
            find.byKey(const Key('navigation-location-panel')),
            findsNothing,
          );
          if (width < 600) {
            expect(find.byType(Drawer).hitTestable(), findsOneWidget);
            final en = tester.getSize(find.byKey(const Key('language-en')));
            final es = tester.getSize(find.byKey(const Key('language-es')));
            expect(en, es);
            expect(en.width, 80);
            expect(en.height, 48);
          }
          expect(container.read(currentLocationProvider).value?.id, 'second');
          expect(
            tester.widget<PelinesLocationContext>(context).location.id,
            'second',
          );
          expect(
            find.descendant(
              of: context,
              matching: find.textContaining('Tualatin', findRichText: true),
            ),
            findsWidgets,
          );
          expect(find.byType(BottomSheet), findsNothing);
          if (width < 600) {
            expect(find.byType(Drawer).hitTestable(), findsOneWidget);
            Navigator.of(tester.element(find.byType(Drawer))).pop();
            await tester.pumpAndSettle();
          }
          // To Do is Today-only; date selection belongs to Orders / Upcoming.
          expect(find.byKey(const Key('orders-date-selector')), findsNothing);
          final labels = language == 'es'
              ? ['En espera', 'Confirmado', 'En preparación', 'Listo']
              : ['Waiting', 'Confirmed', 'Preparing', 'Ready'];
          for (final label in labels) {
            expect(
              find.widgetWithText(OutlinedButton, '$label · 0'),
              findsOneWidget,
            );
          }
          for (final status in ['pending', 'confirmed', 'preparing', 'ready']) {
            expect(find.byKey(Key('todo-column-$status')), findsOneWidget);
          }
          await tester.tap(find.byKey(const Key('orders-header-refresh')));
          expect(
            (container.read(
              todayOrdersProvider.notifier,
            ) as _Orders).refreshCalls,
            1,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
