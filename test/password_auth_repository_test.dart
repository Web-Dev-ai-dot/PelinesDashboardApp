import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pelines_admin_app/features/auth/data/auth_repository.dart';
import 'package:pelines_admin_app/features/auth/models/password_change.dart';

Matcher failure(PasswordChangeError reason) =>
    isA<PasswordChangeFailure>().having((e) => e.reason, 'reason', reason);

void main() {
  late _Auth auth;
  late SupabaseAuthRepository repository;
  setUp(() {
    auth = _Auth();
    repository = SupabaseAuthRepository.withAuth(auth);
  });
  tearDown(() => auth.dispose());
  Future<void> change({String? nonce}) => repository.changePassword(
    userId: 'admin',
    currentPassword: 'current-test-value',
    newPassword: 'new-test-value',
    nonce: nonce,
  );

  test('server session then password grant then update, preserving the same account', () async {
    await change();
    expect(auth.calls, ['getUser', 'passwordGrant', 'updateUser']);
    expect(auth.attributes!.currentPassword, 'current-test-value');
    expect(auth.attributes!.password, 'new-test-value');
    expect(repository.currentSession!.user.id, 'admin');
    expect(auth.signOutCalls, 0);
  });
  test(
    'wrong current password never reaches update and preserves old session',
    () async {
      final before = auth.session;
      auth.signInError = const AuthException(
        'never surface provider text',
        code: 'invalid_credentials',
      );
      await expectLater(
        change(),
        throwsA(failure(PasswordChangeError.incorrectCurrent)),
      );
      expect(auth.attributes, isNull);
      expect(auth.session, same(before));
    },
  );
  test(
    'missing or server-invalid session never authenticates or updates',
    () async {
      auth.session = null;
      await expectLater(
        change(),
        throwsA(failure(PasswordChangeError.sessionExpired)),
      );
      expect(auth.calls, isEmpty);
      auth.session = _session('admin');
      auth.getUserError = const AuthException(
        'expired',
        code: 'session_expired',
      );
      await expectLater(
        change(),
        throwsA(failure(PasswordChangeError.sessionExpired)),
      );
      expect(auth.calls, ['getUser']);
    },
  );
  test('different verified identity blocks update', () async {
    auth.verifiedId = 'another-user';
    await expectLater(
      change(),
      throwsA(failure(PasswordChangeError.sessionExpired)),
    );
    expect(auth.attributes, isNull);
  });
  test('provider enforces policy, raw error is not exposed', () async {
    auth.updateError = const AuthException(
      'sensitive provider details',
      code: 'weak_password',
    );
    await expectLater(change(), throwsA(failure(PasswordChangeError.rejected)));
  });
  test('reauthentication is explicit and nonce is passed on retry', () async {
    auth.updateError = const AuthException(
      'challenge',
      code: 'reauthentication_needed',
    );
    await expectLater(
      change(),
      throwsA(failure(PasswordChangeError.reauthenticationRequired)),
    );
    expect(auth.codeRequests, 0);
    await repository.requestPasswordVerification(userId: 'admin');
    expect(auth.codeRequests, 1);
    auth.updateError = null;
    await change(nonce: '123456');
    expect(auth.attributes!.nonce, '123456');
  });
  test('invalid code and rate limits are classified', () async {
    auth.updateError = const AuthException(
      'bad code',
      code: 'reauthentication_not_valid',
    );
    await expectLater(
      change(nonce: '123456'),
      throwsA(failure(PasswordChangeError.invalidCode)),
    );
    auth.updateError = const AuthException('limited', statusCode: '429');
    await expectLater(
      change(),
      throwsA(failure(PasswordChangeError.rateLimited)),
    );
  });
  test(
    'network before update is retryable; ambiguous write is never retried',
    () async {
      auth.signInError = AuthRetryableFetchException();
      await expectLater(
        change(),
        throwsA(failure(PasswordChangeError.unavailable)),
      );
      expect(auth.attributes, isNull);
      auth.signInError = null;
      auth.updateError = AuthRetryableFetchException();
      await expectLater(
        change(),
        throwsA(failure(PasswordChangeError.uncertain)),
      );
      expect(auth.calls.where((e) => e == 'updateUser').length, 1);
    },
  );
  test('repository blocks concurrent submissions', () async {
    auth.hold = Completer<void>();
    final pending = change();
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      change(),
      throwsA(failure(PasswordChangeError.rateLimited)),
    );
    auth.hold!.complete();
    await pending;
    expect(auth.calls.where((e) => e == 'updateUser').length, 1);
  });
}

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  email: 'admin@example.test',
  createdAt: '2026-01-01T00:00:00Z',
);
Session _session(String id) => Session(
  accessToken: 'test-token-$id',
  tokenType: 'bearer',
  refreshToken: 'test-refresh',
  user: _user(id),
);

class _Auth extends GoTrueClient {
  _Auth()
    : super(url: 'https://example.invalid/auth/v1', autoRefreshToken: false);
  Session? session = _session('admin');
  String verifiedId = 'admin';
  AuthException? getUserError, signInError, updateError;
  UserAttributes? attributes;
  Completer<void>? hold;
  final calls = <String>[];
  int codeRequests = 0, signOutCalls = 0;
  @override
  Session? get currentSession => session;
  @override
  User? get currentUser => session?.user;
  @override
  Future<UserResponse> getUser([String? jwt]) async {
    calls.add('getUser');
    if (getUserError != null) throw getUserError!;
    return UserResponse.fromJson({
      'id': session!.user.id,
      'email': 'admin@example.test',
    });
  }

  @override
  Future<AuthResponse> signInWithPassword({
    String? email,
    String? phone,
    required String password,
    String? captchaToken,
  }) async {
    calls.add('passwordGrant');
    if (signInError != null) throw signInError!;
    session = _session(verifiedId);
    return AuthResponse(session: session);
  }

  @override
  Future<UserResponse> updateUser(
    UserAttributes attributes, {
    String? emailRedirectTo,
  }) async {
    calls.add('updateUser');
    this.attributes = attributes;
    await hold?.future;
    if (updateError != null) throw updateError!;
    return UserResponse.fromJson({'id': session!.user.id});
  }

  @override
  Future<void> reauthenticate() async {
    codeRequests++;
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {
    signOutCalls++;
  }
}
