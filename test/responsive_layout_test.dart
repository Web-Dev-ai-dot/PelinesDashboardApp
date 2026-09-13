import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/app/theme/pelines_components.dart';
import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/models/temporary_closure.dart';
import 'package:pelines_admin_app/features/locations/presentation/business_hours_screen.dart';
import 'package:pelines_admin_app/features/locations/presentation/closure_form_screen.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/menu/models/menu_models.dart';
import 'package:pelines_admin_app/features/menu/presentation/category_form_screen.dart';
import 'package:pelines_admin_app/features/menu/presentation/product_form_screen.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_detail_screen.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

import 'order_test_data.dart';

final _location = Location(
  id: 'location-id',
  name: 'Troutdale restaurant with a very long location name',
  slug: 'troutdale',
  isActive: true,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  isAcceptingOrders: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _CurrentLocation extends CurrentLocationController {
  @override
  Future<Location?> build() async => _location;
}

Widget _app(Widget child, double scale) => MaterialApp(
  theme: AppTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);

void main() {
  testWidgets('loading action wraps its label at large text sizes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: PelinesActionBar(
              children: const [
                FilledButton(
                  onPressed: null,
                  child: PelinesButtonLabel(
                    busy: true,
                    label: 'Marking picked up...',
                  ),
                ),
              ],
            ),
          ),
        ),
        2,
      ),
    );
    await tester.pump();
    expect(find.text('Marking picked up...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
  for (final (width, scale) in <(double, double)>[(320, 2), (768, 1.5)]) {
    testWidgets('order actions and notes fit at $width / $scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final order = orderDetail();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentLocationProvider.overrideWith(_CurrentLocation.new),
            orderDetailProvider(order.id).overrideWith((ref) async => order),
          ],
          child: _app(OrderDetailScreen(orderId: order.id), scale),
        ),
      );
      await tester.pumpAndSettle();
      for (final key in ['save-internal-notes']) {
        final action = find.byKey(Key(key));
        // Detail retains notes, while operational actions now live in preview.
        await tester.scrollUntilVisible(
          action,
          200,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 80,
        );
        await Scrollable.ensureVisible(tester.element(action), alignment: 0.5);
        await tester.pumpAndSettle();
        expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
        expect(tester.getRect(action).bottom, lessThanOrEqualTo(800));
        expect(tester.takeException(), isNull);
      }
    });
  }
  for (final (width, scale) in <(double, double)>[
    (320, 2),
    (390, 1.5),
    (600, 1),
    (768, 1.5),
    (1024, 2),
    (1366, 1),
  ]) {
    testWidgets('shared layouts at $width and text scale $scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var taps = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            appBar: AppBar(title: const Text('Printer Settings')),
            body: PelinesPageBody(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const PelinesLabelValueRow(
                    label: Text('Delivery address and special instructions'),
                    value: Text(
                      '123 Very Long Restaurant Street, Building B, Suite 104, Troutdale',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const PelinesStateBadge(
                    label: 'A very long restaurant location name',
                    foreground: PelinesColors.brandPrimary,
                    background: PelinesColors.brandPrimarySoft,
                    icon: Icons.storefront_outlined,
                  ),
                  const SizedBox(height: 16),
                  PelinesActionBar(
                    children: [
                      FilledButton(
                        key: const Key('primary'),
                        onPressed: () => taps++,
                        child: const Text(
                          'Test Connection with the configured printer',
                        ),
                      ),
                      const OutlinedButton(
                        onPressed: null,
                        child: Text('Disabled secondary action'),
                      ),
                      TextButton(onPressed: () {}, child: const Text('Cancel')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          scale,
        ),
      );
      await tester.pumpAndSettle();
      final primary = find.byKey(const Key('primary'));
      await tester.scrollUntilVisible(
        primary,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(primary);
      expect(taps, 1);
      expect(tester.getSize(primary).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(primary).width, greaterThanOrEqualTo(48));
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      final title = tester.widget<AppBar>(find.byType(AppBar));
      final context = tester.element(find.byWidget(title));
      expect(
        Theme.of(context).appBarTheme.titleTextStyle?.fontFamily,
        'Work Sans',
      );
      expect(
        Theme.of(context).appBarTheme.titleTextStyle?.fontWeight,
        FontWeight.w700,
      );
      expect(
        Theme.of(context).textTheme.headlineSmall?.fontFamily,
        'Bree Serif',
      );
    });
  }

  testWidgets('action bar uses local width and keeps distinct touch areas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1366, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [280.0, 720.0]) {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: PelinesActionBar(
                  children: [
                    FilledButton(
                      key: const Key('one'),
                      onPressed: () {},
                      child: const Text('Accept'),
                    ),
                    OutlinedButton(
                      key: const Key('two'),
                      onPressed: () {},
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          1,
        ),
      );
      final one = tester.getRect(find.byKey(const Key('one')));
      final two = tester.getRect(find.byKey(const Key('two')));
      if (width < 600) {
        expect(two.top - one.bottom, greaterThanOrEqualTo(12));
      } else {
        expect(two.left - one.right, greaterThanOrEqualTo(12));
      }
      expect(one.overlaps(two), isFalse);
      expect(tester.takeException(), isNull);
    }
  });

  for (final (name, screen, target) in <(String, Widget, Finder)>[
    (
      'Business Hours',
      BusinessHoursScreen(location: _location),
      find.byKey(const Key('business-hours-save')),
    ),
    (
      'Temporary Closures',
      ClosureFormScreen(
        location: _location,
        closure: TemporaryClosure(
          id: 'closure-id',
          reason: 'A long closure reason',
          start: '2026-09-12',
          end: '2026-09-13',
          notes: '',
          active: true,
        ),
      ),
      find.byKey(const Key('closure-save')),
    ),
    (
      'Category',
      const CategoryFormScreen(kind: MenuKind.store),
      find.text('Create Category'),
    ),
    (
      'Product',
      const ProductFormScreen(
        kind: MenuKind.store,
        categoryId: 'category-id',
        categoryName: 'A long category name',
      ),
      find.text('Create Product'),
    ),
  ]) {
    testWidgets('$name is scrollable at 320 with large text', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentLocationProvider.overrideWith(_CurrentLocation.new),
          ],
          child: _app(screen, 2),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        target,
        250,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 80,
      );
      await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
      await tester.pumpAndSettle();
      // Disabled create actions deliberately do not participate in hit testing.
      final rect = tester.getRect(target);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(640));
      if (name == 'Temporary Closures') {
        // A keyboard reduces the available height; the save action remains reachable.
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          target,
          150,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 80,
        );
        await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
        await tester.pumpAndSettle();
        final body = tester.getRect(find.byType(PelinesPageBody));
        expect(tester.getRect(target).bottom, lessThanOrEqualTo(body.bottom));
        expect(tester.takeException(), isNull);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
