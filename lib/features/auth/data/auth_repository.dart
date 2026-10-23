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
  Future<String?> getAccessToken() async => _auth.currentSession?.accessToken;

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
