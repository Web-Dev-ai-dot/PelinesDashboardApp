import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/locations/presentation/pelines_location_context.dart';

import 'section_location_context_test.dart' show HeaderLocation;

import 'package:pelines_admin_app/app/navigation/admin_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/account/data/account_repository.dart';
import 'package:pelines_admin_app/features/account/models/profile.dart';
import 'package:pelines_admin_app/features/account/presentation/account_screen.dart';
import 'package:pelines_admin_app/features/auth/data/auth_repository.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets(
    'inline save keeps the page, blocks repeats and adopts canonical data',
    (tester) async {
      final harness = await _WidgetHarness.pump(tester, _profile());
      addTearDown(harness.dispose);
      harness.account.hold = Completer<void>();
      await tester.enterText(
        find.byKey(const Key('profile-full-name')),
        'Grace',
      );
      final save = find.byKey(const Key('profile-save'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(harness.account.updateCalls, 1);
      harness.account.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Profile updated.'), findsOneWidget);
      expect(find.byKey(const Key('profile-card')), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(
        harness.container.read(authControllerProvider).value!.profile.fullName,
        'Grace',
      );
      expect(harness.account.updateCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'location context changes retain the account draft and password action',
    (tester) async {
      final harness = await _WidgetHarness.pump(tester, _profile());
      addTearDown(harness.dispose);
      final name = find.byKey(const Key('profile-full-name'));
      await tester.enterText(name, 'Unsaved');
      (harness.container.read(
        currentLocationProvider.notifier,
      ) as HeaderLocation).replace(null);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(name).controller!.text, 'Unsaved');
      expect(find.byType(PelinesLocationContext), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('profile-change-password')),
            )
            .onPressed,
        isNotNull,
      );
      expect(harness.account.updateCalls, 0);
    },
  );
  testWidgets('section change awaits the real profile discard confirmation', (
    tester,
  ) async {
    final harness = await _WidgetHarness.pump(tester, _profile());
    addTearDown(harness.dispose);
    expect(find.byKey(const Key('account-log-out')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('profile-full-name')),
      'Unsaved name',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('nav-orders')));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved name'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-orders')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('orders-page')), findsOneWidget);
    expect(harness.account.updateCalls, 0);
  });
  testWidgets('shows editable canonical profile and read-only auth email', (
    WidgetTester tester,
  ) async {
    final _WidgetHarness harness = await _WidgetHarness.pump(
      tester,
      _profile(fullName: null, phone: null),
    );
    addTearDown(harness.dispose);

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('profile-full-name')))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('profile-phone')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.byType(PelinesLocationContext), findsOneWidget);
    expect(find.text('Tualatin · 7670 SW Nyberg St'), findsOneWidget);
    expect(find.text('session@example.com'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('profile-email')),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      isTrue,
    );
  });

  testWidgets('logout requires confirmation and uses AuthController signOut', (
    WidgetTester tester,
  ) async {
    final _WidgetHarness harness = await _WidgetHarness.pump(
      tester,
      _profile(),
    );
    addTearDown(harness.dispose);

    await tester.drag(find.byType(ListView).last, const Offset(0, -350));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-sign-out')));
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);
    expect(
      find.text('You will need to sign in again to access the dashboard.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('logout-cancel')));
    await tester.pumpAndSettle();
    expect(harness.auth.signOutCalls, 0);

    await tester.drag(find.byType(ListView).last, const Offset(0, -350));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-sign-out')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logout-confirm')));
    await tester.pumpAndSettle();
    expect(harness.auth.signOutCalls, 1);
  });

  testWidgets(
    'reverting edits restores clean state and discard protects changes',
    (WidgetTester tester) async {
      final _WidgetHarness harness = await _WidgetHarness.pump(
        tester,
        _profile(),
      );
      addTearDown(harness.dispose);

      final Finder name = find.byKey(const Key('profile-full-name'));
      final Finder save = find.byKey(const Key('profile-save'));
      await tester.enterText(name, 'Grace');
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.enterText(name, 'Ada');
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(harness.account.updateCalls, 0);

      await tester.enterText(name, 'Grace');
      await tester.pump();
      await tester.tap(find.byKey(const Key('nav-orders')));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-card')), findsOneWidget);
      await tester.tap(find.byKey(const Key('nav-orders')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('orders-page')), findsOneWidget);
      expect(harness.account.updateCalls, 0);
    },
  );
}

class _WidgetHarness {
  _WidgetHarness(this.container, this.auth, this.account);

  static Future<_WidgetHarness> pump(
    WidgetTester tester,
    Profile profile,
  ) async {
    final _FakeAuthRepository auth = _FakeAuthRepository();
    final _FakeAccountRepository account = _FakeAccountRepository(profile);
    final ProviderContainer container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        accountRepositoryProvider.overrideWithValue(account),
        currentLocationProvider.overrideWith(HeaderLocation.new),
      ],
    );
    await container.read(authControllerProvider.future);
    final navigation = AdminNavigationController();
    final router = GoRouter(
      initialLocation: '/app/account',
      routes: [
        ShellRoute(
          observers: [navigation],
          builder: (context, state, child) => AdminNavigationShell(
            controller: navigation,
            path: state.uri.path,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/app/account',
              builder: (_, _) => const AccountScreen(),
            ),
            GoRoute(
              path: '/app',
              builder: (_, _) => const Scaffold(key: Key('orders-page')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return _WidgetHarness(container, auth, account);
  }

  final ProviderContainer container;
  final _FakeAuthRepository auth;
  final _FakeAccountRepository account;
  void dispose() => container.dispose();
}

class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository(this.profile);
  Profile profile;
  int updateCalls = 0;
  Completer<void>? hold;

  @override
  Future<Profile> getMe() async => profile;
  @override
  Future<Profile> updateMe(Map<String, dynamic> patch) async {
    updateCalls++;
    await hold?.future;
    profile = Profile(
      id: profile.id,
      role: profile.role,
      fullName: patch.containsKey('fullName')
          ? patch['fullName'] as String?
          : profile.fullName,
      phone: patch.containsKey('phone')
          ? patch['phone'] as String?
          : profile.phone,
      createdAt: profile.createdAt,
      updatedAt: profile.updatedAt.add(const Duration(seconds: 1)),
    );
    return profile;
  }
}

class _FakeAuthRepository implements AuthRepository {
  bool session = true;
  int signOutCalls = 0;

  @override
  Stream<AuthState> get authStateChanges => const Stream<AuthState>.empty();
  @override
  Session? get currentSession => null;
  @override
  String? get currentUserEmail => 'session@example.com';
  @override
  bool get hasSession => session;
  @override
  Future<String?> getAccessToken() async => 'token';
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {
    signOutCalls++;
    session = false;
  }
}

Profile _profile({String? fullName = 'Ada', String? phone = '555'}) => Profile(
  id: 'profile-id',
  role: ProfileRole.admin,
  fullName: fullName,
  phone: phone,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026, 1, 2),
);
