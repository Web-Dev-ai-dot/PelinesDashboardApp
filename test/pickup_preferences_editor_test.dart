import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';

import 'auto_cancellation_harness.dart';
import 'pickup_auto_cancellation_test.dart' as ui;

String text(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;
Future<void> edit(WidgetTester tester, String key, String value) async {
  await ui.visible(tester, key);
  await tester.enterText(find.byKey(Key(key)), value);
  await tester.pumpAndSettle();
}

void main() {
  for (final viewport in [(320.0, 2.0), (768.0, 1.0)]) {
    testWidgets(
      'long location text and keyboard allow editing and saving $viewport',
      (tester) async {
        final harness = CancellationHarness();
        harness.data['address'] = '7670 SW Nyberg Street, A very long address with additional delivery instructions';
        await ui.pump(
          tester,
          harness,
          width: viewport.$1,
          scale: viewport.$2,
          keyboard: 300,
        );
        await edit(tester, 'pickup-regular-minimum', '29.50');
        await ui.tap(tester, 'pickup-regular-save');
        expect((harness.data['servicePrefsJson'] as Map)['minRegular'], 29.5);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('availability save does not save or discard a service draft', (
    tester,
  ) async {
    final harness = CancellationHarness();
    await ui.pump(tester, harness);
    await edit(tester, 'pickup-regular-minimum', '24');
    await ui.tap(tester, 'accepting-orders-switch');
    await ui.tap(tester, 'pickup-availability-save');
    await tester.tap(find.byKey(const Key('accepting-orders-confirm')));
    await tester.pumpAndSettle();
    expect(harness.patches.single, {'isAcceptingOrders': false});
    expect(text(tester, 'pickup-regular-minimum'), '24');
    await ui.tap(tester, 'pickup-regular-save');
    expect(harness.patches.length, 2);
    expect(harness.data['isAcceptingOrders'], isFalse);
    expect((harness.data['servicePrefsJson'] as Map)['minRegular'], 24);
  });
  for (final kind in ['regular', 'catering']) {
    testWidgets(
      'group $kind saves real values and preserves unknown JSON and other draft',
      (tester) async {
        final harness = CancellationHarness(
          prefs: {
            'minRegular': 17.25,
            'minCatering': 275.5,
            'capRegular': 45,
            'capCatering': 9,
            'unknown': {
              'nested': [1, 2],
            },
          },
        );
        await ui.pump(tester, harness);
        final other = kind == 'regular' ? 'catering' : 'regular';
        expect(text(tester, 'pickup-regular-minimum'), '17.25');
        expect(text(tester, 'pickup-catering-minimum'), '275.5');
        await edit(tester, 'pickup-$other-capacity', '21');
        await edit(tester, 'pickup-$kind-minimum', '33.75');
        await ui.tap(tester, 'pickup-$kind-save');
        expect(harness.patches.length, 1);
        expect(harness.patches.single.keys, ['servicePrefsJson']);
        final suffix = kind == 'regular' ? 'Regular' : 'Catering';
        final otherSuffix = kind == 'regular' ? 'Catering' : 'Regular';
        expect((harness.data['servicePrefsJson'] as Map)['min$suffix'], 33.75);
        expect(
          (harness.data['servicePrefsJson'] as Map)['cap$otherSuffix'],
          kind == 'regular' ? 9 : 45,
        );
        expect((harness.data['servicePrefsJson'] as Map)['unknown'], {
          'nested': [1, 2],
        });
        expect(text(tester, 'pickup-$other-capacity'), '21');
        await ui.tap(tester, 'pickup-$other-save');
        expect(harness.patches.length, 2);
        expect((harness.data['servicePrefsJson'] as Map)['min$suffix'], 33.75);
        expect(
          (harness.data['servicePrefsJson'] as Map)['cap$otherSuffix'],
          21,
        );
      },
    );
  }
  testWidgets('numeric validation and cancel retain canonical defaults', (
    tester,
  ) async {
    final harness = CancellationHarness();
    await ui.pump(tester, harness);
    for (final invalid in ['-1', '1.234', 'abc']) {
      await edit(tester, 'pickup-regular-minimum', invalid);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('pickup-regular-save')))
            .onPressed,
        isNull,
      );
    }
    await edit(tester, 'pickup-regular-minimum', '20.50');
    for (final invalid in ['-1', '2.5']) {
      await edit(tester, 'pickup-regular-capacity', invalid);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('pickup-regular-save')))
            .onPressed,
        isNull,
      );
    }
    await ui.tap(tester, 'pickup-regular-cancel');
    expect(text(tester, 'pickup-regular-minimum'), '15');
    expect(text(tester, 'pickup-regular-capacity'), '80');
    expect(harness.patches, isEmpty);
  });
  for (final applied in [false, true]) {
    testWidgets('ambiguous save is reconciled once applied=$applied', (
      tester,
    ) async {
      final harness = CancellationHarness()
        ..timeout = true
        ..applyPatch = applied;
      await ui.pump(tester, harness);
      await edit(tester, 'pickup-regular-minimum', '20');
      await ui.tap(tester, 'pickup-regular-save');
      expect(harness.patches.length, 1);
      expect(
        find.text(
          applied ? 'Service preferences saved.' : 'The service preference change could not be confirmed. Reload before retrying.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('pickup-regular-save')))
            .onPressed,
        isNull,
      );
    });
  }
  testWidgets('same-group server conflict keeps draft and blocks overwrite', (
    tester,
  ) async {
    final harness = CancellationHarness();
    await ui.pump(tester, harness);
    await edit(tester, 'pickup-regular-minimum', '20');
    harness.data['servicePrefsJson'] = {'minRegular': 99};
    await ui.tap(tester, 'pickup-regular-save');
    expect(harness.patches, isEmpty);
    expect(text(tester, 'pickup-regular-minimum'), '20');
    expect(
      find.text('Store settings were changed elsewhere. Reload before saving.'),
      findsOneWidget,
    );
  });
  testWidgets('shared lock prevents double submits and disables other group', (
    tester,
  ) async {
    final harness = CancellationHarness()..patchHold = Completer<void>();
    await ui.pump(tester, harness);
    await edit(tester, 'pickup-regular-minimum', '20');
    await ui.visible(tester, 'pickup-regular-save');
    await tester.tap(find.byKey(const Key('pickup-regular-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(harness.patches.length, 1);
    for (final kind in ['regular', 'catering']) {
      expect(
        tester
            .widget<FilledButton>(find.byKey(Key('pickup-$kind-save')))
            .onPressed,
        isNull,
      );
    }
    harness.patchHold!.complete();
    await tester.pumpAndSettle();
    expect(harness.patches.length, 1);
  });
  testWidgets(
    'changing selected location replaces draft without cross-location writes',
    (tester) async {
      final harness = CancellationHarness();
      final container = await ui.pump(tester, harness);
      await edit(tester, 'pickup-regular-minimum', '20');
      final next = Map<String, dynamic>.from(harness.data)
        ..['id'] = 'B'
        ..['name'] = 'Troutdale'
        ..['servicePrefsJson'] = {'minRegular': 45};
      (container.read(currentLocationProvider.notifier) as CancellationCurrent)
          .replace(Location.fromJson(next));
      await tester.pumpAndSettle();
      expect(text(tester, 'pickup-regular-minimum'), '45');
      expect(harness.patches, isEmpty);
    },
  );
  testWidgets('back confirmation retains or discards all card drafts', (
    tester,
  ) async {
    final harness = CancellationHarness();
    await ui.pump(tester, harness);
    await edit(tester, 'pickup-regular-minimum', '20');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(text(tester, 'pickup-regular-minimum'), '20');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(harness.patches, isEmpty);
  });
}
