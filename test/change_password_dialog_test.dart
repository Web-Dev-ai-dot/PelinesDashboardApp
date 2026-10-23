import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/features/account/models/profile.dart';
import 'package:pelines_admin_app/features/account/presentation/account_screen.dart';
import 'package:pelines_admin_app/features/auth/models/admin_session.dart';
import 'package:pelines_admin_app/features/auth/models/password_change.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_controller.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_providers.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';

import 'section_location_context_test.dart' show HeaderLocation;

Finder key(String value) => find.byKey(Key(value));

Future<void> _pump(
  WidgetTester tester,
  _Passwords repository, {
  double width = 390,
  double scale = 1,
  double keyboard = 0,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_Admin.new),
        passwordAuthRepositoryProvider.overrideWithValue(repository),
        currentLocationProvider.overrideWith(HeaderLocation.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: const AccountScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> open(WidgetTester tester) async {
  await tester.ensureVisible(key('profile-change-password'));
  await tester.pumpAndSettle();
  await tester.tap(key('profile-change-password'));
  await tester.pumpAndSettle();
}

Future<void> fill(
  WidgetTester tester, {
  String confirm = 'new-test-value',
}) async {
  for (final entry in {
    'password-current': 'current-test-value',
    'password-new': 'new-test-value',
    'password-confirm': confirm,
  }.entries) {
    await tester.ensureVisible(key(entry.key));
    await tester.pumpAndSettle();
    await tester.enterText(key(entry.key), entry.value);
  }
  await tester.pumpAndSettle();
}

Future<void> submit(WidgetTester tester) async {
  await tester.ensureVisible(key('password-update'));
  await tester.pumpAndSettle();
  await tester.tap(key('password-update'));
  await tester.pump();
}

void main() {
  testWidgets('open cancel clears secrets and preserves dirty My Profile', (
    tester,
  ) async {
    await _pump(tester, _Passwords());
    await tester.enterText(key('profile-full-name'), 'Unsaved profile draft');
    await open(tester);
    await fill(tester);
    final current = tester
        .widget<TextField>(key('password-current'))
        .controller!;
    await tester.tap(key('password-cancel'));
    await tester.pumpAndSettle();
    expect(current.text, isEmpty);
    expect(
      tester.widget<TextField>(key('profile-full-name')).controller!.text,
      'Unsaved profile draft',
    );
    expect(
      tester.widget<FilledButton>(key('profile-save')).onPressed,
      isNotNull,
    );
    await open(tester);
    expect(
      tester.widget<TextField>(key('password-new')).controller!.text,
      isEmpty,
    );
  });
  testWidgets(
    'mismatch never calls repository; visibility toggles are independent',
    (tester) async {
      final repository = _Passwords();
      await _pump(tester, repository);
      await open(tester);
      await fill(tester, confirm: 'different');
      await tester.ensureVisible(key('password-current'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: key('password-current'),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(key('password-current')).obscureText,
        isFalse,
      );
      expect(tester.widget<TextField>(key('password-new')).obscureText, isTrue);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('The new passwords do not match.'), findsOneWidget);
      expect(repository.changes, 0);
    },
  );
  for (final reason in [
    PasswordChangeError.incorrectCurrent,
    PasswordChangeError.rejected,
    PasswordChangeError.unavailable,
    PasswordChangeError.uncertain,
    PasswordChangeError.sessionExpired,
  ]) {
    testWidgets(
      'safe error $reason keeps profile and controls retry correctly',
      (tester) async {
        final repository = _Passwords()..error = reason;
        await _pump(tester, repository);
        await open(tester);
        await fill(tester);
        await submit(tester);
        await tester.pumpAndSettle();
        expect(
          find.text(PasswordChangeFailure(reason).message),
          findsOneWidget,
        );
        final blocked =
            reason == PasswordChangeError.uncertain ||
            reason == PasswordChangeError.sessionExpired;
        expect(
          tester.widget<FilledButton>(key('password-update')).onPressed == null,
          blocked,
        );
        expect(repository.changes, 1);
        expect(
          find.byKey(const Key('profile-card'), skipOffstage: false),
          findsOneWidget,
        );
      },
    );
  }
  testWidgets(
    'busy blocks duplicates and dismissal; success clears all fields',
    (tester) async {
      final repository = _Passwords()..hold = Completer<void>();
      await _pump(tester, repository);
      await open(tester);
      await fill(tester);
      final current = tester
          .widget<TextField>(key('password-current'))
          .controller!;
      await submit(tester);
      expect(
        tester.widget<FilledButton>(key('password-update')).onPressed,
        isNull,
      );
      expect(
        tester.widget<OutlinedButton>(key('password-cancel')).onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(key('change-password-dialog'), findsOneWidget);
      expect(repository.changes, 1);
      repository.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Your password was updated.'), findsOneWidget);
      expect(current.text, isEmpty);
      await tester.tap(key('password-cancel'));
      await tester.pumpAndSettle();
      expect(key('change-password-dialog'), findsNothing);
    },
  );
  testWidgets('challenge sends only on request and retries with code', (
    tester,
  ) async {
    final repository = _Passwords()
      ..error = PasswordChangeError.reauthenticationRequired;
    await _pump(tester, repository);
    await open(tester);
    await fill(tester);
    await submit(tester);
    await tester.pumpAndSettle();
    expect(repository.requests, 0);
    await tester.ensureVisible(key('password-send-code'));
    await tester.pumpAndSettle();
    await tester.tap(key('password-send-code'));
    await tester.pumpAndSettle();
    expect(repository.requests, 1);
    await tester.ensureVisible(key('password-code'));
    await tester.enterText(key('password-code'), '123456');
    repository.error = PasswordChangeError.invalidCode;
    await submit(tester);
    await tester.pumpAndSettle();
    expect(
      find.text(
        const PasswordChangeFailure(PasswordChangeError.invalidCode).message,
      ),
      findsOneWidget,
    );
    repository.error = null;
    await submit(tester);
    await tester.pumpAndSettle();
    expect(repository.nonce, '123456');
    expect(find.text('Your password was updated.'), findsOneWidget);
  });
  for (final size in [(320.0, 2.0), (768.0, 1.0)]) {
    testWidgets('responsive dialog scroll and keyboard $size', (tester) async {
      await _pump(
        tester,
        _Passwords(),
        width: size.$1,
        scale: size.$2,
        keyboard: 300,
      );
      await open(tester);
      await fill(tester);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('Your password was updated.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

class _Passwords implements PasswordAuthRepository {
  PasswordChangeError? error;
  Completer<void>? hold;
  int changes = 0, requests = 0;
  String? nonce;
  @override
  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
    String? nonce,
  }) async {
    changes++;
    this.nonce = nonce;
    await hold?.future;
    if (error != null) throw PasswordChangeFailure(error!);
  }

  @override
  Future<void> requestPasswordVerification({required String userId}) async {
    requests++;
  }
}

class _Admin extends AuthController {
  @override
  Future<AdminSession?> build() async => AdminSession(
    email: 'admin@example.test',
    profile: Profile(
      id: 'admin',
      role: ProfileRole.admin,
      fullName: 'Admin',
      phone: '',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  );
}
