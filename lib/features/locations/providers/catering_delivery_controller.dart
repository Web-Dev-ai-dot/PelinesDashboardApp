import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../data/locations_repository.dart';
import '../models/catering_delivery.dart';
import '../models/location.dart';
import 'locations_providers.dart';

enum CateringDeliveryPhase {
  idle,
  submitting,
  reconciling,
  success,
  conflict,
  error,
}

class CateringDeliveryState {
  const CateringDeliveryState({
    this.phase = CateringDeliveryPhase.idle,
    this.message,
  });
  final CateringDeliveryPhase phase;
  final String? message;
  bool get isBusy =>
      phase == CateringDeliveryPhase.submitting ||
      phase == CateringDeliveryPhase.reconciling;
}

final cateringDeliveryProvider =
    NotifierProvider<CateringDeliveryController, CateringDeliveryState>(
      CateringDeliveryController.new,
    );

class CateringDeliveryController extends Notifier<CateringDeliveryState> {
  @override
  CateringDeliveryState build() => const CateringDeliveryState();

  Future<void> save({
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool originalEnabled,
    required bool enabled,
    required int originalFeeCents,
    required int feeCents,
    required int originalMinimumCents,
  }) async {
    if (state.isBusy) return;
    if (ref.read(currentLocationProvider).value?.id != locationId) {
      state = const CateringDeliveryState(
        phase: CateringDeliveryPhase.error,
        message: 'The selected location changed. Reopen Catering Delivery before saving.',
      );
      return;
    }
    final LocationsRepository repository = ref.read(
      locationsRepositoryProvider,
    );
    state = const CateringDeliveryState(
      phase: CateringDeliveryPhase.submitting,
    );
    try {
      await repository.saveCateringDeliverySettings(
        locationId: locationId,
        originalUpdatedAt: originalUpdatedAt,
        originalEnabled: originalEnabled,
        enabled: enabled,
        originalFeeCents: originalFeeCents,
        feeCents: feeCents,
      );
    } on LocationSettingsConflict catch (conflict) {
      _adopt(conflict.canonical);
      state = const CateringDeliveryState(
        phase: CateringDeliveryPhase.conflict,
        message: 'Store settings were changed elsewhere.',
      );
      return;
    } on UnsupportedCateringDeliveryFormat catch (error) {
      state = CateringDeliveryState(
        phase: CateringDeliveryPhase.error,
        message: error.toString(),
      );
      return;
    } catch (error) {
      if (!_ambiguous(error)) {
        state = CateringDeliveryState(
          phase: CateringDeliveryPhase.error,
          message: _message(error),
        );
        return;
      }
      await _reconcile(
        repository,
        locationId,
        originalEnabled: originalEnabled,
        enabled: enabled,
        originalFee: originalFeeCents,
        fee: feeCents,
        minimum: originalMinimumCents,
        ambiguous: true,
      );
      return;
    }
    await _reconcile(
      repository,
      locationId,
      originalEnabled: originalEnabled,
      enabled: enabled,
      originalFee: originalFeeCents,
      fee: feeCents,
      minimum: originalMinimumCents,
      ambiguous: false,
    );
  }

  Future<void> _reconcile(
    LocationsRepository repository,
    String id, {
    required bool originalEnabled,
    required bool enabled,
    required int originalFee,
    required int fee,
    required int minimum,
    required bool ambiguous,
  }) async {
    state = const CateringDeliveryState(
      phase: CateringDeliveryPhase.reconciling,
    );
    try {
      final Location canonical = await repository.getLocation(id);
      if (ref.read(currentLocationProvider).value?.id != id) {
        state = const CateringDeliveryState(
          phase: CateringDeliveryPhase.error,
          message: 'The selected location changed. No further change was sent.',
        );
        return;
      }
      final CateringDeliverySettings settings =
          CateringDeliverySettings.fromJson(canonical.cateringDeliveryJson);
      _adopt(canonical);
      final bool enabledMatches =
          settings.enabled == enabled &&
          (enabled == originalEnabled ||
              canonical.cateringDeliveryJson?['enabled'] == enabled);
      final bool feeMatches =
          fee == originalFee || canonical.deliveryFeeCents == fee;
      final bool matches =
          enabledMatches &&
          feeMatches &&
          canonical.deliveryMinimumCents == minimum;
      state = CateringDeliveryState(
        phase: matches
            ? CateringDeliveryPhase.success
            : CateringDeliveryPhase.error,
        message: matches
            ? (ambiguous
                  ? 'Catering delivery was confirmed after reconnecting.'
                  : null)
            : (ambiguous
                  ? 'The change could not be confirmed. Reload and try again manually.'
                  : 'The server did not save the expected catering delivery settings.'),
      );
    } catch (error) {
      state = CateringDeliveryState(
        phase: CateringDeliveryPhase.error,
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
      : 'Catering delivery could not be saved.';
}
