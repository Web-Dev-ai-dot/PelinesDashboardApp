import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../locations/providers/locations_providers.dart';
import '../data/menu_repository.dart';
import '../models/menu_models.dart';
import 'menu_providers.dart';

typedef ModifierContext = ({
  String locationId,
  String locationSlug,
  MenuKind kind,
  String categoryId,
  String productId,
});

final modifierGroupsProvider = FutureProvider.autoDispose
    .family<List<MenuModifierGroup>, ModifierContext>((ref, context) async {
      await _validateModifierContext(ref, context);
      final groups = await ref
          .watch(menuRepositoryProvider)
          .getModifierGroups(context.productId);
      if (groups.any(
        (group) => group.productId != context.productId || !group.isFullyLoaded,
      )) {
        throw const MenuContextChangedException();
      }
      return groups;
    });

enum ModifierMutationPhase { idle, submitting, reconciling, success, error }

class ModifierMutationState {
  const ModifierMutationState({
    this.phase = ModifierMutationPhase.idle,
    this.message,
  });
  final ModifierMutationPhase phase;
  final String? message;
  bool get isBusy =>
      phase == ModifierMutationPhase.submitting ||
      phase == ModifierMutationPhase.reconciling;
}

final modifierMutationProvider = NotifierProvider.autoDispose
    .family<ModifierMutationController, ModifierMutationState, ModifierContext>(
      ModifierMutationController.new,
    );

class ModifierMutationController extends Notifier<ModifierMutationState> {
  ModifierMutationController(this.context);
  final ModifierContext context;

  @override
  ModifierMutationState build() => const ModifierMutationState();

  Future<bool> saveGroup(ModifierGroupWriteInput input, {String? groupId}) =>
      _save(
        create: groupId == null,
        write: () => groupId == null
            ? ref
                  .read(menuRepositoryProvider)
                  .createModifierGroup(context.productId, input)
            : ref
                  .read(menuRepositoryProvider)
                  .updateModifierGroup(groupId, input),
        find: (groups, responseId) => groups
            .where((group) => group.id == (groupId ?? responseId))
            .firstOrNull,
        matches: (group) =>
            group.name == input.name &&
            group.isRequired == input.isRequired &&
            group.minSelect == input.minSelect &&
            group.maxSelect == input.maxSelect &&
            group.sortOrder == input.sortOrder,
        existingGroupId: groupId,
        successMessage: groupId == null
            ? 'Modifier group created.'
            : 'Modifier group updated.',
      );

  Future<bool> saveOption(
    ModifierOptionWriteInput input, {
    required String groupId,
    String? optionId,
  }) => _save(
    create: optionId == null,
    write: () => optionId == null
        ? ref.read(menuRepositoryProvider).createModifierOption(groupId, input)
        : ref
              .read(menuRepositoryProvider)
              .updateModifierOption(optionId, input),
    find: (groups, responseId) {
      final group = groups.where((value) => value.id == groupId).firstOrNull;
      return group?.options
          .where((option) => option.id == (optionId ?? responseId))
          .firstOrNull;
    },
    matches: (option) =>
        option.groupId == groupId &&
        option.name == input.name &&
        option.priceDeltaCents == input.priceDeltaCents &&
        option.isDefault == input.isDefault &&
        option.sortOrder == input.sortOrder,
    existingGroupId: groupId,
    existingOptionId: optionId,
    successMessage: optionId == null
        ? 'Modifier option created.'
        : 'Modifier option updated.',
  );

  Future<bool> _save<T>({
    required bool create,
    required Future<T> Function() write,
    required T? Function(List<MenuModifierGroup>, String) find,
    required bool Function(T) matches,
    required String? existingGroupId,
    String? existingOptionId,
    required String successMessage,
  }) async {
    if (state.isBusy) return false;
    state = const ModifierMutationState(
      phase: ModifierMutationPhase.submitting,
    );
    try {
      final groups = await _validateModifierContext(ref, context);
      if (existingGroupId != null) {
        final group = groups.where((g) => g.id == existingGroupId).firstOrNull;
        if (group == null || group.productId != context.productId) {
          throw const MenuContextChangedException();
        }
        if (existingOptionId != null &&
            !group.options.any(
              (option) =>
                  option.id == existingOptionId &&
                  option.groupId == existingGroupId,
            )) {
          throw const MenuContextChangedException();
        }
      }
    } on ApiException catch (error) {
      state = ModifierMutationState(
        phase: ModifierMutationPhase.error,
        message: error.message,
      );
      return false;
    } on Object catch (error) {
      state = ModifierMutationState(
        phase: ModifierMutationPhase.error,
        message: error.toString(),
      );
      return false;
    }

    state = const ModifierMutationState(
      phase: ModifierMutationPhase.submitting,
    );
    try {
      final T provisional = await write();
      final String responseId = switch (provisional) {
        MenuModifierGroup value => value.id,
        MenuModifierOption value => value.id,
        _ => '',
      };
      return await _reconcile(responseId, find, matches, successMessage);
    } on ApiException catch (error) {
      if (_ambiguous(error) && !create) {
        return _reconcile(
          existingOptionId ?? existingGroupId ?? '',
          find,
          matches,
          successMessage,
          failurePrefix: error.message,
        );
      }
      state = ModifierMutationState(
        phase: ModifierMutationPhase.error,
        message: _ambiguous(error) && create
            ? '${error.message} Refresh Product Detail before trying again to avoid a duplicate.'
            : error.message,
      );
      if (_ambiguous(error) && create) _refresh();
      return false;
    } on Object {
      state = const ModifierMutationState(
        phase: ModifierMutationPhase.error,
        message: 'The modifier could not be saved.',
      );
      return false;
    }
  }

  Future<bool> _reconcile<T>(
    String responseId,
    T? Function(List<MenuModifierGroup>, String) find,
    bool Function(T) matches,
    String successMessage, {
    String? failurePrefix,
  }) async {
    state = const ModifierMutationState(
      phase: ModifierMutationPhase.reconciling,
    );
    try {
      final groups = await ref
          .read(menuRepositoryProvider)
          .getModifierGroups(context.productId);
      final T? canonical = find(groups, responseId);
      if (canonical != null && matches(canonical)) {
        state = ModifierMutationState(
          phase: ModifierMutationPhase.success,
          message: successMessage,
        );
        _refresh();
        return true;
      }
      state = ModifierMutationState(
        phase: ModifierMutationPhase.error,
        message:
            '${failurePrefix ?? 'The saved modifier differs from the submitted values.'} Review it before retrying.',
      );
    } on Object {
      state = ModifierMutationState(
        phase: ModifierMutationPhase.error,
        message:
            '${failurePrefix ?? 'The modifier was submitted.'} Its current state could not be verified.',
      );
    }
    return false;
  }

  bool _ambiguous(ApiException error) =>
      error.cause is DioException &&
      const <DioExceptionType>{
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      }.contains((error.cause! as DioException).type);

  void _refresh() {
    ref.invalidate(modifierGroupsProvider(context));
    ref.invalidate(
      menuProductDetailProvider((
        locationId: context.locationId,
        categoryId: context.categoryId,
        productId: context.productId,
      )),
    );
  }
}

Future<List<MenuModifierGroup>> _validateModifierContext(
  Ref ref,
  ModifierContext context,
) async {
  final location = await ref.read(currentLocationProvider.future);
  if (location == null ||
      location.id != context.locationId ||
      location.slug != context.locationSlug) {
    throw const MenuContextChangedException();
  }
  final category = await ref
      .read(menuRepositoryProvider)
      .getCategory(context.categoryId);
  if (category.locationId != context.locationId ||
      category.kind != context.kind) {
    throw const MenuContextChangedException();
  }
  final product = await ref
      .read(menuRepositoryProvider)
      .getProduct(context.productId);
  if (product.categoryId != context.categoryId) {
    throw const MenuContextChangedException();
  }
  final groups = await ref
      .read(menuRepositoryProvider)
      .getModifierGroups(context.productId);
  if (groups.any(
    (group) => group.productId != context.productId || !group.isFullyLoaded,
  )) {
    throw const MenuContextChangedException();
  }
  return groups;
}
