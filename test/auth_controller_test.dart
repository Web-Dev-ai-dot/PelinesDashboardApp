import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/account/data/account_repository.dart';
import 'package:pelines_admin_app/features/account/models/profile.dart';
import 'package:pelines_admin_app/features/auth/data/auth_repository.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_controller.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('a non-admin profile is signed out and denied', () async {
    final _FakeAuthRepository auth = _FakeAuthRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        accountRepositoryProvider.overrideWithValue(
          _FakeAccountRepository(_profile(ProfileRole.customer)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    await container
        .read(authControllerProvider.notifier)
        .signIn(email: 'customer@example.com', password: 'secret');

    final AsyncValue<Object?> result = container.read(authControllerProvider);
    expect(result.error, isA<AdminAccessDeniedException>());
    expect(auth.signOutCalls, 1);
  });

  test('an admin profile becomes an authenticated admin session', () async {
    final _FakeAuthRepository auth = _FakeAuthRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        accountRepositoryProvider.overrideWithValue(
          _FakeAccountRepository(_profile(ProfileRole.admin)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    await container
        .read(authControllerProvider.notifier)
        .signIn(email: 'admin@example.com', password: 'secret');

    expect(
      container.read(authControllerProvider).value?.profile.role,
      ProfileRole.admin,
    );
  });
}

Profile _profile(ProfileRole role) => Profile(
  id: '10cebd42-65df-46a8-b0bf-6aeaf02bc33f',
  role: role,
  fullName: 'Test User',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _FakeAuthRepository implements AuthRepository {
  bool _hasSession = false;
  int signOutCalls = 0;

  @override
  Stream<AuthState> get authStateChanges => const Stream<AuthState>.empty();

  @override
  Session? get currentSession => null;

  @override
  String? get currentUserEmail => 'admin@example.com';

  @override
  bool get hasSession => _hasSession;

  @override
  Future<String?> getAccessToken() async => 'test-token';

  @override
  Future<void> signIn({required String email, required String password}) async {
    _hasSession = true;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _hasSession = false;
  }
}

class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository(this.profile);

  final Profile profile;

  @override
  Future<Profile> getMe() async => profile;

  @override
  Future<Profile> updateMe(Map<String, dynamic> patch) async => profile;
}
