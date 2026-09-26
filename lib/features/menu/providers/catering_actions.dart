import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../../core/api/api_exception.dart';
import '../../locations/providers/locations_providers.dart';
import '../data/menu_repository.dart';
import '../models/menu_models.dart';
import 'menu_providers.dart';

enum CateringEntity { product, category, group, option }

final cateringDeleteProvider = Provider<CateringDeleteApi>(
  (ref) => CateringDeleteApi(ref.watch(apiClientProvider).dio),
);

class CateringDeleteApi {
  CateringDeleteApi(this.dio);
  final Dio dio;
  Future<void> delete(CateringEntity entity, String id) async {
    final resource = switch (entity) {
      CateringEntity.product => 'products',
      CateringEntity.category => 'categories',
      CateringEntity.group => 'modifier-groups',
      CateringEntity.option => 'modifier-options',
    };
    try {
      await dio.delete<void>('$resource/${Uri.encodeComponent(id)}');
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return;
      throw ApiException(
        message: 'Deletion was not confirmed. Refresh before retrying.',
        cause: error,
        statusCode: error.response?.statusCode,
      );
    }
  }
}

/// Validate the live location and category before any menu action.
Future<void> validateCateringContext(
  WidgetRef ref,
  CategoryQuery query,
  String categoryId,
) async {
  final current = await ref.read(currentLocationProvider.future);
  if (current?.id != query.locationId || current?.slug != query.locationSlug) {
    throw const MenuContextChangedException();
  }
  final categories = await ref
      .read(menuRepositoryProvider)
      .getCategories(locationSlug: query.locationSlug, kind: query.kind);
  if (!categories.any(
    (c) =>
        c.id == categoryId &&
        c.locationId == query.locationId &&
        c.kind == query.kind,
  )) {
    throw const MenuContextChangedException();
  }
}

class CateringCopyException implements Exception {
  CateringCopyException(this.createdId);
  final String? createdId;
  @override
  String toString() => createdId == null
      ? 'Copy was not confirmed. Refresh before trying again to avoid duplicates.'
      : 'Copy $createdId may be incomplete. Review its modifiers before using it. No automatic retry was made.';
}

/// Web Duplicate semantics: Copy suffix, base fields/photo/serves and add-ons.
/// Never silently discard add-ons when their initial read fails.
Future<MenuProduct> duplicateCateringProduct(
  MenuRepository repository,
  MenuProduct source, {
  MenuKind kind = MenuKind.catering,
}) async {
  final groups = await repository.getModifierGroups(source.id);
  if (groups.any((g) => !g.isFullyLoaded || g.productId != source.id)) {
    throw const FormatException('Modifier data is incomplete.');
  }
  final name = '${source.name} (Copy)';
  if (name.length > 120) {
    throw const FormatException('The copy name exceeds 120 characters.');
  }
  MenuProduct? created;
  try {
    created = await repository.createProduct(
      ProductWriteInput(
        categoryId: source.categoryId,
        name: name,
        priceCents: source.priceCents,
        isAvailable: source.isAvailable,
        sortOrder: 0,
        description: source.description ?? '',
        // Preserve Catering copy semantics; Regular web also copies these fields.
        subcategory: kind == MenuKind.store ? source.subcategory ?? '' : '',
        disclaimer: kind == MenuKind.store ? source.disclaimer ?? '' : '',
        servesCount: source.servesCount,
        imageUrl: source.imageUrl,
      ),
    );
    final ordered = [...groups]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (var i = 0; i < ordered.length; i++) {
      final g = ordered[i];
      final copy = await repository.createModifierGroup(
        created.id,
        ModifierGroupWriteInput(
          name: g.name,
          isRequired: g.isRequired!,
          minSelect: g.minSelect!,
          maxSelect: g.maxSelect!,
          sortOrder: i,
        ),
      );
      final options = [...g.options]
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      for (var j = 0; j < options.length; j++) {
        final option = options[j];
        await repository.createModifierOption(
          copy.id,
          ModifierOptionWriteInput(
            name: option.name,
            priceDeltaCents: option.priceDeltaCents,
            isDefault: false,
            sortOrder: j,
          ),
        );
      }
    }
    return await repository.getProduct(created.id);
  } on Object {
    throw CateringCopyException(created?.id);
  }
}
