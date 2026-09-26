import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/presentation/auto_accept_screen.dart';
import 'package:pelines_admin_app/features/locations/presentation/store_operations_screen.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/locations/providers/store_operations_controller.dart';

Location location({String name = 'Tualatin', Map<String, dynamic>? prefs}) =>
    Location(
      id: name,
      name: name,
      slug: name,
      isActive: true,
      isAcceptingOrders: true,
      deliveryFeeCents: 0,
      deliveryMinimumCents: 0,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      address: 'Do not show contact',
      phone: '555-contact',
      servicePrefsJson: prefs,
    );

class Current extends CurrentLocationController {
  Current(this.load);
  final Future<Location?> Function() load;
  @override
  Future<Location?> build() => load();
  void replace(Location value) => state = AsyncData(value);
}

class Operation extends StoreOperationsController {
  void publish(StoreOperationState value) => state = value;
}

Future<ProviderContainer> pump(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  String lang = 'en',
  Future<Location?> Function()? load,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      currentLocationProvider.overrideWith(
        () => Current(load ?? () async => location()),
      ),
      storeOperationsProvider.overrideWith(Operation.new),
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
        home: const PickupSettingsScreen(),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  for (final width in [320.0, 390.0, 768.0, 1400.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final lang in ['en', 'es']) {
        testWidgets('pickup $width $scale $lang', (tester) async {
          await pump(tester, width: width, scale: scale, lang: lang);
          await tester.pumpAndSettle();
          expect(
            find.text(
              lang == 'en' ? 'Pickup Settings' : 'Configuraci\u00f3n de pickup',
            ),
            findsOneWidget,
          );
          expect(find.text('Tualatin'), findsOneWidget);
          expect(
            find.byKey(const Key('accepting-orders-switch')),
            findsOneWidget,
          );

          for (final key in [
            'edit-business-hours',
            'edit-regular-delivery',
            'edit-catering-delivery',
          ]) {
            expect(find.byKey(Key(key)), findsNothing);
          }
          for (final label in [
            'Do not show contact',
            '555-contact',
            'Enable Pickup',
            'Preparation Time',
            'Temporary Closures',
            'Regular Delivery',
            'Catering Delivery',
          ]) {
            expect(find.text(label), findsNothing);
          }
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.byKey(const Key('edit-auto-accept-regular')),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            tester
                .getSize(find.byKey(const Key('edit-auto-accept-regular')))
                .height,
            greaterThanOrEqualTo(48),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const Key('edit-auto-accept-regular')),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('pickup-regular-card')), findsOneWidget);
          await tester.tap(find.byKey(const Key('edit-auto-accept-regular')));
          await tester.pumpAndSettle();
          expect(find.byType(AutoAcceptScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
    'ordering uses existing named confirmation; cancel changes nothing',
    (tester) async {
      final container = await pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accepting-orders-switch')));
      await tester.pumpAndSettle();
      expect(find.text('Stop online orders for Tualatin?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('accepting-orders-cancel')));
      await tester.pumpAndSettle();
      expect(
        container.read(storeOperationsProvider).phase,
        StoreOperationPhase.idle,
      );
      expect(
        container.read(currentLocationProvider).value!.isAcceptingOrders,
        isTrue,
      );
    },
  );

  testWidgets('busy disables ordering and error remains visible', (
    tester,
  ) async {
    final container = await pump(tester);
    await tester.pumpAndSettle();
    final operation =
        container.read(storeOperationsProvider.notifier) as Operation;
    operation.publish(
      const StoreOperationState(phase: StoreOperationPhase.reconciling),
    );
    await tester.pump();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('accepting-orders-switch')),
          )
          .onChanged,
      isNull,
    );
    expect(find.byKey(const Key('store-operation-progress')), findsOneWidget);
    operation.publish(
      const StoreOperationState(
        phase: StoreOperationPhase.error,
        message: 'Server refused change',
      ),
    );
    await tester.pump();
    expect(find.text('Server refused change'), findsOneWidget);
  });

  testWidgets(
    'location changes update summaries; malformed preferences block editor',
    (tester) async {
      final container = await pump(tester);
      await tester.pumpAndSettle();
      final current =
          container.read(currentLocationProvider.notifier) as Current;
      current.replace(
        location(name: 'Portland', prefs: {'autoAcceptRegular': true}),
      );
      await tester.pumpAndSettle();
      expect(find.text('Portland'), findsOneWidget);
      expect(find.text('Tualatin'), findsNothing);
      expect(find.text('Automatically accepted after payment'), findsOneWidget);
      current.replace(location(prefs: {'autoAcceptRegular': 'invalid'}));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit-auto-accept-regular')), findsNothing);
      expect(find.textContaining('unsupported format'), findsNWidgets(2));
    },
  );

  testWidgets('loading, failure, retry and missing location', (tester) async {
    final pending = Completer<Location?>();
    var calls = 0;
    await pump(
      tester,
      load: () {
        calls++;
        return calls == 1 ? pending.future : Future.value(null);
      },
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(Exception('Cannot load location'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cannot load location'), findsOneWidget);
    expect(find.byKey(const Key('accepting-orders-switch')), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a location to continue.'), findsOneWidget);
  });
}
