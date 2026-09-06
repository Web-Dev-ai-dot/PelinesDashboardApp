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
    'shows canonical profile, auth email, nulls, and read-only role',
    (WidgetTester tester) async {
      final _WidgetHarness harness = await _WidgetHarness.pump(
        tester,
        _profile(fullName: null, phone: null),
      );
      addTearDown(harness.dispose);

      expect(find.text('Not set'), findsNWidgets(2));
      expect(find.text('session@example.com'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Read-only'), findsNWidgets(2));
    },
  );

  testWidgets('logout requires confirmation and uses AuthController signOut', (
    WidgetTester tester,
  ) async {
    final _WidgetHarness harness = await _WidgetHarness.pump(
      tester,
      _profile(),
    );
    addTearDown(harness.dispose);

    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-log-out')));
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);
    expect(
      find.text('You will need to sign in again to access the dashboard.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('logout-cancel')));
    await tester.pumpAndSettle();
    expect(harness.auth.signOutCalls, 0);

    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-log-out')));
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

      await tester.tap(find.byKey(const Key('edit-profile')));
      await tester.pumpAndSettle();
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
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Profile'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);
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
      ],
    );
    await container.read(authControllerProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AccountScreen()),
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

  @override
  Future<Profile> getMe() async => profile;
  @override
  Future<Profile> updateMe(Map<String, dynamic> patch) async {
    updateCalls++;
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
