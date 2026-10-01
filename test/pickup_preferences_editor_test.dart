import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';

import 'auto_cancellation_harness.dart';
import 'pickup_auto_cancellation_test.dart' as ui;

String text(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  for (final canonical in [false, true]) {
    testWidgets(
      'canonical/default values and save each Accept canonical=$canonical',
      (tester) async {
        final harness = CancellationHarness(
          prefs: canonical
              ? {
                  'acceptRegular': false,
                  'minRegular': 0,
                  'capRegular': 0,
                  'acceptCatering': false,
                  'minCatering': 245.75,
                  'capCatering': 12,
                }
              : null,
        );
        await ui.pump(tester, harness);
        for (final kind in ['regular', 'catering']) {
          final prefix = 'pickup-$kind';
          expect(
            tester
                .widget<SwitchListTile>(find.byKey(Key('$prefix-accept')))
                .value,
            !canonical,
          );
          expect(
            text(tester, '$prefix-minimum'),
            canonical
                ? (kind == 'regular' ? '0' : '245.75')
                : (kind == 'regular' ? '15' : '150'),
          );
          expect(
            text(tester, '$prefix-capacity'),
            canonical
                ? (kind == 'regular' ? '0' : '12')
                : (kind == 'regular' ? '80' : '6'),
          );
          expect(
            tester
                .widget<FilledButton>(find.byKey(Key('$prefix-save')))
                .onPressed,
            isNull,
          );
          await ui.tap(tester, '$prefix-accept');
          await ui.tap(tester, '$prefix-save');
          expect(
            tester
                .widget<FilledButton>(find.byKey(Key('$prefix-save')))
                .onPressed,
            isNull,
          );
          expect(
            tester.widget<Text>(find.byKey(Key('$prefix-message'))).data,
            'Service preferences saved.',
          );
          final suffix = kind == 'regular' ? 'Regular' : 'Catering';
          expect(
            (harness.data['servicePrefsJson'] as Map)['accept$suffix'],
            canonical,
          );
        }
        expect(harness.patches.length, 2);
      },
    );
  }
  for (final lang in ['en', 'es']) {
    for (final width in [320.0, 768.0, 1400.0]) {
      testWidgets('functional helpers, validation and saving $lang $width 2x', (
        tester,
      ) async {
        final harness = CancellationHarness();
        await ui.pump(tester, harness, width: width, scale: 2, lang: lang);
        expect(
          find.text(lang == 'en' ? '0 = No minimum' : '0 = Sin compra mínima'),
          findsNWidgets(2),
        );
        expect(
          find.text(
            lang == 'en' ? '0 = No daily limit' : '0 = Sin límite diario',
          ),
          findsNWidgets(2),
        );
        for (final kind in ['regular', 'catering']) {
          final prefix = 'pickup-$kind';
          for (final field in ['minimum', 'capacity']) {
            final key = '$prefix-$field';
            await ui.visible(tester, key);
            for (final invalid in ['', '-1', '1.234', 'abc', 'Infinity']) {
              await tester.enterText(find.byKey(Key(key)), invalid);
              await tester.pump();
              expect(
                tester
                    .widget<TextField>(find.byKey(Key(key)))
                    .decoration!
                    .errorText,
                isNotNull,
              );
              expect(
                tester
                    .widget<FilledButton>(find.byKey(Key('$prefix-save')))
                    .onPressed,
                isNull,
              );
              expect(tester.takeException(), isNull);
            }
            await tester.enterText(find.byKey(Key(key)), '0');
            await tester.pump();
            expect(
              tester
                  .widget<TextField>(find.byKey(Key(key)))
                  .decoration!
                  .errorText,
              isNull,
            );
          }
          await ui.tap(tester, '$prefix-save');
          expect(
            tester.getSize(find.byKey(Key('$prefix-save'))).height,
            greaterThanOrEqualTo(48),
          );
          expect(
            find.text(
              lang == 'en'
                  ? 'Service preferences saved.'
                  : 'Preferencias de servicio guardadas.',
            ),
            findsWidgets,
          );
          expect(tester.takeException(), isNull);
        }
        expect(harness.data['servicePrefsJson'], {
          'minRegular': 0,
          'capRegular': 0,
          'minCatering': 0,
          'capCatering': 0,
        });
      });
    }
  }
  for (final first in ['regular', 'catering']) {
    testWidgets(
      'save $first does not leak other local draft; stale draft conflicts',
      (tester) async {
        final harness = CancellationHarness();
        await ui.pump(tester, harness);
        final other = first == 'regular' ? 'catering' : 'regular';
        for (final kind in [first, other]) {
          await ui.visible(tester, 'pickup-$kind-minimum');
          await tester.enterText(
            find.byKey(Key('pickup-$kind-minimum')),
            kind == first ? '19.95' : '500',
          );
        }
        await ui.tap(tester, 'pickup-$first-save');
        final suffix = first == 'regular' ? 'Regular' : 'Catering';
        expect(harness.patches.single, {
          'servicePrefsJson': {'min$suffix': 19.95},
        });
        expect(text(tester, 'pickup-$other-minimum'), '500');
        await ui.tap(tester, 'pickup-$other-save');
        expect(harness.patches.length, 1);
        expect(
          find.text(
            'Store settings were changed elsewhere. Reload before saving.',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(Key('pickup-$other-save')))
              .onPressed,
          isNull,
        );
        await ui.tap(tester, 'pickup-$other-reload');
        expect(
          text(tester, 'pickup-$other-minimum'),
          other == 'regular' ? '15' : '150',
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(Key('pickup-$other-save')))
              .onPressed,
          isNull,
        );
      },
    );
  }
  testWidgets('decimal equivalent is no-op; Cancel discards draft', (
    tester,
  ) async {
    final harness = CancellationHarness();
    await ui.pump(tester, harness);
    await ui.visible(tester, 'pickup-regular-minimum');
    await tester.enterText(
      find.byKey(const Key('pickup-regular-minimum')),
      '15.00',
    );
    await ui.tap(tester, 'pickup-regular-save');
    expect(harness.patches, isEmpty);
    expect(text(tester, 'pickup-regular-minimum'), '15');
    await ui.visible(tester, 'pickup-regular-minimum');
    await tester.enterText(
      find.byKey(const Key('pickup-regular-minimum')),
      '99.95',
    );
    await ui.tap(tester, 'pickup-regular-cancel');
    expect(text(tester, 'pickup-regular-minimum'), '15');
    expect(harness.patches, isEmpty);
  });
  testWidgets(
    'malformed canonical settings block only their section and can reload',
    (tester) async {
      final harness = CancellationHarness(prefs: {'minRegular': 'bad'});
      await ui.pump(tester, harness);
      expect(find.byKey(const Key('pickup-regular-save')), findsNothing);
      expect(find.byKey(const Key('pickup-catering-save')), findsOneWidget);
      expect(find.byKey(const Key('edit-auto-accept-regular')), findsOneWidget);
      harness.data['servicePrefsJson'] = {'minRegular': 20};
      await ui.tap(tester, 'pickup-regular-reload');
      expect(text(tester, 'pickup-regular-minimum'), '20');
      expect(harness.patches, isEmpty);
    },
  );
  for (final applied in [true, false]) {
    testWidgets('timeout reconciles UI applied=$applied', (tester) async {
      final harness = CancellationHarness()
        ..timeout = true
        ..applyPatch = applied;
      await ui.pump(tester, harness);
      await ui.tap(tester, 'pickup-regular-accept');
      await ui.tap(tester, 'pickup-regular-save');
      expect(harness.patches.length, 1);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('pickup-regular-save')))
            .onPressed,
        isNull,
      );
      if (applied) {
        expect(find.text('Service preferences saved.'), findsOneWidget);
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const Key('pickup-regular-accept')),
              )
              .value,
          false,
        );
      } else {
        expect(
          find.text(
            'The service preference change could not be confirmed. Reload before retrying.',
          ),
          findsOneWidget,
        );
        await ui.tap(tester, 'pickup-regular-reload');
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const Key('pickup-regular-accept')),
              )
              .value,
          true,
        );
      }
    });
  }
  testWidgets(
    'saving freezes service controls and existing Auto Accept/Cancel',
    (tester) async {
      final harness = CancellationHarness()..patchHold = Completer<void>();
      await ui.pump(tester, harness);
      await ui.tap(tester, 'pickup-regular-accept');
      await ui.visible(tester, 'pickup-regular-save');
      await tester.tap(find.byKey(const Key('pickup-regular-save')));
      await tester.pump();
      for (final kind in ['regular', 'catering']) {
        expect(
          tester
              .widget<FilledButton>(find.byKey(Key('pickup-$kind-save')))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<SwitchListTile>(find.byKey(Key('pickup-$kind-accept')))
              .onChanged,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(find.byKey(Key('edit-auto-accept-$kind')))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(Key('auto-cancel-$kind-enabled')),
              )
              .onChanged,
          isNull,
        );
      }
      harness.patchHold!.complete();
      await tester.pumpAndSettle();
      expect(harness.patches.length, 1);
    },
  );
  testWidgets(
    'location switch discards old draft and reads new canonical values',
    (tester) async {
      final harness = CancellationHarness();
      final container = await ui.pump(tester, harness);
      await ui.visible(tester, 'pickup-regular-minimum');
      await tester.enterText(
        find.byKey(const Key('pickup-regular-minimum')),
        '99.95',
      );
      (container.read(currentLocationProvider.notifier) as CancellationCurrent)
          .replace(
            Location.fromJson({
              ...harness.data,
              'id': 'B',
              'servicePrefsJson': {'minRegular': 30},
            }),
          );
      await tester.pumpAndSettle();
      expect(text(tester, 'pickup-regular-minimum'), '30');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('pickup-regular-save')))
            .onPressed,
        isNull,
      );
      expect(harness.patches, isEmpty);
    },
  );
}
