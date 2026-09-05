import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../data/locations_repository.dart';
import '../models/location.dart';
import 'locations_providers.dart';

enum StoreOperationPhase { idle, submitting, reconciling, success, error }

class StoreOperationState {
  const StoreOperationState({
    this.phase = StoreOperationPhase.idle,
    this.message,
    this.canonicalLocation,
  });

  final StoreOperationPhase phase;
  final String? message;
  final Location? canonicalLocation;

  bool get isBusy =>
      phase == StoreOperationPhase.submitting ||
      phase == StoreOperationPhase.reconciling;
}

final storeOperationsProvider =
    NotifierProvider<StoreOperationsController, StoreOperationState>(
      StoreOperationsController.new,
    );

class StoreOperationsController extends Notifier<StoreOperationState> {
  @override
  StoreOperationState build() => const StoreOperationState();

  Future<void> setAcceptingOrders({
    required String locationId,
    required bool observedValue,
    required bool requestedValue,
  }) async {
    if (state.isBusy) return;
    final Location? selected = ref.read(currentLocationProvider).value;
    if (selected?.id != locationId) {
      state = const StoreOperationState(
        phase: StoreOperationPhase.error,
        message: 'The selected location changed. Please try again.',
      );
      return;
    }

    final LocationsRepository repository = ref.read(
      locationsRepositoryProvider,
    );
    state = const StoreOperationState(phase: StoreOperationPhase.reconciling);
    late Location before;
    try {
      before = await repository.getLocation(locationId);
    } catch (error) {
      state = StoreOperationState(
        phase: StoreOperationPhase.error,
        message: _message(error),
      );
      return;
    }

    if (!_contextStillMatches(locationId)) {
      state = const StoreOperationState(
        phase: StoreOperationPhase.error,
        message: 'The selected location changed. No change was sent.',
      );
      return;
    }
    _adopt(before);
    if (before.isAcceptingOrders == requestedValue) {
      state = StoreOperationState(
        phase: StoreOperationPhase.success,
        message: 'The server already had this setting.',
        canonicalLocation: before,
      );
      return;
    }
    if (before.isAcceptingOrders != observedValue) {
      state = StoreOperationState(
        phase: StoreOperationPhase.error,
        message: 'Online ordering changed on another device. Review the current setting and try again.',
        canonicalLocation: before,
      );
      return;
    }

    state = StoreOperationState(
      phase: StoreOperationPhase.submitting,
      canonicalLocation: before,
    );
    try {
      await repository.setAcceptingOrders(locationId, requestedValue);
    } catch (error) {
      if (!_isAmbiguousNetworkError(error)) {
        state = StoreOperationState(
          phase: StoreOperationPhase.error,
          message: _message(error),
          canonicalLocation: before,
        );
        return;
      }
      await _reconcile(
        repository: repository,
        locationId: locationId,
        requestedValue: requestedValue,
        previous: before,
        ambiguousFailure: true,
      );
      return;
    }

    await _reconcile(
      repository: repository,
      locationId: locationId,
      requestedValue: requestedValue,
      previous: before,
      ambiguousFailure: false,
    );
  }

  Future<void> _reconcile({
    required LocationsRepository repository,
    required String locationId,
    required bool requestedValue,
    required Location previous,
    required bool ambiguousFailure,
  }) async {
    state = StoreOperationState(
      phase: StoreOperationPhase.reconciling,
      canonicalLocation: previous,
    );
    try {
      final Location canonical = await repository.getLocation(locationId);
      if (!_contextStillMatches(locationId)) {
        state = const StoreOperationState(
          phase: StoreOperationPhase.error,
          message: 'The selected location changed. Refresh before making another change.',
        );
        return;
      }
      _adopt(canonical);
      if (canonical.isAcceptingOrders == requestedValue) {
        state = StoreOperationState(
          phase: StoreOperationPhase.success,
          message: ambiguousFailure
              ? 'The change was confirmed after reconnecting.'
              : null,
          canonicalLocation: canonical,
        );
      } else {
        state = StoreOperationState(
          phase: StoreOperationPhase.error,
          message: ambiguousFailure
              ? 'The change could not be confirmed. Please try again manually.'
              : 'The server did not save the requested setting.',
          canonicalLocation: canonical,
        );
      }
    } catch (error) {
      state = StoreOperationState(
        phase: StoreOperationPhase.error,
        message: ambiguousFailure
            ? 'The result could not be confirmed. Check the connection before retrying.'
            : _message(error),
        canonicalLocation: previous,
      );
    }
  }

  bool _contextStillMatches(String locationId) =>
      ref.read(currentLocationProvider).value?.id == locationId;

  void _adopt(Location location) {
    ref.read(locationsProvider.notifier).adoptCanonical(location);
    ref.read(currentLocationProvider.notifier).adoptCanonical(location);
  }

  bool _isAmbiguousNetworkError(Object error) {
    if (error is! ApiException || error.statusCode != null) return false;
    final Object? cause = error.cause;
    if (cause is! DioException) return false;
    return cause.type == DioExceptionType.connectionTimeout ||
        cause.type == DioExceptionType.sendTimeout ||
        cause.type == DioExceptionType.receiveTimeout ||
        cause.type == DioExceptionType.connectionError;
  }

  String _message(Object error) => error is ApiException
      ? error.message
      : 'The location could not be updated.';
}
