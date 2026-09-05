import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../data/locations_repository.dart';
import '../models/location.dart';
import '../models/temporary_closure.dart';
import 'locations_providers.dart';

enum ClosureSavePhase {
  idle,
  submitting,
  reconciling,
  success,
  conflict,
  error,
}

class ClosureSaveState {
  const ClosureSaveState({
    this.phase = ClosureSavePhase.idle,
    this.message,
    this.canonicalLocation,
  });
  final ClosureSavePhase phase;
  final String? message;
  final Location? canonicalLocation;
  bool get isBusy =>
      phase == ClosureSavePhase.submitting ||
      phase == ClosureSavePhase.reconciling;
}

final closureSaveProvider =
    NotifierProvider<ClosureSaveController, ClosureSaveState>(
      ClosureSaveController.new,
    );

class ClosureSaveController extends Notifier<ClosureSaveState> {
  @override
  ClosureSaveState build() => const ClosureSaveState();

  Future<void> save({
    required String locationId,
    required DateTime originalUpdatedAt,
    required TemporaryClosure closure,
    required bool isNew,
  }) async {
    if (state.isBusy) return;
    if (!_contextMatches(locationId)) {
      state = const ClosureSaveState(
        phase: ClosureSavePhase.error,
        message:
            'The selected location changed. Reopen the closure before saving.',
      );
      return;
    }
    final LocationsRepository repository = ref.read(
      locationsRepositoryProvider,
    );
    state = const ClosureSaveState(phase: ClosureSavePhase.submitting);
    try {
      await repository.saveClosure(
        locationId: locationId,
        originalUpdatedAt: originalUpdatedAt,
        closure: closure,
        isNew: isNew,
      );
    } on LocationSettingsConflict catch (conflict) {
      _adopt(conflict.canonical);
      state = ClosureSaveState(
        phase: ClosureSavePhase.conflict,
        message: 'Store settings were changed elsewhere.',
        canonicalLocation: conflict.canonical,
      );
      return;
    } on UnsupportedClosureFormat catch (error) {
      state = ClosureSaveState(
        phase: ClosureSavePhase.error,
        message: error.toString(),
      );
      return;
    } catch (error) {
      if (!_isAmbiguousNetworkError(error)) {
        state = ClosureSaveState(
          phase: ClosureSavePhase.error,
          message: _message(error),
        );
        return;
      }
      await _reconcile(repository, locationId, closure, ambiguous: true);
      return;
    }
    await _reconcile(repository, locationId, closure, ambiguous: false);
  }

  Future<void> _reconcile(
    LocationsRepository repository,
    String locationId,
    TemporaryClosure expected, {
    required bool ambiguous,
  }) async {
    state = const ClosureSaveState(phase: ClosureSavePhase.reconciling);
    try {
      final Location canonical = await repository.getLocation(locationId);
      if (!_contextMatches(locationId)) {
        state = const ClosureSaveState(
          phase: ClosureSavePhase.error,
          message: 'The selected location changed. No further change was sent.',
        );
        return;
      }
      _adopt(canonical);
      final TemporaryClosure? actual = _find(canonical, expected.id);
      if (actual != null && _sameKnownFields(actual, expected)) {
        state = ClosureSaveState(
          phase: ClosureSavePhase.success,
          message: ambiguous
              ? 'The closure was confirmed after reconnecting.'
              : null,
          canonicalLocation: canonical,
        );
      } else {
        state = ClosureSaveState(
          phase: ClosureSavePhase.error,
          message: ambiguous
              ? 'The closure could not be confirmed. Please reload and try again manually.'
              : 'The server did not save the expected closure.',
          canonicalLocation: canonical,
        );
      }
    } on UnsupportedClosureFormat catch (error) {
      state = ClosureSaveState(
        phase: ClosureSavePhase.error,
        message: error.toString(),
      );
    } catch (error) {
      state = ClosureSaveState(
        phase: ClosureSavePhase.error,
        message: ambiguous
            ? 'The result could not be confirmed. Reload before retrying.'
            : _message(error),
      );
    }
  }

  TemporaryClosure? _find(Location location, String id) {
    for (final TemporaryClosure closure in closuresFromExtras(
      location.hoursExtrasJson,
    )) {
      if (closure.id == id) return closure;
    }
    return null;
  }

  bool _sameKnownFields(TemporaryClosure a, TemporaryClosure b) =>
      a.id == b.id &&
      a.reason == b.reason &&
      a.start == b.start &&
      a.end == b.end &&
      a.notes == b.notes &&
      a.active == b.active;

  bool _contextMatches(String id) =>
      ref.read(currentLocationProvider).value?.id == id;

  void _adopt(Location location) {
    ref.read(locationsProvider.notifier).adoptCanonical(location);
    ref.read(currentLocationProvider.notifier).adoptCanonical(location);
  }

  bool _isAmbiguousNetworkError(Object error) {
    if (error is! ApiException || error.statusCode != null) return false;
    final Object? cause = error.cause;
    return cause is DioException &&
        (cause.type == DioExceptionType.connectionTimeout ||
            cause.type == DioExceptionType.sendTimeout ||
            cause.type == DioExceptionType.receiveTimeout ||
            cause.type == DioExceptionType.connectionError);
  }

  String _message(Object error) =>
      error is ApiException ? error.message : 'The closure could not be saved.';
}
