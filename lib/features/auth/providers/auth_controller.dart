import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/api_exception.dart';
import '../../account/data/account_repository.dart';
import '../../account/models/profile.dart';
import '../data/auth_repository.dart';
import '../models/admin_session.dart';
import 'auth_providers.dart';

class AuthController extends AsyncNotifier<AdminSession?> {
  late AuthRepository _auth;
  late AccountRepository _account;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  Future<AdminSession?> build() async {
    _auth = ref.watch(authRepositoryProvider);
    _account = ref.watch(accountRepositoryProvider);
    _authSubscription = _auth.authStateChanges.listen((AuthState event) {
      if (event.event == AuthChangeEvent.signedOut && state.value != null) {
        state = const AsyncData<AdminSession?>(null);
      }
    });
    ref.onDispose(() => _authSubscription?.cancel());

    if (!_auth.hasSession) {
      return null;
    }
    return _loadAdminProfile();
  }

  Future<void> signIn({required String email, required String password}) async {
    if (state.isLoading) return;
    state = const AsyncLoading<AdminSession?>();
    state = await AsyncValue.guard(() async {
      await _auth.signIn(email: email, password: password);
      return _loadAdminProfile();
    });
  }

  Future<void> retrySession() async {
    if (state.isLoading) return;
    state = const AsyncLoading<AdminSession?>();
    state = await AsyncValue.guard(() async {
      if (!_auth.hasSession) return null;
      return _loadAdminProfile();
    });
  }

  Future<void> signOut() async {
    if (state.isLoading) return;
    state = const AsyncLoading<AdminSession?>();
    state = await AsyncValue.guard(() async {
      await _auth.signOut();
      return null;
    });
  }

  Future<AdminSession> _loadAdminProfile() async {
    try {
      final Profile profile = await _account.getMe();
      if (profile.role != ProfileRole.admin) {
        await _auth.signOut();
        throw const AdminAccessDeniedException();
      }
      return AdminSession(profile: profile, email: _auth.currentUserEmail);
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _auth.signOut();
      }
      rethrow;
    }
  }
}

class AdminAccessDeniedException implements Exception {
  const AdminAccessDeniedException();

  @override
  String toString() => 'This account does not have administrator access.';
}
