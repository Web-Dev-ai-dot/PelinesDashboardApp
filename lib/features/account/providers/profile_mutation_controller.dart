import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/account_repository.dart';
import '../models/profile.dart';
import '../models/profile_edit.dart';

enum ProfileMutationPhase {
  idle,
  preflight,
  submitting,
  reconciling,
  success,
  conflict,
  error,
}

class ProfileMutationState {
  const ProfileMutationState({
    this.phase = ProfileMutationPhase.idle,
    this.message,
  });

  final ProfileMutationPhase phase;
  final String? message;
  bool get isBusy =>
      phase == ProfileMutationPhase.preflight ||
      phase == ProfileMutationPhase.submitting ||
      phase == ProfileMutationPhase.reconciling;
}

final profileMutationProvider =
    NotifierProvider<ProfileMutationController, ProfileMutationState>(
      ProfileMutationController.new,
    );

class ProfileMutationController extends Notifier<ProfileMutationState> {
  @override
  ProfileMutationState build() => const ProfileMutationState();

  void reset() => state = const ProfileMutationState();

  Future<void> save({
    required String profileId,
    required DateTime originalUpdatedAt,
    required ProfileDraftResult desired,
  }) async {
    if (state.isBusy || !desired.isValid) return;
    if (!_hasSession()) {
      _error('Your session is no longer available. Please sign in again.');
      return;
    }
    final AccountRepository repository = ref.read(accountRepositoryProvider);
    state = const ProfileMutationState(phase: ProfileMutationPhase.preflight);
    late Profile canonical;
    try {
      canonical = await repository.getMe();
    } catch (error) {
      await _handleError(error, 'Your profile could not be checked.');
      return;
    }
    if (!_hasSession()) {
      _error('Your session changed. No profile update was sent.');
      return;
    }
    if (canonical.id != profileId) {
      _error('The signed-in profile changed. No profile update was sent.');
      return;
    }
    if (canonical.role != ProfileRole.admin) {
      _error('This account no longer has administrator access.');
      await ref.read(authControllerProvider.notifier).signOut();
      return;
    }
    if (canonical.updatedAt != originalUpdatedAt.toUtc()) {
      _adopt(canonical);
      state = const ProfileMutationState(
        phase: ProfileMutationPhase.conflict,
        message: 'Your profile was changed elsewhere.',
      );
      return;
    }
    final Map<String, dynamic> patch = profilePatch(canonical, desired);
    if (patch.isEmpty) {
      _adopt(canonical);
      state = const ProfileMutationState(phase: ProfileMutationPhase.success);
      return;
    }
    state = const ProfileMutationState(phase: ProfileMutationPhase.submitting);
    try {
      await repository.updateMe(patch);
    } catch (error) {
      if (!_ambiguous(error)) {
        await _handleError(error, 'Your profile could not be updated.');
        return;
      }
      await _reconcile(repository, profileId, patch, ambiguous: true);
      return;
    }
    await _reconcile(repository, profileId, patch, ambiguous: false);
  }

  Future<void> _reconcile(
    AccountRepository repository,
    String profileId,
    Map<String, dynamic> patch, {
    required bool ambiguous,
  }) async {
    state = const ProfileMutationState(phase: ProfileMutationPhase.reconciling);
    try {
      final Profile canonical = await repository.getMe();
      if (!_hasSession()) {
        _error(
          'Your session changed. The profile result could not be adopted.',
        );
        return;
      }
      if (canonical.id != profileId || canonical.role != ProfileRole.admin) {
        _error(
          'The signed-in profile changed. The update result is uncertain.',
        );
        return;
      }
      _adopt(canonical);
      final bool matches =
          (!patch.containsKey('fullName') ||
              canonical.fullName == patch['fullName']) &&
          (!patch.containsKey('phone') || canonical.phone == patch['phone']);
      state = ProfileMutationState(
        phase: matches
            ? ProfileMutationPhase.success
            : ProfileMutationPhase.error,
        message: matches && ambiguous
            ? 'Your profile update was confirmed after reconnecting.'
            : matches
            ? null
            : ambiguous
            ? 'The update could not be confirmed. Reload and try again manually.'
            : 'The server did not save the expected profile values.',
      );
    } catch (error) {
      await _handleError(
        error,
        ambiguous
            ? 'The update result could not be confirmed. Reload before retrying.'
            : 'Your profile could not be reloaded.',
      );
    }
  }

  bool _hasSession() => ref.read(authRepositoryProvider).hasSession;

  void _adopt(Profile profile) =>
      ref.read(authControllerProvider.notifier).adoptCanonicalProfile(profile);

  Future<void> _handleError(Object error, String fallback) async {
    if (error is ApiException &&
        (error.statusCode == 401 || error.statusCode == 403)) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
    _error(error is ApiException ? error.message : fallback);
  }

  void _error(String message) {
    state = ProfileMutationState(
      phase: ProfileMutationPhase.error,
      message: message,
    );
  }

  bool _ambiguous(Object error) {
    if (error is! ApiException ||
        error.statusCode != null ||
        error.cause is! DioException) {
      return false;
    }
    final DioExceptionType type = (error.cause! as DioException).type;
    return type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.sendTimeout ||
        type == DioExceptionType.receiveTimeout ||
        type == DioExceptionType.connectionError;
  }
}
