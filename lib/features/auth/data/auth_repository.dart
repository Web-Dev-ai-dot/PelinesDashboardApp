import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AuthRepository {
  Session? get currentSession;

  bool get hasSession;

  String? get currentUserEmail;

  Stream<AuthState> get authStateChanges;

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  Future<String?> getAccessToken();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Session? get currentSession => _client.auth.currentSession;

  @override
  bool get hasSession => currentSession != null;

  @override
  String? get currentUserEmail => _client.auth.currentUser?.email;

  @override
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  @override
  Future<void> signIn({required String email, required String password}) async {
    final AuthResponse response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (response.session == null) {
      throw const AuthException('Supabase did not return a session.');
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<String?> getAccessToken() async =>
      _client.auth.currentSession?.accessToken;
}
