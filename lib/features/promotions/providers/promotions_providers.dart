import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../auth/providers/auth_providers.dart';
import '../../locations/providers/locations_providers.dart';
import '../data/promotions_repository.dart';
import '../models/discount.dart';

final promotionsRepositoryProvider = Provider<PromotionsRepository>((Ref ref) {
  return ApiPromotionsRepository(ref.watch(apiClientProvider));
});

final promotionsProvider =
    AsyncNotifierProvider<PromotionsController, List<Discount>>(
      PromotionsController.new,
    );

class PromotionsController extends AsyncNotifier<List<Discount>> {
  @override
  Future<List<Discount>> build() =>
      ref.watch(promotionsRepositoryProvider).getDiscounts();

  Future<void> refresh() async {
    state = const AsyncLoading<List<Discount>>();
    state = await AsyncValue.guard(
      ref.read(promotionsRepositoryProvider).getDiscounts,
    );
  }

  void adoptCanonical(List<Discount> discounts) {
    state = AsyncData<List<Discount>>(discounts);
  }
}

enum PromotionMutationPhase {
  idle,
  preflight,
  submitting,
  reconciling,
  success,
  conflict,
  error,
}

class PromotionMutationState {
  const PromotionMutationState({
    this.phase = PromotionMutationPhase.idle,
    this.message,
  });
  final PromotionMutationPhase phase;
  final String? message;
  bool get isBusy =>
      phase == PromotionMutationPhase.preflight ||
      phase == PromotionMutationPhase.submitting ||
      phase == PromotionMutationPhase.reconciling;
}

final promotionMutationProvider =
    NotifierProvider<PromotionMutationController, PromotionMutationState>(
      PromotionMutationController.new,
    );

class PromotionMutationController extends Notifier<PromotionMutationState> {
  @override
  PromotionMutationState build() => const PromotionMutationState();

  void reset() => state = const PromotionMutationState();

  Future<void> setActive({
    required String discountId,
    required String locationId,
    required DateTime originalUpdatedAt,
    required bool isActive,
  }) async {
    if (state.isBusy) return;
    if (!_sameLocation(locationId)) {
      _locationChanged();
      return;
    }
    final PromotionsRepository repository = ref.read(
      promotionsRepositoryProvider,
    );
    state = const PromotionMutationState(
      phase: PromotionMutationPhase.preflight,
    );
    late List<Discount> preflight;
    try {
      preflight = await repository.getDiscounts();
    } catch (error) {
      state = PromotionMutationState(
        phase: PromotionMutationPhase.error,
        message: _message(error, 'The promotion could not be checked.'),
      );
      return;
    }
    _adopt(preflight);
    if (!_sameLocation(locationId)) {
      _locationChanged();
      return;
    }
    final Discount? canonical = _find(preflight, discountId);
    if (canonical == null) {
      state = const PromotionMutationState(
        phase: PromotionMutationPhase.error,
        message: 'This promotion no longer exists.',
      );
      return;
    }
    if (canonical.locationId != locationId) {
      state = const PromotionMutationState(
        phase: PromotionMutationPhase.error,
        message: 'This promotion can no longer be managed for this location.',
      );
      return;
    }
    if (canonical.updatedAt != originalUpdatedAt.toUtc()) {
      state = const PromotionMutationState(
        phase: PromotionMutationPhase.conflict,
        message: 'This promotion was changed elsewhere.',
      );
      return;
    }

    state = const PromotionMutationState(
      phase: PromotionMutationPhase.submitting,
    );
    try {
      await repository.setActive(discountId, isActive);
    } catch (error) {
      if (!_ambiguous(error)) {
        state = PromotionMutationState(
          phase: PromotionMutationPhase.error,
          message: _message(error, 'The promotion could not be updated.'),
        );
        return;
      }
      await _reconcile(
        repository,
        discountId,
        locationId,
        isActive,
        ambiguous: true,
      );
      return;
    }
    await _reconcile(
      repository,
      discountId,
      locationId,
      isActive,
      ambiguous: false,
    );
  }

  Future<void> _reconcile(
    PromotionsRepository repository,
    String discountId,
    String locationId,
    bool requested, {
    required bool ambiguous,
  }) async {
    state = const PromotionMutationState(
      phase: PromotionMutationPhase.reconciling,
    );
    try {
      final List<Discount> canonical = await repository.getDiscounts();
      _adopt(canonical);
      if (!_sameLocation(locationId)) {
        _locationChanged();
        return;
      }
      final Discount? discount = _find(canonical, discountId);
      if (discount == null) {
        state = PromotionMutationState(
          phase: PromotionMutationPhase.error,
          message: ambiguous
              ? 'This promotion no longer exists, so the result is uncertain.'
              : 'This promotion no longer exists.',
        );
        return;
      }
      if (discount.locationId != locationId) {
        state = const PromotionMutationState(
          phase: PromotionMutationPhase.error,
          message: 'This promotion can no longer be managed for this location.',
        );
        return;
      }
      final bool matches = discount.isActive == requested;
      state = PromotionMutationState(
        phase: matches
            ? PromotionMutationPhase.success
            : PromotionMutationPhase.error,
        message: matches && ambiguous
            ? 'The promotion change was confirmed after reconnecting.'
            : matches
            ? null
            : ambiguous
            ? 'The change could not be confirmed. Reload and try again manually.'
            : 'The server did not save the expected active setting.',
      );
    } catch (error) {
      state = PromotionMutationState(
        phase: PromotionMutationPhase.error,
        message: ambiguous
            ? 'The result could not be confirmed. Reload before retrying.'
            : _message(error, 'The promotion could not be reloaded.'),
      );
    }
  }

  void _adopt(List<Discount> discounts) =>
      ref.read(promotionsProvider.notifier).adoptCanonical(discounts);

  bool _sameLocation(String id) =>
      ref.read(currentLocationProvider).value?.id == id;

  void _locationChanged() {
    state = const PromotionMutationState(
      phase: PromotionMutationPhase.error,
      message: 'The selected location changed. No further change was sent.',
    );
  }

  Discount? _find(List<Discount> values, String id) {
    for (final Discount value in values) {
      if (value.id == id) return value;
    }
    return null;
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

  String _message(Object error, String fallback) =>
      error is ApiException ? error.message : fallback;
}
