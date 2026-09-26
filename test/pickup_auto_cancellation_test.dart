import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/presentation/store_operations_screen.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';

import 'auto_cancellation_harness.dart';

Future<ProviderContainer> pump(
  WidgetTester tester,
  CancellationHarness harness, {
  double width = 768,
  double scale = 1,
  String lang = 'en',
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = harness.container();
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
  await tester.pumpAndSettle();
  return container;
}

Future<void> visible(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String key) async {
  await visible(tester, key);
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 768.0, 1400.0]) {
    for (final lang in ['en', 'es']) {
      testWidgets('all pickup service controls $width 2x $lang', (
        tester,
      ) async {
        final harness = CancellationHarness();
        await pump(tester, harness, width: width, scale: 2, lang: lang);
        expect(find.text(lang == 'en' ? 'General' : 'General'), findsOneWidget);
        for (final kind in ['regular', 'catering']) {
          await visible(tester, 'auto-cancel-$kind-value');
          expect(
            tester
                .widget<TextField>(find.byKey(Key('auto-cancel-$kind-value')))
                .controller!
                .text,
            kind == 'regular' ? '10' : '12',
          );
          final unit = kind == 'regular' ? 'minutes' : 'hours';
          await visible(tester, 'auto-cancel-$kind-unit-$unit');
          expect(
            tester
                .getSize(find.byKey(Key('auto-cancel-$kind-unit-$unit')))
                .height,
            greaterThanOrEqualTo(48),
          );
          await visible(tester, 'auto-cancel-$kind-save');
          expect(
            tester.getSize(find.byKey(Key('auto-cancel-$kind-save'))).height,
            greaterThanOrEqualTo(48),
          );
          expect(tester.takeException(), isNull);
        }
        expect(harness.patches, isEmpty);
        expect(find.byKey(const Key('edit-regular-delivery')), findsNothing);
      });
    }
  }
  for (final kind in ['regular', 'catering']) {
    for (final activate in [true, false]) {
      testWidgets(
        '$kind ${activate ? 'enable' : 'shorten'} confirmation cancel sends no PATCH',
        (tester) async {
          final prefix = kind == 'regular'
              ? 'autoCancelRegular'
              : 'autoCancelCatering';
          final harness = CancellationHarness(
            prefs: activate ? {'${prefix}Enabled': false} : null,
          );
          await pump(tester, harness);
          if (activate) {
            await tap(tester, 'auto-cancel-$kind-enabled');
          } else {
            await visible(tester, 'auto-cancel-$kind-value');
            await tester.enterText(
              find.byKey(Key('auto-cancel-$kind-value')),
              kind == 'regular' ? '5' : '1',
            );
          }
          await tap(tester, 'auto-cancel-$kind-save');
          expect(find.text('Apply auto-cancellation changes?'), findsOneWidget);
          expect(
            find.textContaining('Existing pending orders'),
            findsOneWidget,
          );
          expect(harness.patches, isEmpty);
          await tester.tap(find.byKey(Key('auto-cancel-$kind-confirm-cancel')));
          await tester.pumpAndSettle();
          expect(harness.patches, isEmpty);
          await tap(tester, 'auto-cancel-$kind-save');
          await tester.tap(find.byKey(Key('auto-cancel-$kind-confirm')));
          await tester.pumpAndSettle();
          expect(harness.patches.length, 1);
          expect(find.text('Auto-cancel settings saved.'), findsOneWidget);
        },
      );
    }
    testWidgets(
      '$kind scope reuses existing Auto Accept confirmations/mutation',
      (tester) async {
        final harness = CancellationHarness(
          prefs: {
            'autoCancelRegularValue': 25,
            'future': {'keep': true},
          },
        );
        await pump(tester, harness);
        await tap(tester, 'edit-auto-accept-$kind');
        expect(
          find.byKey(
            Key('auto-accept-${kind == 'regular' ? 'catering' : 'regular'}'),
          ),
          findsNothing,
        );
        await tap(tester, 'auto-accept-$kind');
        await tester.tap(find.byKey(Key('auto-accept-$kind-confirm-cancel')));
        await tester.pumpAndSettle();
        expect(harness.patches, isEmpty);
        await tap(tester, 'auto-accept-$kind');
        await tester.tap(find.byKey(Key('auto-accept-$kind-confirm')));
        await tester.pumpAndSettle();
        await tap(tester, 'auto-accept-save');
        expect(harness.patches.length, 1);
        expect(
          (harness.data['servicePrefsJson'] as Map)['autoCancelRegularValue'],
          25,
        );
        expect((harness.data['servicePrefsJson'] as Map)['future'], {
          'keep': true,
        });
      },
    );
  }
  testWidgets(
    'changing hours to minutes shortens effective duration and confirms',
    (tester) async {
      final harness = CancellationHarness();
      await pump(tester, harness);
      await tap(tester, 'auto-cancel-catering-unit-hours');
      await tester.tap(find.text('Minutes').last);
      await tester.pumpAndSettle();
      await tap(tester, 'auto-cancel-catering-save');
      expect(
        find.byKey(const Key('auto-cancel-catering-confirm')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('auto-cancel-catering-confirm-cancel')),
      );
      await tester.pumpAndSettle();
      expect(harness.patches, isEmpty);
    },
  );
  testWidgets('invalid values rejected; Cancel resets draft without mutation', (
    tester,
  ) async {
    final harness = CancellationHarness();
    await pump(tester, harness);
    for (final input in ['0', '-1', '1.5', '1441']) {
      await visible(tester, 'auto-cancel-regular-value');
      await tester.enterText(
        find.byKey(const Key('auto-cancel-regular-value')),
        input,
      );
      await tap(tester, 'auto-cancel-regular-save');
      expect(harness.patches, isEmpty);
      expect(
        find.byKey(const Key('auto-cancel-regular-message')),
        findsOneWidget,
      );
    }
    await tap(tester, 'auto-cancel-regular-cancel');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('auto-cancel-regular-value')))
          .controller!
          .text,
      '10',
    );
    expect(harness.patches, isEmpty);
  });
  testWidgets('location change while confirmation open sends no PATCH', (
    tester,
  ) async {
    final harness = CancellationHarness();
    final container = await pump(tester, harness);
    await visible(tester, 'auto-cancel-regular-value');
    await tester.enterText(
      find.byKey(const Key('auto-cancel-regular-value')),
      '5',
    );
    await tap(tester, 'auto-cancel-regular-save');
    (container.read(currentLocationProvider.notifier) as CancellationCurrent)
        .replace(
          Location.fromJson({...harness.data, 'id': 'B', 'name': 'Portland'}),
        );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auto-cancel-regular-confirm')));
    await tester.pumpAndSettle();
    expect(harness.patches, isEmpty);
    expect(find.text('Portland'), findsOneWidget);
  });
  testWidgets(
    'location active read-only and unsupported cancellation does not block Auto Accept',
    (tester) async {
      final harness = CancellationHarness(
        prefs: {'autoCancelRegularUnit': 'days'},
      );
      await pump(tester, harness);
      await visible(tester, 'edit-auto-accept-regular');
      expect(find.byKey(const Key('auto-cancel-regular-save')), findsNothing);
      expect(find.byKey(const Key('edit-auto-accept-regular')), findsOneWidget);
      expect(
        find.text(
          'Read-only here. Manage location activation in the web admin.',
        ),
        findsOneWidget,
      );
      expect(harness.patches, isEmpty);
    },
  );
}
