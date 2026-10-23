import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/locations/presentation/store_operations_screen.dart';
import 'package:pelines_admin_app/features/locations/presentation/business_hours_screen.dart';
import 'package:pelines_admin_app/features/locations/presentation/closure_form_screen.dart';
import 'package:pelines_admin_app/features/locations/presentation/auto_accept_screen.dart';
import 'package:pelines_admin_app/features/locations/presentation/regular_delivery_screen.dart';
import 'package:pelines_admin_app/features/locations/presentation/catering_delivery_screen.dart';
import 'package:pelines_admin_app/features/promotions/data/promotions_repository.dart';
import 'package:pelines_admin_app/features/promotions/models/discount.dart';
import 'package:pelines_admin_app/features/promotions/providers/promotions_providers.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotions_screen.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotion_detail_screen.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotion_form_screen.dart';

final _location = Location(
  id: 'A',
  name: 'Tualatin',
  slug: 'tualatin',
  address: '123 Backend Address',
  isActive: true,
  deliveryFeeCents: 250,
  deliveryMinimumCents: 1000,
  isAcceptingOrders: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _Current extends CurrentLocationController {
  @override
  Future<Location?> build() async => _location;
}

Discount _discount(String id, String? location) => Discount(
  id: id,
  code: 'CODE-$id',
  type: 'percent',
  value: 10,
  minSubtotalCents: 0,
  startsAt: null,
  endsAt: null,
  usageLimit: 20,
  timesRedeemed: 3,
  locationId: location,
  appliesTo: 'both',
  isActive: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _Repo implements PromotionsRepository {
  @override
  Future<void> deletePromotion(String id) => throw UnimplementedError();

  bool fail = false, empty = false;
  Completer<void>? hold;
  @override
  Future<List<Discount>> getDiscounts() async {
    await hold?.future;
    if (fail) throw const ApiException(message: 'explicit promotion error');
    return empty
        ? []
        : [
            _discount('local', 'A'),
            _discount('global', null),
            _discount('hidden', 'B'),
          ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<GoRouter> _pump(
  WidgetTester tester,
  Widget screen, {
  double width = 390,
  double scale = 1,
  String lang = 'en',
  _Repo? repo,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(
        path: '/app/promotions/new',
        builder: (_, _) => const PromotionFormScreen(),
      ),
      GoRoute(
        path: '/app/promotions/:id',
        builder: (_, state) =>
            PromotionDetailScreen(discountId: state.pathParameters['id']!),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentLocationProvider.overrideWith(_Current.new),
        promotionsRepositoryProvider.overrideWithValue(repo ?? _Repo()),
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
  await tester.pump();
  return router;
}

void main() {
  for (final section in [
    StoreOperationsSection.locations,
    StoreOperationsSection.pickup,
    StoreOperationsSection.delivery,
  ]) {
    testWidgets('Store split reuses existing cards $section', (tester) async {
      await _pump(tester, StoreOperationsScreen(section: section), width: 1200);
      if (section == StoreOperationsSection.locations) {
        expect(
          find.text('Tualatin · 123 Backend Address', findRichText: true),
          findsOneWidget,
        );
      } else {
        expect(find.text('Tualatin'), findsWidgets);
        expect(find.text('123 Backend Address'), findsOneWidget);
      }
      expect(
        find.text('Business Hours'),
        section == StoreOperationsSection.delivery
            ? findsNothing
            : findsWidgets,
      );
      expect(
        find.byKey(const Key('accepting-orders-switch')),
        section == StoreOperationsSection.locations
            ? findsOneWidget
            : findsNothing,
      );
      expect(
        find.text('Regular Delivery'),
        section == StoreOperationsSection.delivery
            ? findsWidgets
            : findsNothing,
      );
      expect(
        find.text('Catering Delivery'),
        section == StoreOperationsSection.delivery
            ? findsWidgets
            : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
  for (final size in [
    (390.0, 1.0),
    (768.0, 1.0),
    (1400.0, 1.0),
    (320.0, 2.0),
  ]) {
    for (final lang in ['en', 'es']) {
      testWidgets('promotions cards/table ${size.$1} ${size.$2} $lang', (
        tester,
      ) async {
        final router = await _pump(
          tester,
          const PromotionsScreen(),
          width: size.$1,
          scale: size.$2,
          lang: lang,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Tualatin · 123 Backend Address', findRichText: true),
          findsOneWidget,
        );
        expect(find.byKey(const Key('add-promotion')), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('CODE-local'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('CODE-local'), findsOneWidget);
        expect(find.text('CODE-hidden'), findsNothing);
        expect(find.byType(DataTable), findsNothing);
        expect(find.byKey(const Key('promotion-card-local')), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('CODE-global'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('CODE-global'), findsOneWidget);
        expect(tester.takeException(), isNull);
        router.go('/app/promotions/global');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('edit-promotion')), findsOneWidget);
        expect(find.byKey(const Key('promotion-active-action')), findsNothing);
        expect(tester.takeException(), isNull);
      });
      for (final screen in <String, Widget>{
        'operations': const StoreOperationsScreen(),
        'hours': BusinessHoursScreen(location: _location),
        'closure': ClosureFormScreen(location: _location),
        'auto': AutoAcceptScreen(location: _location),
        'regular': RegularDeliveryScreen(location: _location),
        'catering': CateringDeliveryScreen(location: _location),
        'promotion form': const PromotionFormScreen(discountId: 'local'),
        'promotion detail': const PromotionDetailScreen(discountId: 'local'),
      }.entries) {
        testWidgets('${screen.key} ${size.$1} ${size.$2} $lang no overflow', (
          tester,
        ) async {
          await _pump(
            tester,
            screen.value,
            width: size.$1,
            scale: size.$2,
            lang: lang,
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('Tualatin'), findsWidgets);
          if (screen.key == 'operations') {
            expect(
              find.byKey(
                ValueKey(
                  'operations-grid-${size.$1 >= 768 && size.$2 == 1 ? 2 : 1}',
                ),
              ),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('edit-business-hours')),
              findsOneWidget,
            );
            expect(find.byKey(const Key('edit-auto-accept')), findsOneWidget);
          }
          if (screen.key == 'hours') {
            expect(find.byKey(const Key('business-day-6')), findsOneWidget);
          }
          if (screen.key == 'promotion detail') {
            expect(find.text('3 / 20'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          for (var n = 0; n < 5; n++) {
            await tester.drag(
              find.byType(ListView).first,
              const Offset(0, -700),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  }
  testWidgets('promotion errors remain errors, retry and empty state', (
    tester,
  ) async {
    final repo = _Repo()..hold = Completer<void>();
    await _pump(tester, const PromotionsScreen(), repo: repo);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('add-promotion')), findsOneWidget);
    repo.fail = true;
    repo.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('explicit promotion error'), findsOneWidget);
    expect(
      find.text('No promotions available for this location.'),
      findsNothing,
    );
    repo.fail = false;
    repo.empty = true;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(
      find.text('No promotions available for this location.'),
      findsOneWidget,
    );
  });
  testWidgets('new promotion route and dirty cancel preserve draft', (
    tester,
  ) async {
    await _pump(tester, const PromotionsScreen());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-promotion')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'DRAFTCODE');
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'DRAFTCODE',
    );
  });
}
