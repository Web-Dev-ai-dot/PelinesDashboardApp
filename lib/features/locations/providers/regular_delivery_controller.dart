import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../data/locations_repository.dart';
import '../models/location.dart';
import '../models/regular_delivery.dart';
import 'locations_providers.dart';

enum RegularDeliveryPhase {
  idle,
  submitting,
  reconciling,
  success,
  conflict,
  error,
}

class RegularDeliveryState {
  const RegularDeliveryState({
    this.phase = RegularDeliveryPhase.idle,
    this.message,
  });
  final RegularDeliveryPhase phase;
  final String? message;
  bool get isBusy =>
      phase == RegularDeliveryPhase.submitting ||
      phase == RegularDeliveryPhase.reconciling;
}

final regularDeliveryProvider =
    NotifierProvider<RegularDeliveryController, RegularDeliveryState>(
      RegularDeliveryController.new,
    );

class RegularDeliveryController extends Notifier<RegularDeliveryState> {
  @override
  RegularDeliveryState build() => const RegularDeliveryState();

  Future<void> save({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool enabled,
    required int feeCents,
  }) async {
    if (state.isBusy) return;
    if (ref.read(currentLocationProvider).value?.id != locationId) {
      state = const RegularDeliveryState(
        phase: RegularDeliveryPhase.error,
        message: 'The selected location changed. Reopen Regular Delivery before saving.',
      );
      return;
    }
    final LocationsRepository repository = ref.read(
      locationsRepositoryProvider,
    );
    state = const RegularDeliveryState(phase: RegularDeliveryPhase.submitting);
    try {
      await repository.saveRegularDeliverySettings(
        locationId: locationId,
        originalUpdatedAt: originalUpdatedAt,
        enabled: enabled,
        feeCents: feeCents,
      );
    } on LocationSettingsConflict catch (conflict) {
      _adopt(conflict.canonical);
      state = const RegularDeliveryState(
        phase: RegularDeliveryPhase.conflict,
        message: 'Store settings were changed elsewhere.',
      );
      return;
    } on UnsupportedRegularDeliveryFormat catch (error) {
      state = RegularDeliveryState(
        phase: RegularDeliveryPhase.error,
        message: error.toString(),
      );
      return;
    } catch (error) {
      if (!_ambiguous(error)) {
        state = RegularDeliveryState(
          phase: RegularDeliveryPhase.error,
          message: _message(error),
        );
        return;
      }
      await _reconcile(
        repository,
        locationId,
        enabled,
        feeCents,
        ambiguous: true,
      );
      return;
    }
    await _reconcile(
      repository,
      locationId,
      enabled,
      feeCents,
      ambiguous: false,
    );
  }

  Future<void> _reconcile(
    LocationsRepository repository,
    String id,
    bool enabled,
    int fee, {
    required bool ambiguous,
  }) async {
    state = const RegularDeliveryState(phase: RegularDeliveryPhase.reconciling);
    try {
      final Location canonical = await repository.getLocation(id);
      if (ref.read(currentLocationProvider).value?.id != id) {
        state = const RegularDeliveryState(
          phase: RegularDeliveryPhase.error,
          message: 'The selected location changed. No further change was sent.',
        );
        return;
      }
      final RegularDeliverySettings settings = RegularDeliverySettings.fromJson(
        canonical.regularDeliveryJson,
      );
      _adopt(canonical);
      final bool matches =
          settings.enabled == enabled && settings.feeCents == fee;
      state = RegularDeliveryState(
        phase: matches
            ? RegularDeliveryPhase.success
            : RegularDeliveryPhase.error,
        message: matches
            ? (ambiguous
                  ? 'Regular delivery was confirmed after reconnecting.'
                  : null)
            : (ambiguous
                  ? 'The change could not be confirmed. Reload and try again manually.'
                  : 'The server did not save the expected delivery settings.'),
      );
    } catch (error) {
      state = RegularDeliveryState(
        phase: RegularDeliveryPhase.error,
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
      : 'Regular delivery could not be saved.';
}
