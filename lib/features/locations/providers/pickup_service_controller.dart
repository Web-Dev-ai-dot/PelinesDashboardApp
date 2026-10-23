import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../data/locations_repository.dart';
import '../data/pickup_service_repository.dart';
import '../models/auto_cancellation.dart';
import '../models/location.dart';
import '../models/pickup_service_settings.dart';
import 'locations_providers.dart';
import 'pickup_preferences_controller.dart'
    show PickupPreferencesPhase, PickupPreferencesState;
import 'service_preferences_write_lock.dart';

final pickupServiceProvider =
    NotifierProvider.family<
      PickupServiceController,
      PickupPreferencesState,
      PickupOrderKind
    >(PickupServiceController.new);

class PickupServiceController extends Notifier<PickupPreferencesState> {
  PickupServiceController(this.kind);
  final PickupOrderKind kind;
  @override
  PickupPreferencesState build() => const PickupPreferencesState();
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

  Future<PickupPreferencesState> save({
    required String locationId,
    required PickupServiceSettings original,
    required PickupServiceSettings settings,
  }) async {
    if (state.isBusy) return state;
    if (!_matches(locationId)) {
      return _error('The selected location changed. No change was sent.');
    }
    final validation = settings.validate(kind);
    if (validation != null) return _error(validation);
    final lock = ref.read(servicePreferencesWriteProvider.notifier);
    if (!lock.tryAcquire()) {
      return _error('Another service setting is being saved. Please wait.');
    }
    final repository = ref.read(locationsRepositoryProvider);
    var ambiguous = false;
    try {
      state = const PickupPreferencesState(
        phase: PickupPreferencesPhase.submitting,
      );
      try {
        await (repository as PickupServiceRepository).savePickupService(
          locationId: locationId,
          kind: kind,
          original: original,
          settings: settings,
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
        ambiguous =
            error is ApiException &&
            error.statusCode == null &&
            error.cause is DioException &&
            [
              DioExceptionType.connectionTimeout,
              DioExceptionType.sendTimeout,
              DioExceptionType.receiveTimeout,
              DioExceptionType.connectionError,
            ].contains((error.cause as DioException).type);
        if (!ambiguous) {
          return _error(
            error is ApiException
                ? error.message
                : 'Service preferences could not be saved.',
          );
        }
      }
      state = const PickupPreferencesState(
        phase: PickupPreferencesPhase.reconciling,
      );
      try {
        final canonical = await repository.getLocation(locationId);
        if (!_matches(locationId)) {
          return _error(
            'The selected location changed. No further change was sent.',
          );
        }
        final matches =
            PickupServiceSettings.fromJson(
              canonical.servicePrefsJson,
              kind,
            ).sameAs(settings) &&
            settings
                .changesFrom(original, kind)
                .entries
                .every(
                  (entry) =>
                      canonical.servicePrefsJson?[entry.key] == entry.value,
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
      } catch (_) {
        return _error(
          'The service preference change could not be confirmed. Reload before retrying.',
        );
      }
    } finally {
      lock.release();
    }
  }
}
