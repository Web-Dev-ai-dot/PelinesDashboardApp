import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/features/account/presentation/admin_home_screen.dart';
import 'package:pelines_admin_app/features/locations/data/location_selection_store.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

Location _location(String id, String name, {bool active = true}) => Location(
  id: id,
  name: name,
  slug: id,
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
  for (final width in [390.0, 768.0]) {
    testWidgets(
      'integrated selector preserves location controller and persistence at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
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
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const AdminHomeScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(_locations.first.name), findsOneWidget);
        expect(find.byTooltip('Change location'), findsNothing);
        final selector = find.byKey(const Key('location-selector'));
        final refresh = find.byTooltip('Refresh orders');
        expect(refresh, findsOneWidget);
        expect(tester.getSize(refresh).shortestSide, greaterThanOrEqualTo(48));
        expect(tester.getRect(refresh).right, greaterThan(width - 60));
        expect(tester.getRect(refresh).top, lessThan(56));
        await tester.tap(refresh);
        expect(
          (container.read(
            todayOrdersProvider.notifier,
          ) as _Orders).refreshCalls,
          1,
        );
        if (width >= 768) {
          expect(
            tester.getCenter(selector).dy,
            tester.getCenter(find.byKey(const Key('orders-date-selector'))).dy,
          );
        }
        expect(AppTheme.light.appBarTheme.titleTextStyle?.fontSize, 28);
        expect(
          AppTheme.light.appBarTheme.titleTextStyle?.fontFamily,
          'Work Sans',
        );
        expect(tester.getSize(selector).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        final inactive = tester.widget<ListTile>(
          find.widgetWithText(ListTile, 'Inactive restaurant'),
        );
        expect(inactive.enabled, isFalse);
        expect(inactive.onTap, isNull);
        await tester.tap(find.text('Tualatin'));
        await tester.pumpAndSettle();
        expect(container.read(currentLocationProvider).value?.id, 'second');
        expect(store.value, 'second');
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('Tualatin'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
