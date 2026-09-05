import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../data/locations_repository.dart';
import '../models/business_hours.dart';
import '../models/location.dart';
import 'locations_providers.dart';

enum BusinessHoursSavePhase {
  idle,
  submitting,
  reconciling,
  success,
  conflict,
  error,
}

class BusinessHoursSaveState {
  const BusinessHoursSaveState({
    this.phase = BusinessHoursSavePhase.idle,
    this.message,
  });
  final BusinessHoursSavePhase phase;
  final String? message;
  bool get isBusy =>
      phase == BusinessHoursSavePhase.submitting ||
      phase == BusinessHoursSavePhase.reconciling;
}

final businessHoursSaveProvider =
    NotifierProvider<BusinessHoursController, BusinessHoursSaveState>(
      BusinessHoursController.new,
    );

class BusinessHoursController extends Notifier<BusinessHoursSaveState> {
  @override
  BusinessHoursSaveState build() => const BusinessHoursSaveState();

  Future<void> save({
    required String locationId,
    required DateTime originalUpdatedAt,
    required BusinessHoursSchedule schedule,
  }) async {
    if (state.isBusy) return;
    if (ref.read(currentLocationProvider).value?.id != locationId) {
      state = const BusinessHoursSaveState(
        phase: BusinessHoursSavePhase.error,
        message: 'The selected location changed. Reopen Business Hours before saving.',
      );
      return;
    }
    final LocationsRepository repository = ref.read(
      locationsRepositoryProvider,
    );
    state = const BusinessHoursSaveState(
      phase: BusinessHoursSavePhase.submitting,
    );
    try {
      await repository.saveBusinessHours(
        locationId: locationId,
        originalUpdatedAt: originalUpdatedAt,
        schedule: schedule,
      );
    } on LocationSettingsConflict catch (conflict) {
      _adopt(conflict.canonical);
      state = const BusinessHoursSaveState(
        phase: BusinessHoursSavePhase.conflict,
        message: 'Store settings were changed elsewhere.',
      );
      return;
    } catch (error) {
      if (!_ambiguous(error)) {
        state = BusinessHoursSaveState(
          phase: BusinessHoursSavePhase.error,
          message: error is ArgumentError
              ? error.message.toString()
              : _message(error),
        );
        return;
      }
      await _reconcile(repository, locationId, schedule, ambiguous: true);
      return;
    }
    await _reconcile(repository, locationId, schedule, ambiguous: false);
  }

  Future<void> _reconcile(
    LocationsRepository repository,
    String locationId,
    BusinessHoursSchedule expected, {
    required bool ambiguous,
  }) async {
    state = const BusinessHoursSaveState(
      phase: BusinessHoursSavePhase.reconciling,
    );
    try {
      final Location canonical = await repository.getLocation(locationId);
      if (ref.read(currentLocationProvider).value?.id != locationId) {
        state = const BusinessHoursSaveState(
          phase: BusinessHoursSavePhase.error,
          message: 'The selected location changed. No further change was sent.',
        );
        return;
      }
      _adopt(canonical);
      final Map<String, dynamic>? json = canonical.hoursJson;
      final bool matches =
          json != null && BusinessHoursSchedule.fromJson(json).sameAs(expected);
      state = BusinessHoursSaveState(
        phase: matches
            ? BusinessHoursSavePhase.success
            : BusinessHoursSavePhase.error,
        message: matches
            ? (ambiguous
                  ? 'Business hours were confirmed after reconnecting.'
                  : null)
            : (ambiguous
                  ? 'Business hours could not be confirmed. Reload and try again manually.'
                  : 'The server did not save the expected business hours.'),
      );
    } catch (error) {
      state = BusinessHoursSaveState(
        phase: BusinessHoursSavePhase.error,
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
      : 'Business hours could not be saved.';
}
