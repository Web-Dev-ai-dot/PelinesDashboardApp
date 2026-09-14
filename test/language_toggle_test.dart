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
  @override
  Future<String?> read() async => 'en';
  @override
  Future<void> write(String language) async {}
}

void main() {
  for (final width in [120.0, 232.0, 304.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('language pill fits navigation width $width at $scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [languageStoreProvider.overrideWithValue(_Store())],
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
          PelinesColors.brandPrimarySoft,
        );
        expect(
          tester.widget<TextButton>(en).style!.backgroundColor!.resolve({}),
          Colors.transparent,
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
