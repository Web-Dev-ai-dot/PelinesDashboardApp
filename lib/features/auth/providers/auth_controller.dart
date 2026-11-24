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

  @override
  Future<AdminSession?> build() async {
    _auth = ref.watch(authRepositoryProvider);
    _account = ref.watch(accountRepositoryProvider);
    final subscription = _auth.authStateChanges.listen(
      (AuthState event) {
        if (event.event == AuthChangeEvent.signedOut && !state.isLoading) {
          state = const AsyncData<AdminSession?>(null);
        }
        if (event.event == AuthChangeEvent.tokenRefreshed &&
            state.hasError &&
            state.error is ApiException &&
            (state.error as ApiException).statusCode != 403) {
          unawaited(retrySession());
        }
      },
      onError: (Object _) {
        // SDK refresh failures also reach the awaiting request.
      },
    );
    ref.onDispose(subscription.cancel);

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

  void adoptCanonicalProfile(Profile profile) {
    final AdminSession? current = state.value;
    if (current == null ||
        current.profile.id != profile.id ||
        profile.role != ProfileRole.admin) {
      return;
    }
    state = AsyncData<AdminSession?>(
      AdminSession(profile: profile, email: current.email),
    );
  }

  Future<AdminSession?> _loadAdminProfile() async {
    final user = _auth.currentSession?.user.id;
    try {
      final Profile profile = await _account.getMe();
      if (!_auth.hasSession || user != _auth.currentSession?.user.id) {
        return null;
      }
      if (profile.role != ProfileRole.admin) {
        await _auth.signOut();
        throw const AdminAccessDeniedException();
      }
      if (user != null && profile.id != user) {
        throw const ApiException(
          message: 'The Pelines server returned an invalid profile.',
        );
      }
      return AdminSession(profile: profile, email: _auth.currentUserEmail);
    } on ApiException {
      if (!_auth.hasSession) return null;
      rethrow;
    }
  }
}

class AdminAccessDeniedException implements Exception {
  const AdminAccessDeniedException();

  @override
  String toString() => 'This account does not have administrator access.';
}
