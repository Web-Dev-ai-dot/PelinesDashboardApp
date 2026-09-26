import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../data/auto_cancellation_repository.dart';
import '../data/locations_repository.dart';
import '../models/auto_cancellation.dart';
import '../models/location.dart';
import 'locations_providers.dart';
import 'service_preferences_write_lock.dart';

enum AutoCancellationPhase {
  idle,
  submitting,
  reconciling,
  success,
  conflict,
  error,
}

class AutoCancellationState {
  const AutoCancellationState({
    this.phase = AutoCancellationPhase.idle,
    this.message,
  });
  final AutoCancellationPhase phase;
  final String? message;
  bool get isBusy =>
      phase == AutoCancellationPhase.submitting ||
      phase == AutoCancellationPhase.reconciling;
}

final autoCancellationRepositoryProvider = Provider<AutoCancellationRepository>(
  (ref) => ref.watch(locationsRepositoryProvider) as AutoCancellationRepository,
);
final autoCancellationProvider =
    NotifierProvider.family<
      AutoCancellationController,
      AutoCancellationState,
      PickupOrderKind
    >(AutoCancellationController.new);

class AutoCancellationController extends Notifier<AutoCancellationState> {
  AutoCancellationController(this.kind);
  final PickupOrderKind kind;
  @override
  AutoCancellationState build() => const AutoCancellationState();

  Future<AutoCancellationState> save({
    required String locationId,
    required DateTime originalUpdatedAt,
    required AutoCancellationRule original,
    required AutoCancellationRule rule,
  }) async {
    if (state.isBusy) return state;
    if (!_matches(locationId)) {
      return _error('The selected location changed. No change was sent.');
    }
    final validation = rule.validate(kind);
    if (validation != null) return _error(validation);
    final lock = ref.read(servicePreferencesWriteProvider.notifier);
    if (!lock.tryAcquire()) {
      return _error('Another service setting is being saved. Please wait.');
    }
    try {
      state = const AutoCancellationState(
        phase: AutoCancellationPhase.submitting,
      );
      try {
        await ref
            .read(autoCancellationRepositoryProvider)
            .saveAutoCancellationSettings(
              locationId: locationId,
              originalUpdatedAt: originalUpdatedAt,
              kind: kind,
              original: original,
              rule: rule,
              canWrite: () => _matches(locationId),
            );
      } on LocationSettingsConflict catch (conflict) {
        if (_matches(locationId)) _adopt(conflict.canonical);
        return state = const AutoCancellationState(
          phase: AutoCancellationPhase.conflict,
          message:
              'Store settings were changed elsewhere. Reload before saving.',
        );
      } catch (error) {
        if (!_ambiguous(error)) return _error(_message(error));
        return await _reconcile(locationId, original, rule, ambiguous: true);
      }
      return await _reconcile(locationId, original, rule, ambiguous: false);
    } finally {
      lock.release();
    }
  }

  Future<AutoCancellationState> _reconcile(
    String id,
    AutoCancellationRule original,
    AutoCancellationRule rule, {
    required bool ambiguous,
  }) async {
    state = const AutoCancellationState(
      phase: AutoCancellationPhase.reconciling,
    );
    try {
      final canonical = await ref
          .read(locationsRepositoryProvider)
          .getLocation(id);
      if (!_matches(id)) {
        return _error(
          'The selected location changed. No further change was sent.',
        );
      }
      final effective = AutoCancellationRule.fromJson(
        canonical.servicePrefsJson,
        kind,
      );
      final changes = rule.changesFrom(original, kind);
      final matches =
          effective.sameAs(rule) &&
          changes.entries.every(
            (entry) => canonical.servicePrefsJson?[entry.key] == entry.value,
          );
      _adopt(canonical);
      if (!matches) {
        return _error(
          'The auto-cancel change could not be confirmed. Reload before retrying.',
        );
      }
      return state = const AutoCancellationState(
        phase: AutoCancellationPhase.success,
        message: 'Auto-cancel settings saved.',
      );
    } catch (error) {
      return _error(
        ambiguous
            ? 'The auto-cancel change could not be confirmed. Reload before retrying.'
            : _message(error),
      );
    }
  }

  bool _matches(String id) => ref.read(currentLocationProvider).value?.id == id;
  void _adopt(Location location) {
    ref.read(locationsProvider.notifier).adoptCanonical(location);
    ref.read(currentLocationProvider.notifier).adoptCanonical(location);
  }

  AutoCancellationState _error(String message) => state = AutoCancellationState(
    phase: AutoCancellationPhase.error,
    message: message,
  );
  String _message(Object error) => error is ApiException
      ? error.message
      : error is UnsupportedAutoCancellationFormat
      ? error.toString()
      : 'Auto-cancel settings could not be saved.';
  bool _ambiguous(Object error) {
    if (error is! ApiException ||
        error.statusCode != null ||
        error.cause is! DioException) {
      return false;
    }
    return [
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
    ].contains((error.cause! as DioException).type);
  }
}
