import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/features/locations/data/locations_repository.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/presentation/delivery_settings_screen.dart';
import 'package:pelines_admin_app/features/locations/presentation/regular_delivery_screen.dart';
import 'package:pelines_admin_app/features/locations/presentation/catering_delivery_screen.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/locations/providers/regular_delivery_controller.dart';
import 'package:pelines_admin_app/features/locations/providers/catering_delivery_controller.dart';

Location location({
  String name = 'Tualatin',
  Map<String, dynamic>? regular = const {
    'enabled': false,
    'feeCents': 325,
    'minimumCents': 1800,
  },
  Map<String, dynamic>? catering,
  int fee = 1275,
}) => Location(
  id: name,
  name: name,
  slug: name,
  isActive: true,
  isAcceptingOrders: true,
  regularDeliveryJson: regular,
  cateringDeliveryJson: catering,
  deliveryFeeCents: fee,
  deliveryMinimumCents: 15000,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class Current extends CurrentLocationController {
  Current(this.load);
  final Future<Location?> Function() load;
  @override
  Future<Location?> build() => load();
  void replace(Location value) => state = AsyncData(value);
}

class Repo implements LocationsRepository {
  Location current = location();
  int regularWrites = 0, cateringWrites = 0;
  Completer<void>? hold;
  bool fail = false;
  @override
  Future<List<Location>> getLocations() async => [current];
  @override
  Future<Location> getLocation(String id) async => current;
  @override
  Future<Location> saveRegularDeliverySettings({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool enabled,
    required int feeCents,
  }) async {
    regularWrites++;
    await hold?.future;
    if (fail) throw Exception('save failed');
    return current = location(
      regular: {'enabled': enabled, 'feeCents': feeCents, 'minimumCents': 1800},
    );
  }

  @override
  Future<Location> saveCateringDeliverySettings({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool originalEnabled,
    required bool enabled,
    required int originalFeeCents,
    required int feeCents,
  }) async {
    cateringWrites++;
    await hold?.future;
    if (fail) throw Exception('save failed');
    return current = location(catering: {'enabled': enabled}, fee: feeCents);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> pump(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  String lang = 'en',
  Future<Location?> Function()? load,
  Repo? repo,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      currentLocationProvider.overrideWith(
        () => Current(load ?? () async => location()),
      ),
      locationsRepositoryProvider.overrideWithValue(repo ?? Repo()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
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
        home: const DeliverySettingsScreen(),
      ),
    ),
  );
  await tester.pump();
  return container;
}

Future<void> tap(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0, 768.0, 1400.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final lang in ['en', 'es']) {
        testWidgets('delivery summaries/editors $width $scale $lang', (
          tester,
        ) async {
          await pump(tester, width: width, scale: scale, lang: lang);
          await tester.pumpAndSettle();
          expect(
            find.text(
              lang == 'en'
                  ? 'Delivery Settings'
                  : 'Configuraci\u00f3n de entrega',
            ),
            findsOneWidget,
          );
          expect(find.text('Tualatin'), findsOneWidget);
          expect(find.text(r'$3.25'), findsOneWidget);
          expect(find.text(r'$18.00'), findsOneWidget);
          expect(find.text(r'$12.75'), findsOneWidget);
          expect(find.text(r'$150.00'), findsOneWidget);
          for (final key in [
            'accepting-orders-switch',
            'auto-accept-card',
            'edit-business-hours',
          ]) {
            expect(find.byKey(Key(key)), findsNothing);
          }
          expect(tester.takeException(), isNull);
          for (final kind in ['regular', 'catering']) {
            await tap(tester, 'edit-$kind-delivery');
            expect(
              kind == 'regular'
                  ? find.byType(RegularDeliveryScreen)
                  : find.byType(CateringDeliveryScreen),
              findsOneWidget,
            );
            expect(
              tester
                  .widget<TextField>(find.byKey(Key('$kind-delivery-fee')))
                  .controller!
                  .text,
              kind == 'regular' ? '3.25' : '12.75',
            );
            expect(
              tester
                  .widget<SwitchListTile>(
                    find.byKey(Key('$kind-delivery-enabled')),
                  )
                  .value,
              kind == 'catering',
            );
            expect(find.byType(TextField), findsOneWidget);
            await tester.scrollUntilVisible(
              find.byKey(Key('$kind-delivery-cancel')),
              250,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(
              tester.getSize(find.byKey(Key('$kind-delivery-cancel'))).height,
              greaterThanOrEqualTo(48),
            );
            expect(tester.takeException(), isNull);
            await tap(tester, '$kind-delivery-cancel');
            expect(find.byType(DeliverySettingsScreen), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  for (final kind in ['regular', 'catering']) {
    testWidgets(
      '$kind save preserves other configuration and refreshes summary',
      (tester) async {
        final repo = Repo();
        await pump(tester, repo: repo);
        await tester.pumpAndSettle();
        await tap(tester, 'edit-$kind-delivery');
        await tester.enterText(find.byKey(Key('$kind-delivery-fee')), '7.49');
        await tap(tester, '$kind-delivery-save');
        expect(find.byType(DeliverySettingsScreen), findsOneWidget);
        expect(find.text(r'$7.49'), findsOneWidget);
        expect(
          find.text(kind == 'regular' ? r'$12.75' : r'$3.25'),
          findsOneWidget,
        );
        expect(repo.regularWrites, kind == 'regular' ? 1 : 0);
        expect(repo.cateringWrites, kind == 'catering' ? 1 : 0);
      },
    );
    testWidgets('$kind dirty Cancel preserves draft until discard', (
      tester,
    ) async {
      final repo = Repo();
      await pump(tester, repo: repo);
      await tester.pumpAndSettle();
      await tap(tester, 'edit-$kind-delivery');
      await tester.enterText(find.byKey(Key('$kind-delivery-fee')), '8.00');
      await tap(tester, '$kind-delivery-cancel');
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(Key('$kind-delivery-fee')))
            .controller!
            .text,
        '8.00',
      );
      await tap(tester, '$kind-delivery-cancel');
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(DeliverySettingsScreen), findsOneWidget);
      expect(repo.regularWrites + repo.cateringWrites, 0);
    });
    testWidgets('$kind busy disables editor and save error keeps draft', (
      tester,
    ) async {
      final repo = Repo()
        ..hold = Completer<void>()
        ..fail = true;
      final container = await pump(tester, repo: repo);
      await tester.pumpAndSettle();
      await tap(tester, 'edit-$kind-delivery');
      await tester.enterText(find.byKey(Key('$kind-delivery-fee')), '9.50');
      await tester.ensureVisible(find.byKey(Key('$kind-delivery-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('$kind-delivery-save')));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byKey(Key('$kind-delivery-fee'))).enabled,
        false,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(Key('$kind-delivery-save')))
            .onPressed,
        isNull,
      );
      repo.hold!.complete();
      await tester.pumpAndSettle();
      expect(
        find.text(
          kind == 'regular'
              ? 'Regular delivery could not be saved.'
              : 'Catering delivery could not be saved.',
        ),
        findsOneWidget,
      );
      expect(
        kind == 'regular'
            ? container.read(regularDeliveryProvider).isBusy
            : container.read(cateringDeliveryProvider).isBusy,
        false,
      );
    });
  }
  testWidgets('location switch and malformed settings never share defaults', (
    tester,
  ) async {
    final container = await pump(tester, width: 1400);
    await tester.pumpAndSettle();
    final current = container.read(currentLocationProvider.notifier) as Current;
    current.replace(
      location(name: 'Portland', regular: null, catering: {'enabled': false}),
    );
    await tester.pumpAndSettle();
    expect(find.text('Portland'), findsOneWidget);
    expect(find.text('Tualatin'), findsNothing);
    expect(find.text('Disabled'), findsNWidgets(2));
    current.replace(
      location(regular: {'enabled': 'bad'}, catering: {'enabled': true}),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-regular-delivery')), findsNothing);
    expect(find.byKey(const Key('edit-catering-delivery')), findsOneWidget);
    current.replace(location(catering: {'enabled': 'bad'}));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-regular-delivery')), findsOneWidget);
    expect(find.byKey(const Key('edit-catering-delivery')), findsNothing);
  });
  testWidgets('loading, error, retry and missing location', (tester) async {
    final pending = Completer<Location?>();
    var calls = 0;
    await pump(
      tester,
      load: () => ++calls == 1 ? pending.future : Future.value(null),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(Exception('Location unavailable'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Location unavailable'), findsOneWidget);
    expect(find.byKey(const Key('edit-regular-delivery')), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a location to continue.'), findsOneWidget);
  });
}
