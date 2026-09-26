import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';

import 'auto_cancellation_harness.dart';
import 'pickup_auto_cancellation_test.dart' as ui;

String text(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  for (final canonical in [false, true]) {
    testWidgets('preview seeds, local edits and reopen canonical=$canonical', (
      tester,
    ) async {
      final prefs = canonical
          ? <String, dynamic>{
              'acceptRegular': false,
              'minRegular': 0,
              'capRegular': 0,
              'acceptCatering': false,
              'minCatering': 245.75,
              'capCatering': 12,
            }
          : null;
      final harness = CancellationHarness(prefs: prefs);
      final original = jsonEncode(harness.data);
      final container = await ui.pump(tester, harness);
      final before = container.read(currentLocationProvider).value;
      for (final kind in ['regular', 'catering']) {
        final prefix = 'pickup-preview-$kind';
        await ui.visible(tester, '$prefix-accept');
        expect(
          tester
              .widget<SwitchListTile>(find.byKey(Key('$prefix-accept')))
              .value,
          !canonical,
        );
        await ui.tap(tester, '$prefix-accept');
        await ui.visible(tester, '$prefix-minimum');
        expect(
          text(tester, '$prefix-minimum'),
          canonical
              ? (kind == 'regular' ? '0' : '245.75')
              : (kind == 'regular' ? '15' : '150'),
        );
        await tester.enterText(find.byKey(Key('$prefix-minimum')), '99.95');
        await ui.visible(tester, '$prefix-capacity');
        expect(
          text(tester, '$prefix-capacity'),
          canonical
              ? (kind == 'regular' ? '0' : '12')
              : (kind == 'regular' ? '80' : '6'),
        );
        await tester.enterText(find.byKey(Key('$prefix-capacity')), '25');
        await ui.visible(tester, 'auto-cancel-$kind-save');
        expect(
          tester
              .widget<FilledButton>(find.byKey(Key('auto-cancel-$kind-save')))
              .onPressed,
          isNull,
        );
      }
      expect(harness.patches, isEmpty);
      expect(jsonEncode(harness.data), original);
      expect(
        identical(container.read(currentLocationProvider).value, before),
        true,
      );
      // Unmounting the route disposes all local drafts; reopening reads again.
      await tester.pumpWidget(const SizedBox());
      await ui.pump(tester, harness);
      for (final kind in ['regular', 'catering']) {
        final prefix = 'pickup-preview-$kind';
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
      }
      expect(harness.patches, isEmpty);
    });
  }

  for (final lang in ['en', 'es']) {
    for (final width in [320.0, 768.0]) {
      testWidgets('preview labels and local validation $lang $width 2x', (
        tester,
      ) async {
        final harness = CancellationHarness();
        await ui.pump(tester, harness, width: width, scale: 2, lang: lang);
        expect(
          find.text(lang == 'en' ? 'Not enforced yet' : 'Aún no aplicado'),
          findsNWidgets(6),
        );
        for (final kind in ['regular', 'catering']) {
          for (final field in ['minimum', 'capacity']) {
            final key = 'pickup-preview-$kind-$field';
            await ui.visible(tester, key);
            for (final invalid in ['', '-1', '1.234', 'abc']) {
              await tester.enterText(find.byKey(Key(key)), invalid);
              await tester.pump();
              expect(
                tester
                    .widget<TextField>(find.byKey(Key(key)))
                    .decoration!
                    .errorText,
                isNotNull,
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
        }
        expect(harness.patches, isEmpty);
      });
    }
  }

  testWidgets('real auto cancel save excludes all edited preview values', (
    tester,
  ) async {
    final prefs = {'acceptRegular': true, 'minRegular': 15, 'capRegular': 80};
    final harness = CancellationHarness(prefs: prefs);
    await ui.pump(tester, harness);
    await ui.tap(tester, 'pickup-preview-regular-accept');
    await ui.visible(tester, 'pickup-preview-regular-minimum');
    await tester.enterText(
      find.byKey(const Key('pickup-preview-regular-minimum')),
      '200',
    );
    await ui.visible(tester, 'auto-cancel-regular-value');
    await tester.enterText(
      find.byKey(const Key('auto-cancel-regular-value')),
      '20',
    );
    await ui.tap(tester, 'auto-cancel-regular-save');
    expect(harness.patches, [
      {
        'servicePrefsJson': {...prefs, 'autoCancelRegularValue': 20},
      },
    ]);
    expect(text(tester, 'pickup-preview-regular-minimum'), '200');
  });
}
