import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/account/data/account_repository.dart';
import 'package:pelines_admin_app/features/account/models/profile.dart';
import 'package:pelines_admin_app/features/account/models/profile_edit.dart';
import 'package:pelines_admin_app/features/account/providers/profile_mutation_controller.dart';
import 'package:pelines_admin_app/features/auth/data/auth_repository.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'preflights, PATCHes once with the exact diff, and adopts GET result',
    () async {
      final _Harness harness = await _Harness.create();
      addTearDown(harness.dispose);
      harness.account.afterPatch = _profile(
        fullName: 'Grace',
        phone: '555',
        updatedAt: DateTime.utc(2026, 1, 3),
      );

      await harness.save(fullName: ' Grace ', phone: '555');

      expect(harness.account.updateCalls, 1);
      expect(harness.account.lastPatch, <String, dynamic>{'fullName': 'Grace'});
      expect(harness.state.phase, ProfileMutationPhase.success);
      expect(
        harness.container.read(authControllerProvider).value?.profile.fullName,
        'Grace',
      );
    },
  );

  test('clearing a field sends null', () async {
    final _Harness harness = await _Harness.create();
    addTearDown(harness.dispose);
    harness.account.afterPatch = _profile(
      fullName: 'Ada',
      updatedAt: DateTime.utc(2026, 1, 3),
    );

    await harness.save(fullName: 'Ada', phone: ' ');

    expect(harness.account.lastPatch, <String, dynamic>{'phone': null});
  });

  test(
    'a concurrent updatedAt change is a conflict and sends no PATCH',
    () async {
      final _Harness harness = await _Harness.create();
      addTearDown(harness.dispose);
      harness.account.current = _profile(
        fullName: 'Changed elsewhere',
        phone: '555',
        updatedAt: DateTime.utc(2026, 1, 4),
      );

      await harness.save(fullName: 'Grace', phone: '555');

      expect(harness.state.phase, ProfileMutationPhase.conflict);
      expect(harness.account.updateCalls, 0);
      expect(
        harness.container.read(authControllerProvider).value?.profile.fullName,
        'Changed elsewhere',
      );
    },
  );

  test('an identity change sends no PATCH', () async {
    final _Harness harness = await _Harness.create();
    addTearDown(harness.dispose);
    harness.account.current = _profile(id: 'different-id');

    await harness.save(fullName: 'Grace', phone: '555');

    expect(harness.state.phase, ProfileMutationPhase.error);
    expect(harness.account.updateCalls, 0);
  });

  test('a role downgrade sends no PATCH and signs out', () async {
    final _Harness harness = await _Harness.create();
    addTearDown(harness.dispose);
    harness.account.current = _profile(role: ProfileRole.customer);

    await harness.save(fullName: 'Grace', phone: '555');

    expect(harness.account.updateCalls, 0);
    expect(harness.auth.signOutCalls, 1);
  });

  test('timeout reconciles with GET and never retries PATCH', () async {
    final _Harness harness = await _Harness.create();
    addTearDown(harness.dispose);
    harness.account.afterPatch = _profile(
      fullName: 'Grace',
      phone: '555',
      updatedAt: DateTime.utc(2026, 1, 3),
    );
    harness.account.updateError = ApiException(
      message: 'Timed out.',
      cause: DioException(
        requestOptions: RequestOptions(path: '/me'),
        type: DioExceptionType.receiveTimeout,
      ),
    );

    await harness.save(fullName: 'Grace', phone: '555');

    expect(harness.account.updateCalls, 1);
    expect(harness.state.phase, ProfileMutationPhase.success);
  });
}

class _Harness {
  _Harness(this.container, this.auth, this.account, this.original);

  static Future<_Harness> create() async {
    final Profile original = _profile();
    final _FakeAuthRepository auth = _FakeAuthRepository();
    final _FakeAccountRepository account = _FakeAccountRepository(original);
    final ProviderContainer container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        accountRepositoryProvider.overrideWithValue(account),
      ],
    );
    await container.read(authControllerProvider.future);
    return _Harness(container, auth, account, original);
  }

  final ProviderContainer container;
  final _FakeAuthRepository auth;
  final _FakeAccountRepository account;
  final Profile original;

  ProfileMutationState get state => container.read(profileMutationProvider);

  Future<void> save({required String fullName, required String phone}) =>
      container
          .read(profileMutationProvider.notifier)
          .save(
            profileId: original.id,
            originalUpdatedAt: original.updatedAt,
            desired: ProfileDraft(fullName: fullName, phone: phone).validate(),
          );

  void dispose() => container.dispose();
}

class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository(this.current);

  Profile current;
  Profile? afterPatch;
  Object? updateError;
  int updateCalls = 0;
  Map<String, dynamic>? lastPatch;

  @override
  Future<Profile> getMe() async => current;

  @override
  Future<Profile> updateMe(Map<String, dynamic> patch) async {
    updateCalls++;
    lastPatch = Map<String, dynamic>.from(patch);
    if (afterPatch != null) current = afterPatch!;
    if (updateError != null) throw updateError!;
    return current;
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
  String? get currentUserEmail => 'auth@example.com';
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

Profile _profile({
  String id = 'profile-id',
  ProfileRole role = ProfileRole.admin,
  String? fullName = 'Ada',
  String? phone = '555',
  DateTime? updatedAt,
}) => Profile(
  id: id,
  role: role,
  fullName: fullName,
  phone: phone,
  createdAt: DateTime.utc(2026),
  updatedAt: updatedAt ?? DateTime.utc(2026, 1, 2),
);
