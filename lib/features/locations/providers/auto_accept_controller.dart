import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../data/locations_repository.dart';
import '../models/auto_accept.dart';
import '../models/location.dart';
import 'locations_providers.dart';
import 'service_preferences_write_lock.dart';

enum AutoAcceptPhase { idle, submitting, reconciling, success, conflict, error }

class AutoAcceptState {
  const AutoAcceptState({this.phase = AutoAcceptPhase.idle, this.message});
  final AutoAcceptPhase phase;
  final String? message;
  bool get isBusy =>
      phase == AutoAcceptPhase.submitting ||
      phase == AutoAcceptPhase.reconciling;
}

final autoAcceptProvider =
    NotifierProvider<AutoAcceptController, AutoAcceptState>(
      AutoAcceptController.new,
    );

class AutoAcceptController extends Notifier<AutoAcceptState> {
  @override
  AutoAcceptState build() => const AutoAcceptState();

  Future<void> save({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool originalRegular,
    required bool regular,
    required bool originalCatering,
    required bool catering,
  }) async {
    if (state.isBusy) return;
    final lock = ref.read(servicePreferencesWriteProvider.notifier);
    if (!lock.tryAcquire()) {
      state = const AutoAcceptState(
        phase: AutoAcceptPhase.error,
        message: 'Another service setting is being saved. Please wait.',
      );
      return;
    }
    try {
      await _save(
        locationId: locationId,
        originalUpdatedAt: originalUpdatedAt,
        originalRegular: originalRegular,
        regular: regular,
        originalCatering: originalCatering,
        catering: catering,
      );
    } finally {
      lock.release();
    }
  }

  Future<void> _save({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool originalRegular,
    required bool regular,
    required bool originalCatering,
    required bool catering,
  }) async {
    if (state.isBusy) return;
    if (ref.read(currentLocationProvider).value?.id != locationId) {
      state = const AutoAcceptState(
        phase: AutoAcceptPhase.error,
        message: 'The selected location changed. Reopen Auto-Accept Orders before saving.',
      );
      return;
    }
    final LocationsRepository repository = ref.read(
      locationsRepositoryProvider,
    );
    state = const AutoAcceptState(phase: AutoAcceptPhase.submitting);
    try {
      await repository.saveAutoAcceptSettings(
        locationId: locationId,
        originalUpdatedAt: originalUpdatedAt,
        originalRegular: originalRegular,
        regular: regular,
        originalCatering: originalCatering,
        catering: catering,
      );
    } on LocationSettingsConflict catch (conflict) {
      _adopt(conflict.canonical);
      state = const AutoAcceptState(
        phase: AutoAcceptPhase.conflict,
        message: 'Store settings were changed elsewhere.',
      );
      return;
    } on UnsupportedAutoAcceptFormat catch (error) {
      state = AutoAcceptState(
        phase: AutoAcceptPhase.error,
        message: error.toString(),
      );
      return;
    } catch (error) {
      if (!_ambiguous(error)) {
        state = AutoAcceptState(
          phase: AutoAcceptPhase.error,
          message: _message(error),
        );
        return;
      }
      await _reconcile(
        repository,
        locationId,
        originalRegular: originalRegular,
        regular: regular,
        originalCatering: originalCatering,
        catering: catering,
        ambiguous: true,
      );
      return;
    }
    await _reconcile(
      repository,
      locationId,
      originalRegular: originalRegular,
      regular: regular,
      originalCatering: originalCatering,
      catering: catering,
      ambiguous: false,
    );
  }

  Future<void> _reconcile(
    LocationsRepository repository,
    String id, {
    required bool originalRegular,
    required bool regular,
    required bool originalCatering,
    required bool catering,
    required bool ambiguous,
  }) async {
    state = const AutoAcceptState(phase: AutoAcceptPhase.reconciling);
    try {
      final Location canonical = await repository.getLocation(id);
      if (ref.read(currentLocationProvider).value?.id != id) {
        state = const AutoAcceptState(
          phase: AutoAcceptPhase.error,
          message: 'The selected location changed. No further change was sent.',
        );
        return;
      }
      final AutoAcceptSettings settings = AutoAcceptSettings.fromJson(
        canonical.servicePrefsJson,
      );
      final bool regularMatches =
          regular == originalRegular ||
          (settings.regular == regular &&
              canonical.servicePrefsJson?['autoAcceptRegular'] == regular);
      final bool cateringMatches =
          catering == originalCatering ||
          (settings.catering == catering &&
              canonical.servicePrefsJson?['autoAcceptCatering'] == catering);
      _adopt(canonical);
      final bool matches = regularMatches && cateringMatches;
      state = AutoAcceptState(
        phase: matches ? AutoAcceptPhase.success : AutoAcceptPhase.error,
        message: matches
            ? (ambiguous
                  ? 'Auto-accept settings were confirmed after reconnecting.'
                  : null)
            : (ambiguous
                  ? 'The change could not be confirmed. Reload and try again manually.'
                  : 'The server did not save the expected auto-accept settings.'),
      );
    } catch (error) {
      state = AutoAcceptState(
        phase: AutoAcceptPhase.error,
        message: ambiguous
            ? 'The result could not be confirmed. Reload before retrying.'
            : _message(error),
      );
    }
  }

  void _adopt(Location location) {
    ref.read(locationsProvider.notifier).adoptCanonical(location);
    ref.read(currentLocationProvider.notifier).adoptCanonical(location);
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

  String _message(Object error) => error is ApiException
      ? error.message
      : 'Auto-accept settings could not be saved.';
}
