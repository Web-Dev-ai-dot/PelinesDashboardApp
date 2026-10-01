import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../data/pickup_preferences_repository.dart';
import '../data/locations_repository.dart';
import '../models/auto_cancellation.dart';
import '../models/pickup_service_preferences.dart';
import '../models/location.dart';
import 'locations_providers.dart';
import 'service_preferences_write_lock.dart';

enum PickupPreferencesPhase {
  idle,
  submitting,
  reconciling,
  success,
  conflict,
  error,
}

class PickupPreferencesState {
  const PickupPreferencesState({
    this.phase = PickupPreferencesPhase.idle,
    this.message,
  });
  final PickupPreferencesPhase phase;
  final String? message;
  bool get isBusy =>
      phase == PickupPreferencesPhase.submitting ||
      phase == PickupPreferencesPhase.reconciling;
}

final pickupPreferencesRepositoryProvider =
    Provider<PickupPreferencesRepository>(
      (ref) =>
          ref.watch(locationsRepositoryProvider) as PickupPreferencesRepository,
    );
final pickupPreferencesProvider =
    NotifierProvider.family<
      PickupPreferencesController,
      PickupPreferencesState,
      PickupOrderKind
    >(PickupPreferencesController.new);

class PickupPreferencesController extends Notifier<PickupPreferencesState> {
  PickupPreferencesController(this.kind);
  final PickupOrderKind kind;
  @override
  PickupPreferencesState build() => const PickupPreferencesState();

  Future<PickupPreferencesState> save({
    required String locationId,
    required DateTime originalUpdatedAt,
    required PickupServicePreferences original,
    required PickupServicePreferences preferences,
  }) async {
    if (state.isBusy) return state;
    if (!_matches(locationId)) {
      return _error('The selected location changed. No change was sent.');
    }
    final validation = preferences.validate();
    if (validation != null) return _error(validation);
    final lock = ref.read(servicePreferencesWriteProvider.notifier);
    if (!lock.tryAcquire()) {
      return _error('Another service setting is being saved. Please wait.');
    }
    try {
      state = const PickupPreferencesState(
        phase: PickupPreferencesPhase.submitting,
      );
      try {
        await ref
            .read(pickupPreferencesRepositoryProvider)
            .savePickupPreferences(
              locationId: locationId,
              originalUpdatedAt: originalUpdatedAt,
              kind: kind,
              original: original,
              preferences: preferences,
              canWrite: () => _matches(locationId),
            );
      } on LocationSettingsConflict catch (conflict) {
        if (_matches(locationId)) _adopt(conflict.canonical);
        return state = const PickupPreferencesState(
          phase: PickupPreferencesPhase.conflict,
          message:
              'Store settings were changed elsewhere. Reload before saving.',
        );
      } catch (error) {
        if (!_ambiguous(error)) return _error(_message(error));
        return await _reconcile(
          locationId,
          original,
          preferences,
          ambiguous: true,
        );
      }
      return await _reconcile(
        locationId,
        original,
        preferences,
        ambiguous: false,
      );
    } finally {
      lock.release();
    }
  }

  Future<PickupPreferencesState> _reconcile(
    String id,
    PickupServicePreferences original,
    PickupServicePreferences preferences, {
    required bool ambiguous,
  }) async {
    state = const PickupPreferencesState(
      phase: PickupPreferencesPhase.reconciling,
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
      final effective = PickupServicePreferences.fromJson(
        canonical.servicePrefsJson,
        kind,
      );
      final changes = preferences.changesFrom(original, kind);
      final matches =
          effective.sameAs(preferences) &&
          changes.entries.every(
            (entry) => canonical.servicePrefsJson?[entry.key] == entry.value,
          );
      _adopt(canonical);
      if (!matches) {
        return _error(
          'The service preference change could not be confirmed. Reload before retrying.',
        );
      }
      return state = const PickupPreferencesState(
        phase: PickupPreferencesPhase.success,
        message: 'Service preferences saved.',
      );
    } catch (error) {
      return _error(
        ambiguous
            ? 'The service preference change could not be confirmed. Reload before retrying.'
            : _message(error),
      );
    }
  }

  bool _matches(String id) => ref.read(currentLocationProvider).value?.id == id;
  void _adopt(Location location) {
    ref.read(locationsProvider.notifier).adoptCanonical(location);
    ref.read(currentLocationProvider.notifier).adoptCanonical(location);
  }

  PickupPreferencesState _error(String message) =>
      state = PickupPreferencesState(
        phase: PickupPreferencesPhase.error,
        message: message,
      );
  String _message(Object error) => error is ApiException
      ? error.message
      : error is UnsupportedPickupPreferencesFormat
      ? error.toString()
      : 'Service preferences could not be saved.';
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
