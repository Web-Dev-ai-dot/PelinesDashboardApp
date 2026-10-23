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
import 'package:pelines_admin_app/app/navigation/admin_navigation.dart';

import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';

Location location({
  String name = 'Tualatin',
  Map<String, dynamic>? regular = const {
    'enabled': false,
    'feeCents': 325,
    'minimumCents': 1800,
  },
  Map<String, dynamic>? catering,
  int fee = 1275,
  DateTime? updatedAt,
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
  updatedAt: updatedAt ?? DateTime.utc(2026),
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
    if (originalUpdatedAt != current.updatedAt) {
      throw LocationSettingsConflict(current);
    }
    return current = location(
      regular: {'enabled': enabled, 'feeCents': feeCents, 'minimumCents': 1800},
      catering: current.cateringDeliveryJson,
      fee: current.deliveryFeeCents,
      updatedAt: current.updatedAt.add(const Duration(seconds: 1)),
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
    if (originalUpdatedAt != current.updatedAt) {
      throw LocationSettingsConflict(current);
    }
    return current = location(
      catering: {'enabled': enabled},
      fee: feeCents,
      regular: current.regularDeliveryJson,
      updatedAt: current.updatedAt.add(const Duration(seconds: 1)),
    );
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
        testWidgets('inline delivery responsive $width $scale $lang', (
          tester,
        ) async {
          await pump(tester, width: width, scale: scale, lang: lang);
          await tester.pumpAndSettle();
          for (final kind in ['regular', 'catering']) {
            expect(find.byKey(Key('$kind-delivery-card')), findsOneWidget);
            await tester.ensureVisible(find.byKey(Key('$kind-delivery-fee')));
            await tester.pumpAndSettle();
            final field = tester.widget<TextField>(
              find.byKey(Key('$kind-delivery-fee')),
            );
            expect(
              field.controller!.text,
              kind == 'regular' ? '3.25' : '12.75',
            );
            expect(field.enabled, kind == 'catering');
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  }
  testWidgets('independent switches retain fee when disabled', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();
    await tap(tester, 'regular-delivery-enabled');
    await tester.ensureVisible(find.byKey(const Key('regular-delivery-fee')));
    await tester.enterText(
      find.byKey(const Key('regular-delivery-fee')),
      '9.25',
    );
    await tap(tester, 'regular-delivery-enabled');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('regular-delivery-fee')))
          .enabled,
      false,
    );
    await tap(tester, 'regular-delivery-enabled');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('regular-delivery-fee')))
          .controller!
          .text,
      '9.25',
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('catering-delivery-enabled')),
          )
          .value,
      true,
    );
  });
  for (final kind in ['regular', 'catering']) {
    testWidgets('$kind save preserves other draft', (tester) async {
      final repo = Repo();
      await pump(tester, repo: repo);
      await tester.pumpAndSettle();
      await tap(tester, 'regular-delivery-enabled');
      await tester.ensureVisible(find.byKey(const Key('regular-delivery-fee')));
      await tester.enterText(
        find.byKey(const Key('regular-delivery-fee')),
        '8.25',
      );
      await tester.ensureVisible(
        find.byKey(const Key('catering-delivery-fee')),
      );
      await tester.enterText(
        find.byKey(const Key('catering-delivery-fee')),
        '7.49',
      );
      await tap(tester, '$kind-delivery-save');
      expect(repo.regularWrites, kind == 'regular' ? 1 : 0);
      expect(repo.cateringWrites, kind == 'catering' ? 1 : 0);
      final other = kind == 'regular' ? 'catering' : 'regular';
      expect(
        tester
            .widget<TextField>(find.byKey(Key('$other-delivery-fee')))
            .controller!
            .text,
        kind == 'regular' ? '7.49' : '8.25',
      );
      expect(find.text('Delivery settings saved.'), findsOneWidget);
      await tap(tester, '$other-delivery-save');
      expect(repo.regularWrites, 1);
      expect(repo.cateringWrites, 1);
      expect(repo.current.deliveryFeeCents, 749);
      expect(repo.current.regularDeliveryJson!['feeCents'], 825);
    });
    testWidgets('$kind invalid money does not write', (tester) async {
      final repo = Repo();
      await pump(tester, repo: repo);
      await tester.pumpAndSettle();
      if (kind == 'regular') await tap(tester, 'regular-delivery-enabled');
      for (final input in ['-1', '2.345', 'abc', '']) {
        await tester.ensureVisible(find.byKey(Key('$kind-delivery-fee')));
        await tester.enterText(find.byKey(Key('$kind-delivery-fee')), input);
        await tap(tester, '$kind-delivery-save');
        expect(
          find.text(
            'Enter a valid non-negative fee with no more than two decimals.',
          ),
          findsOneWidget,
        );
      }
      expect(repo.regularWrites + repo.cateringWrites, 0);
    });
    testWidgets('$kind error retains draft and disables duplicate saves', (
      tester,
    ) async {
      final repo = Repo()
        ..hold = Completer<void>()
        ..fail = true;
      await pump(tester, repo: repo);
      await tester.pumpAndSettle();
      if (kind == 'regular') await tap(tester, 'regular-delivery-enabled');
      await tester.ensureVisible(find.byKey(Key('$kind-delivery-fee')));
      await tester.enterText(find.byKey(Key('$kind-delivery-fee')), '9.50');
      await tester.ensureVisible(find.byKey(Key('$kind-delivery-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('$kind-delivery-save')));
      await tester.pump();
      for (final other in ['regular', 'catering']) {
        expect(
          tester
              .widget<FilledButton>(find.byKey(Key('$other-delivery-save')))
              .onPressed,
          isNull,
        );
      }
      repo.hold!.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(Key('$kind-delivery-fee')))
            .controller!
            .text,
        '9.50',
      );
      expect(repo.regularWrites + repo.cateringWrites, 1);
      expect(
        find.text(
          kind == 'regular'
              ? 'Regular delivery could not be saved.'
              : 'Catering delivery could not be saved.',
        ),
        findsOneWidget,
      );
    });
  }
  testWidgets('catering confirmation can be cancelled or accepted', (
    tester,
  ) async {
    final repo = Repo();
    await pump(tester, repo: repo);
    await tester.pumpAndSettle();
    await tap(tester, 'catering-delivery-enabled');
    await tap(tester, 'catering-delivery-save');
    await tester.tap(find.byKey(const Key('catering-delivery-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(repo.cateringWrites, 0);
    await tap(tester, 'catering-delivery-save');
    await tester.tap(find.byKey(const Key('catering-delivery-confirm')));
    await tester.pumpAndSettle();
    expect(repo.cateringWrites, 1);
  });
  testWidgets('selected location uses real values', (tester) async {
    final container = await pump(tester);
    await tester.pumpAndSettle();
    (container.read(currentLocationProvider.notifier) as Current).replace(
      location(
        name: 'Portland',
        regular: {'enabled': true, 'feeCents': 975},
        catering: {'enabled': false},
        fee: 1800,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Portland'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('regular-delivery-fee')))
          .controller!
          .text,
      '9.75',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('catering-delivery-fee')))
          .controller!
          .text,
      '18.00',
    );
  });
  testWidgets('dirty guard keeps or discards both drafts', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();
    await tap(tester, 'regular-delivery-enabled');
    final scope = tester.widget<AdminPopScope<void>>(
      find.byType(AdminPopScope<void>),
    );
    final pending = scope.onRequestLeave!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(await pending, false);
    final discard = scope.onRequestLeave!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(await discard, true);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('regular-delivery-enabled')),
          )
          .value,
      false,
    );
  });
  testWidgets('keyboard and large text keep save reachable', (tester) async {
    await pump(tester, width: 320, scale: 2);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.ensureVisible(find.byKey(const Key('catering-delivery-fee')));
    await tester.enterText(
      find.byKey(const Key('catering-delivery-fee')),
      '6.00',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('catering-delivery-save')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byKey(const Key('catering-delivery-save'))).bottom,
      lessThanOrEqualTo(800),
    );
  });
  testWidgets('conflict requires explicit reload without overwriting server', (
    tester,
  ) async {
    final repo = Repo();
    await pump(tester, repo: repo);
    await tester.pumpAndSettle();
    await tap(tester, 'regular-delivery-enabled');
    repo.current = location(
      regular: {'enabled': true, 'feeCents': 950},
      updatedAt: DateTime.utc(2026, 2),
    );
    await tap(tester, 'regular-delivery-save');
    expect(find.text('Store settings were changed elsewhere.'), findsOneWidget);
    expect(repo.current.regularDeliveryJson!['feeCents'], 950);
    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('regular-delivery-fee')))
          .controller!
          .text,
      '9.50',
    );
  });
  testWidgets('unsupported service settings isolate only the affected card', (
    tester,
  ) async {
    await pump(tester, load: () async => location(regular: {'enabled': 'bad'}));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('regular-delivery-save')), findsNothing);
    expect(find.byKey(const Key('catering-delivery-save')), findsOneWidget);
    expect(find.textContaining('unsupported format'), findsOneWidget);
  });
  testWidgets('loading error retry missing location', (tester) async {
    final pending = Completer<Location?>();
    var calls = 0;
    await pump(
      tester,
      load: () => ++calls == 1 ? pending.future : Future.value(null),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(Exception('Location unavailable'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a location to continue.'), findsOneWidget);
  });
}
