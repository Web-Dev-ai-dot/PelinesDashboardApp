import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/features/locations/presentation/store_operations_screen.dart';

import 'auto_cancellation_harness.dart';

Future<ProviderContainer> pump(
  WidgetTester tester,
  CancellationHarness harness, {
  double width = 768,
  double scale = 1,
  double keyboard = 0,
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
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
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
  for (final kind in ['regular', 'catering']) {
    testWidgets('grouped auto cancel $kind confirms before write', (
      tester,
    ) async {
      final harness = CancellationHarness();
      await pump(tester, harness);
      final key = 'auto-cancel-$kind-value';
      await visible(tester, key);
      await tester.enterText(
        find.byKey(Key(key)),
        kind == 'regular' ? '5' : '1',
      );
      await tap(tester, 'pickup-$kind-save');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(harness.patches, isEmpty);
      await tester.tap(find.byKey(Key('auto-cancel-$kind-confirm-cancel')));
      await tester.pumpAndSettle();
      expect(harness.patches, isEmpty);
      await tap(tester, 'pickup-$kind-save');
      await tester.tap(find.byKey(Key('auto-cancel-$kind-confirm')));
      await tester.pumpAndSettle();
      expect(harness.patches.length, 1);
      final suffix = kind == 'regular' ? 'Regular' : 'Catering';
      expect(
        (harness.data['servicePrefsJson'] as Map)['autoCancel${suffix}Value'],
        kind == 'regular' ? 5 : 1,
      );
    });
  }
  testWidgets(
    'disabled cancellation preserves value/unit and disables fields',
    (tester) async {
      final harness = CancellationHarness(
        prefs: {
          'autoCancelRegularEnabled': false,
          'autoCancelRegularValue': 7,
          'autoCancelRegularUnit': 'hours',
        },
      );
      await pump(tester, harness);
      final field = find.byKey(const Key('auto-cancel-regular-value'));
      expect(tester.widget<TextField>(field).controller!.text, '7');
      expect(tester.widget<TextField>(field).enabled, isFalse);
      expect(
        tester
            .widget<DropdownButtonFormField>(
              find.byKey(const Key('auto-cancel-regular-unit-hours')),
            )
            .onChanged,
        isNull,
      );
      await visible(tester, 'pickup-regular-minimum');
      await tester.enterText(
        find.byKey(const Key('pickup-regular-minimum')),
        '27',
      );
      await tap(tester, 'pickup-regular-save');
      expect(
        (harness.data['servicePrefsJson'] as Map)['autoCancelRegularValue'],
        7,
      );
      expect(
        (harness.data['servicePrefsJson'] as Map)['autoCancelRegularUnit'],
        'hours',
      );
      expect(
        (harness.data['servicePrefsJson'] as Map)['autoCancelRegularEnabled'],
        isFalse,
      );
    },
  );
  testWidgets('auto-accept confirmation cancel preserves unsaved card', (
    tester,
  ) async {
    final harness = CancellationHarness();
    await pump(tester, harness);
    await tap(tester, 'auto-accept-regular-switch');
    await tap(tester, 'pickup-regular-save');
    expect(harness.patches, isEmpty);
    await tester.tap(
      find.byKey(const Key('auto-accept-regular-confirm-cancel')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('auto-accept-regular-switch')),
          )
          .value,
      isTrue,
    );
    expect(harness.patches, isEmpty);
    await tap(tester, 'pickup-regular-save');
    await tester.tap(find.byKey(const Key('auto-accept-regular-confirm')));
    await tester.pumpAndSettle();
    expect(
      (harness.data['servicePrefsJson'] as Map)['autoAcceptRegular'],
      isTrue,
    );
    expect(harness.patches.length, 1);
  });
  testWidgets('invalid duration cannot save and valid duration restores save', (
    tester,
  ) async {
    final harness = CancellationHarness();
    await pump(tester, harness);
    await visible(tester, 'auto-cancel-regular-value');
    await tester.enterText(
      find.byKey(const Key('auto-cancel-regular-value')),
      '0',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('pickup-regular-save')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('auto-cancel-regular-value')),
      '30',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('pickup-regular-save')))
          .onPressed,
      isNotNull,
    );
    expect(harness.patches, isEmpty);
  });
}
