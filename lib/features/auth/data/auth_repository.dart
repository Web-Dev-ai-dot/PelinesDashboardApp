import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/password_change.dart';

abstract interface class AuthRepository {
  Session? get currentSession;

  bool get hasSession;

  String? get currentUserEmail;

  Stream<AuthState> get authStateChanges;

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  Future<String?> getAccessToken();
}

class SupabaseAuthRepository implements AuthRepository, PasswordAuthRepository {
  SupabaseAuthRepository(SupabaseClient client) : this.withAuth(client.auth);
  SupabaseAuthRepository.withAuth(this._auth);

  final GoTrueClient _auth;
  bool _passwordBusy = false;
  ({String? token, Future<void> future})? _refreshInFlight;
  String? _lastRefreshedToken;
  final Stopwatch _sinceRefresh = Stopwatch();

  @override
  Session? get currentSession => _auth.currentSession;

  @override
  bool get hasSession => currentSession != null;

  @override
  String? get currentUserEmail => _auth.currentUser?.email;

  @override
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  @override
  Future<void> signIn({required String email, required String password}) async {
    final AuthResponse response = await _auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (response.session == null) {
      throw const AuthException('Supabase did not return a session.');
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<String?> getAccessToken() async {
    final session = currentSession;
    if (session == null) return null;
    final running = _refreshInFlight;
    if (session.isExpired ||
        (running != null && running.token == session.refreshToken)) {
      return _refreshFor(session);
    }
    return session.accessToken;
  }

  Future<String?> recoverRejectedToken(String rejectedToken) async {
    final session = currentSession;
    if (session == null) return null;
    if (session.accessToken != rejectedToken) return getAccessToken();
    if (!session.isExpired &&
        rejectedToken == _lastRefreshedToken &&
        _sinceRefresh.elapsed < const Duration(seconds: 15)) {
      return null;
    }
    return _refreshFor(session);
  }

  Future<String?> _refreshFor(Session session) async {
    final running = _refreshInFlight;
    if (running != null && running.token == session.refreshToken) {
      await running.future;
    } else {
      final pending = (token: session.refreshToken, future: _refresh(session));
      _refreshInFlight = pending;
      try {
        await pending.future;
      } finally {
        if (_refreshInFlight == pending) _refreshInFlight = null;
      }
    }
    final current = currentSession;
    if (current == null ||
        current.user.id != session.user.id ||
        current.isExpired) {
      return null;
    }
    return current.accessToken;
  }

  Future<void> _refresh(Session original) async {
    try {
      // The SDK joins recovery and auto-refresh for the same refresh token.
      // Use currentSession afterward because the SDK discards stale results.
      final response = await _auth.refreshSession();
      final current = currentSession;
      if (current?.user.id == original.user.id &&
          current?.accessToken == response.session?.accessToken) {
        _lastRefreshedToken = current?.accessToken;
        _sinceRefresh
          ..reset()
          ..start();
      }
    } on AuthSessionMissingException {
      if (identical(currentSession, original) &&
          original.refreshToken == null) {
        await _auth.signOut(scope: SignOutScope.local);
      }
    } on AuthException {
      // GoTrue clears definitive failures and emits signedOut. A transient
      // failure keeps the session and is surfaced as a retryable request error.
      if (currentSession != null) rethrow;
    }
  }

  @override
  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
    String? nonce,
  }) async {
    if (_passwordBusy) {
      throw const PasswordChangeFailure(PasswordChangeError.rateLimited);
    }
    _passwordBusy = true;
    var updating = false;
    var verifyingPassword = false;
    try {
      final original = currentSession;
      if (original == null ||
          original.user.id != userId ||
          original.user.email == null) {
        throw const PasswordChangeFailure(PasswordChangeError.sessionExpired);
      }
      if (currentPassword.isEmpty ||
          newPassword.isEmpty ||
          newPassword == currentPassword) {
        throw const PasswordChangeFailure(PasswordChangeError.rejected);
      }
      final user = (await _auth.getUser()).user;
      if (user?.id != original.user.id ||
          currentSession?.user.id != original.user.id) {
        throw const PasswordChangeFailure(PasswordChangeError.sessionExpired);
      }
      // A password grant verifies the current credential even when the server
      // does not enforce current_password on updates. Keep the same account;
      // Supabase adopts/persists its fresh session through the existing SDK.
      verifyingPassword = true;
      final verified = await _auth.signInWithPassword(
        email: user!.email!,
        password: currentPassword,
      );
      verifyingPassword = false;
      if (verified.session == null ||
          verified.user?.id != original.user.id ||
          currentSession?.accessToken != verified.session!.accessToken) {
        throw const PasswordChangeFailure(PasswordChangeError.sessionExpired);
      }
      updating = true;
      final updated = await _auth.updateUser(
        UserAttributes(
          password: newPassword,
          currentPassword: currentPassword,
          nonce: nonce,
        ),
      );
      if (updated.user?.id != original.user.id ||
          currentSession?.user.id != original.user.id) {
        throw const PasswordChangeFailure(PasswordChangeError.uncertain);
      }
    } on PasswordChangeFailure {
      rethrow;
    } on AuthException catch (error) {
      throw _passwordError(
        error,
        verifyingPassword: verifyingPassword,
        updating: updating,
      );
    } on Object {
      throw PasswordChangeFailure(
        updating
            ? PasswordChangeError.uncertain
            : PasswordChangeError.unavailable,
      );
    } finally {
      _passwordBusy = false;
    }
  }

  @override
  Future<void> requestPasswordVerification({required String userId}) async {
    if (_passwordBusy) {
      throw const PasswordChangeFailure(PasswordChangeError.rateLimited);
    }
    _passwordBusy = true;
    try {
      final id = currentSession?.user.id;
      if (id == null ||
          id != userId ||
          (await _auth.getUser()).user?.id != id ||
          currentSession?.user.id != id) {
        throw const PasswordChangeFailure(PasswordChangeError.sessionExpired);
      }
      await _auth.reauthenticate();
    } on PasswordChangeFailure {
      rethrow;
    } on AuthException catch (error) {
      throw _passwordError(error);
    } on Object {
      throw const PasswordChangeFailure(PasswordChangeError.unavailable);
    } finally {
      _passwordBusy = false;
    }
  }

  PasswordChangeFailure _passwordError(
    AuthException error, {
    bool verifyingPassword = false,
    bool updating = false,
  }) {
    if (error is AuthSessionMissingException) {
      return const PasswordChangeFailure(PasswordChangeError.sessionExpired);
    }
    final reason = switch (error.code) {
      'invalid_credentials' when verifyingPassword =>
        PasswordChangeError.incorrectCurrent,
      'reauthentication_needed' ||
      'reauth_nonce_missing' => PasswordChangeError.reauthenticationRequired,
      'reauthentication_not_valid' => PasswordChangeError.invalidCode,
      'weak_password' || 'same_password' => PasswordChangeError.rejected,
      'session_not_found' ||
      'session_expired' ||
      'session_missing' ||
      'bad_jwt' ||
      'user_not_found' => PasswordChangeError.sessionExpired,
      'over_request_rate_limit' ||
      'over_email_send_rate_limit' => PasswordChangeError.rateLimited,
      _ when error.statusCode == '429' => PasswordChangeError.rateLimited,
      _ when error.statusCode == '401' || error.statusCode == '403' =>
        PasswordChangeError.sessionExpired,
      _
          when updating &&
              (error.statusCode == null ||
                  (int.tryParse(error.statusCode!) ?? 500) >= 500) =>
        PasswordChangeError.uncertain,
      _ when updating => PasswordChangeError.rejected,
      _ => PasswordChangeError.unavailable,
    };
    return PasswordChangeFailure(reason);
  }
}
