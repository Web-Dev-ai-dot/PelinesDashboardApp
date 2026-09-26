import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/features/auth/presentation/login_screen.dart';
import 'package:pelines_admin_app/features/auth/models/admin_session.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_controller.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_providers.dart';
import 'package:pelines_admin_app/features/account/models/profile.dart';
import 'package:pelines_admin_app/features/account/data/account_repository.dart';
import 'package:pelines_admin_app/features/account/presentation/account_screen.dart';

final _profile = Profile(
  id: 'admin',
  role: ProfileRole.admin,
  fullName: 'Backend Name',
  phone: '555-123',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _Account implements AccountRepository {
  @override
  Future<Profile> getMe() async => _profile;
  @override
  Future<Profile> updateMe(Map<String, dynamic> patch) async => _profile;
}

class _Auth extends AuthController {
  _Auth({this.signedIn = false});
  final bool signedIn;
  Completer<void>? hold;
  String? emailSent, passwordSent;
  @override
  Future<AdminSession?> build() async => signedIn
      ? AdminSession(profile: _profile, email: 'backend@example.test')
      : null;
  @override
  Future<void> signIn({required String email, required String password}) async {
    emailSent = email;
    passwordSent = password;
    state = const AsyncLoading();
    await hold?.future;
    state = AsyncError(const AdminAccessDeniedException(), StackTrace.current);
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget page,
  _Auth auth,
  double width,
  double scale,
  String lang, {
  double keyboard = 0,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        accountRepositoryProvider.overrideWithValue(_Account()),
      ],
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
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final viewport in [
    (390.0, 1.0),
    (768.0, 1.0),
    (1400.0, 1.0),
    (320.0, 2.0),
  ]) {
    for (final lang in ['en', 'es']) {
      testWidgets(
        'login ${viewport.$1} ${viewport.$2} $lang keyboard visibility loading errors',
        (tester) async {
          final auth = _Auth()..hold = Completer<void>();
          await _pump(
            tester,
            const LoginScreen(),
            auth,
            viewport.$1,
            viewport.$2,
            lang,
            keyboard: 300,
          );
          expect(find.byKey(const Key('login-yellow-band')), findsOneWidget);
          expect(
            tester.widget<Text>(find.byKey(const Key('login-title'))).textAlign,
            isNot(TextAlign.center),
          );
          final email = find.byKey(const Key('login-email'));
          final password = find.byKey(const Key('login-password'));
          expect(
            tester
                .widget<TextField>(
                  find.descendant(of: email, matching: find.byType(TextField)),
                )
                .decoration!
                .filled,
            isTrue,
          );
          expect(find.byType(Image), findsOneWidget);
          await tester.enterText(email, 'admin@example.test');
          await tester.ensureVisible(password);
          await tester.enterText(password, 'input-password');
          expect(
            tester
                .widget<TextField>(
                  find.descendant(
                    of: password,
                    matching: find.byType(TextField),
                  ),
                )
                .obscureText,
            isTrue,
          );
          final show = find.byIcon(Icons.visibility_outlined);
          await tester.ensureVisible(show);
          await tester.pumpAndSettle();
          await tester.tap(show);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextField>(
                  find.descendant(
                    of: password,
                    matching: find.byType(TextField),
                  ),
                )
                .obscureText,
            isFalse,
          );
          final submit = find.byKey(const Key('login-submit'));
          await tester.ensureVisible(submit);
          await tester.pumpAndSettle();
          expect(tester.getSize(submit).height, greaterThanOrEqualTo(48));
          await tester.tap(submit);
          await tester.pump();
          expect(auth.emailSent, 'admin@example.test');
          expect(auth.passwordSent, 'input-password');
          expect(tester.widget<FilledButton>(submit).onPressed, isNull);
          expect(tester.widget<TextFormField>(password).enabled, isFalse);
          auth.hold!.complete();
          await tester.pumpAndSettle();
          expect(
            find.text(
              lang == 'es'
                  ? 'Esta cuenta no tiene acceso de administrador.'
                  : 'This account does not have administrator access.',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
      testWidgets(
        'account ${viewport.$1} ${viewport.$2} $lang read edit locked fields draft',
        (tester) async {
          await _pump(
            tester,
            const AccountScreen(),
            _Auth(signedIn: true),
            viewport.$1,
            viewport.$2,
            lang,
          );
          expect(find.text('Backend Name'), findsOneWidget);
          expect(find.text('backend@example.test'), findsOneWidget);
          expect(find.byKey(const Key('profile-card')), findsOneWidget);
          expect(
            find.byKey(
              ValueKey('settings-fields-${viewport.$1 >= 768 ? 2 : 1}'),
            ),
            findsOneWidget,
          );
          final edit = find.byKey(const Key('edit-profile'));
          await tester.scrollUntilVisible(
            edit,
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(edit);
          await tester.pumpAndSettle();
          expect(find.byType(TextField), findsNWidgets(2));
          expect(find.text('backend@example.test'), findsOneWidget);
          final name = find.byKey(const Key('profile-full-name'));
          expect(
            tester.widget<TextField>(name).decoration!.enabledBorder,
            isA<OutlineInputBorder>(),
          );
          await tester.enterText(name, 'Unsaved Backend Name');
          await tester.tap(find.byIcon(Icons.arrow_back).first);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          // Existing guard text is retained; no mutation is sent by cancelling it.
          await tester.tap(find.text('Keep editing'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(name).controller!.text,
            'Unsaved Backend Name',
          );
          await tester.drag(
            find.byType(ListView).first,
            const Offset(0, -1600),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
