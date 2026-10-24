import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../auth/providers/auth_providers.dart';
import '../../locations/providers/locations_providers.dart';
import '../data/promotions_repository.dart';
import '../models/discount.dart';
import '../models/promotion_write.dart';

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

  Future<void> delete({
    required String discountId,
    required String locationId,
    required DateTime originalUpdatedAt,
    bool global = false,
  }) async {
    if (state.isBusy) return;
    if (!_deleteContext(locationId)) {
      _locationChanged();
      return;
    }
    final repository = ref.read(promotionsRepositoryProvider);
    state = const PromotionMutationState(
      phase: PromotionMutationPhase.preflight,
    );
    try {
      final values = await repository.getDiscounts();
      if (!ref.mounted) return;
      _adopt(values);
      if (!_deleteContext(locationId)) {
        _locationChanged();
        return;
      }
      final canonical = _find(values, discountId);
      if (canonical == null) {
        state = const PromotionMutationState(
          phase: PromotionMutationPhase.success,
          message: 'This promotion no longer exists.',
        );
        return;
      }
      if (canonical.locationId != (global ? null : locationId)) {
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
    } catch (error) {
      if (ref.mounted) {
        state = PromotionMutationState(
          phase: PromotionMutationPhase.error,
          message: _message(error, 'The promotion could not be checked.'),
        );
      }
      return;
    }
    state = const PromotionMutationState(
      phase: PromotionMutationPhase.submitting,
    );
    try {
      await repository.deletePromotion(discountId);
    } catch (error) {
      if (!ref.mounted) return;
      final reconcile =
          _ambiguous(error) ||
          (error is ApiException &&
              (error.statusCode == 404 || (error.statusCode ?? 0) >= 500));
      if (!reconcile) {
        state = PromotionMutationState(
          phase: PromotionMutationPhase.error,
          message: _message(error, 'The promotion could not be deleted.'),
        );
        return;
      }
    }
    if (!ref.mounted) return;
    state = const PromotionMutationState(
      phase: PromotionMutationPhase.reconciling,
    );
    try {
      final values = await repository.getDiscounts();
      if (!ref.mounted) return;
      _adopt(values);
      if (!_deleteContext(locationId)) {
        _locationChanged();
        return;
      }
      state = _find(values, discountId) == null
          ? const PromotionMutationState(phase: PromotionMutationPhase.success)
          : const PromotionMutationState(
              phase: PromotionMutationPhase.error,
              message: 'The deletion could not be confirmed. Refresh before trying again.',
            );
    } catch (_) {
      if (ref.mounted) {
        state = const PromotionMutationState(
          phase: PromotionMutationPhase.error,
          message: 'The deletion could not be confirmed. Refresh before trying again.',
        );
      }
    }
  }

  bool _deleteContext(String id) {
    final current = ref.read(currentLocationProvider);
    return !current.isLoading && !current.hasError && current.value?.id == id;
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

enum PromotionFormPhase {
  idle,
  preflight,
  submitting,
  reconciling,
  success,
  conflict,
  error,
}

class PromotionFormMutationState {
  const PromotionFormMutationState({
    this.phase = PromotionFormPhase.idle,
    this.message,
    this.resultId,
  });
  final PromotionFormPhase phase;
  final String? message;
  final String? resultId;
  bool get isBusy =>
      phase == PromotionFormPhase.preflight ||
      phase == PromotionFormPhase.submitting ||
      phase == PromotionFormPhase.reconciling;
}

final promotionFormMutationProvider =
    NotifierProvider<
      PromotionFormMutationController,
      PromotionFormMutationState
    >(PromotionFormMutationController.new);

class PromotionFormMutationController
    extends Notifier<PromotionFormMutationState> {
  @override
  PromotionFormMutationState build() => const PromotionFormMutationState();

  void reset() => state = const PromotionFormMutationState();

  Future<void> create({
    required String locationId,
    required Map<String, dynamic> body,
  }) async {
    if (state.isBusy) return;
    if (!_sameLocation(locationId)) return _locationChanged();
    final PromotionsRepository repository = ref.read(
      promotionsRepositoryProvider,
    );
    state = const PromotionFormMutationState(
      phase: PromotionFormPhase.submitting,
    );
    String? returnedId;
    try {
      returnedId = (await repository.createPromotion(body)).id;
    } catch (error) {
      if (!_ambiguousFormError(error)) {
        state = PromotionFormMutationState(
          phase: PromotionFormPhase.error,
          message: _formMessage(error, 'The promotion could not be created.'),
        );
        return;
      }
      await _reconcileCreate(repository, locationId, body);
      return;
    }
    await _reconcileCreate(
      repository,
      locationId,
      body,
      returnedId: returnedId,
    );
  }

  Future<void> edit({
    required String discountId,
    required String locationId,
    required DateTime originalUpdatedAt,
    required Map<String, dynamic> desired,
    bool global = false,
  }) async {
    if (state.isBusy) return;
    if (!_sameLocation(locationId)) return _locationChanged();
    final PromotionsRepository repository = ref.read(
      promotionsRepositoryProvider,
    );
    state = const PromotionFormMutationState(
      phase: PromotionFormPhase.preflight,
    );
    late List<Discount> values;
    try {
      values = await repository.getDiscounts();
    } catch (error) {
      return _error(error, 'The promotion could not be checked.');
    }
    _adoptForm(values);
    if (!_sameLocation(locationId)) return _locationChanged();
    final Discount? canonical = _findForm(values, discountId);
    if (canonical == null) {
      return _setFormError('This promotion no longer exists.');
    }
    if (canonical.locationId != (global ? null : locationId)) {
      return _setFormError(
        'This promotion can no longer be edited for this location.',
      );
    }
    if (canonical.updatedAt != originalUpdatedAt.toUtc()) {
      state = const PromotionFormMutationState(
        phase: PromotionFormPhase.conflict,
        message: 'This promotion was changed elsewhere.',
      );
      return;
    }
    final Map<String, dynamic> patch = partialPromotionPatch(
      discountEditableBody(canonical),
      {...desired}..remove('locationId'),
    );
    if (patch.isEmpty) {
      state = PromotionFormMutationState(
        phase: PromotionFormPhase.success,
        resultId: discountId,
      );
      return;
    }
    state = const PromotionFormMutationState(
      phase: PromotionFormPhase.submitting,
    );
    try {
      await repository.updatePromotion(discountId, patch);
    } catch (error) {
      if (!_ambiguousFormError(error)) {
        return _error(error, 'The promotion could not be saved.');
      }
      await _reconcileEdit(repository, discountId, locationId, patch, global);
      return;
    }
    await _reconcileEdit(repository, discountId, locationId, patch, global);
  }

  Future<void> _reconcileCreate(
    PromotionsRepository repository,
    String locationId,
    Map<String, dynamic> body, {
    String? returnedId,
  }) async {
    state = const PromotionFormMutationState(
      phase: PromotionFormPhase.reconciling,
    );
    try {
      final List<Discount> values = await repository.getDiscounts();
      _adoptForm(values);
      if (!_sameLocation(locationId)) return _locationChanged();
      final List<Discount> candidates = returnedId != null
          ? values.where((Discount d) => d.id == returnedId).toList()
          : values
                .where(
                  (Discount d) =>
                      d.code == body['code'] &&
                      d.locationId == body['locationId'],
                )
                .toList();
      if (candidates.length == 1 && _matchesForm(candidates.single, body)) {
        state = PromotionFormMutationState(
          phase: PromotionFormPhase.success,
          resultId: candidates.single.id,
        );
        return;
      }
      _setFormError(
        returnedId == null
            ? 'The create result is uncertain. Review promotions before retrying.'
            : 'The created promotion could not be confirmed.',
      );
    } catch (error) {
      _setFormError(
        'The create result could not be confirmed. Review promotions before retrying.',
      );
    }
  }

  Future<void> _reconcileEdit(
    PromotionsRepository repository,
    String id,
    String locationId,
    Map<String, dynamic> patch,
    bool global,
  ) async {
    state = const PromotionFormMutationState(
      phase: PromotionFormPhase.reconciling,
    );
    try {
      final List<Discount> values = await repository.getDiscounts();
      _adoptForm(values);
      if (!_sameLocation(locationId)) return _locationChanged();
      final Discount? canonical = _findForm(values, id);
      if (canonical == null) {
        return _setFormError('This promotion no longer exists.');
      }
      if (canonical.locationId != (global ? null : locationId)) {
        return _setFormError(
          'This promotion can no longer be edited for this location.',
        );
      }
      if (!_matchesForm(canonical, patch)) {
        return _setFormError(
          'The change could not be confirmed. Reload and try again manually.',
        );
      }
      state = PromotionFormMutationState(
        phase: PromotionFormPhase.success,
        resultId: id,
      );
    } catch (error) {
      _setFormError(
        'The save result could not be confirmed. Reload before retrying.',
      );
    }
  }

  bool _matchesForm(Discount discount, Map<String, dynamic> expected) {
    final Map<String, dynamic> actual = <String, dynamic>{
      ...discountEditableBody(discount),
      'locationId': discount.locationId,
    };
    for (final MapEntry<String, dynamic> entry in expected.entries) {
      final Object? value = actual[entry.key];
      if ((entry.key == 'startsAt' || entry.key == 'endsAt') &&
          value != null &&
          entry.value != null) {
        if (DateTime.parse(value as String).toUtc() !=
            DateTime.parse(entry.value as String).toUtc()) {
          return false;
        }
      } else if (value != entry.value) {
        return false;
      }
    }
    return true;
  }

  void _adoptForm(List<Discount> values) =>
      ref.read(promotionsProvider.notifier).adoptCanonical(values);
  bool _sameLocation(String id) =>
      ref.read(currentLocationProvider).value?.id == id;
  Discount? _findForm(List<Discount> values, String id) {
    for (final Discount value in values) {
      if (value.id == id) return value;
    }
    return null;
  }

  void _locationChanged() => _setFormError(
    'The selected location changed. Reopen this form before saving.',
  );
  void _setFormError(String message) => state = PromotionFormMutationState(
    phase: PromotionFormPhase.error,
    message: message,
  );
  void _error(Object error, String fallback) =>
      _setFormError(_formMessage(error, fallback));
  String _formMessage(Object error, String fallback) =>
      error is ApiException ? error.message : fallback;
  bool _ambiguousFormError(Object error) {
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
}
