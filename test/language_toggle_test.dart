import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/language_toggle.dart';
import 'package:pelines_admin_app/app/l10n/locale_controller.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';

class _Store implements LanguageStore {
  String value = 'en';
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String language) async {
    value = language;
  }
}

void main() {
  test('language selection persists across provider containers', () async {
    final store = _Store();
    final first = ProviderContainer(
      overrides: [languageStoreProvider.overrideWithValue(store)],
    );
    await first.read(localeProvider.notifier).select('es');
    expect(store.value, 'es');
    first.dispose();
    final restored = ProviderContainer(
      overrides: [languageStoreProvider.overrideWithValue(store)],
    );
    addTearDown(restored.dispose);
    final subscription = restored.listen(localeProvider, (_, _) {});
    addTearDown(subscription.close);
    await Future<void>.delayed(Duration.zero);
    expect(restored.read(localeProvider).languageCode, 'es');
  });
  for (final width in [120.0, 232.0, 304.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('language pill fits navigation width $width at $scale', (
        tester,
      ) async {
        final store = _Store();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [languageStoreProvider.overrideWithValue(store)],
            child: Consumer(
              builder: (context, ref, _) => MaterialApp(
                locale: ref.watch(localeProvider),
                supportedLocales: AdminLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AdminLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                theme: AppTheme.light,
                home: Scaffold(
                  body: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: width,
                        child: const LanguageToggle(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final globe = find.byIcon(Icons.language);
        final en = find.byKey(const Key('language-en'));
        final es = find.byKey(const Key('language-es'));
        expect(tester.getRect(globe).left, PelinesSpacing.lg);
        if (width > 120) {
          expect(find.text('Language'), findsOneWidget);
          expect(
            tester.getRect(find.text('Language')).left,
            PelinesSpacing.lg + 24 + PelinesSpacing.sm,
          );
        } else {
          expect(find.byTooltip('Language'), findsOneWidget);
        }
        for (final button in [en, es]) {
          expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          expect(tester.getRect(button).right, lessThanOrEqualTo(width));
        }
        expect(tester.takeException(), isNull);
        await tester.tap(es);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextButton>(es).style!.backgroundColor!.resolve({}),
          PelinesColors.languageSelectedBackground,
        );
        expect(
          tester.widget<TextButton>(en).style!.backgroundColor!.resolve({}),
          Colors.transparent,
        );
        expect(store.value, 'es');
        expect(
          tester.widget<TextButton>(es).style!.foregroundColor!.resolve({}),
          PelinesColors.languageSelectedText,
        );
        expect(
          tester.widget<TextButton>(en).style!.foregroundColor!.resolve({}),
          PelinesColors.textPrimary,
        );
        expect(find.byTooltip('Idioma'), findsOneWidget);
        await tester.tap(en);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Language'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
