import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../auth/providers/auth_providers.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../data/menu_repository.dart';
import '../models/menu_models.dart';

final menuRepositoryProvider = Provider<MenuRepository>(
  (Ref ref) => ApiMenuRepository(ref.watch(apiClientProvider)),
);

typedef CategoryQuery = ({
  String locationId,
  String locationSlug,
  MenuKind kind,
});
typedef ProductQuery = ({
  String locationId,
  String locationSlug,
  String categoryId,
});
typedef ProductDetailQuery = ({
  String locationId,
  String categoryId,
  String productId,
});

final menuCategoriesProvider = FutureProvider.autoDispose
    .family<List<MenuCategory>, CategoryQuery>((
      Ref ref,
      CategoryQuery query,
    ) async {
      final Location? current = await ref.watch(currentLocationProvider.future);
      if (current == null ||
          current.id != query.locationId ||
          current.slug != query.locationSlug) {
        return const <MenuCategory>[];
      }
      try {
        final categories = await ref
            .watch(menuRepositoryProvider)
            .getCategories(locationSlug: query.locationSlug, kind: query.kind);
        return categories
            .where(
              (category) =>
                  category.locationId == query.locationId &&
                  category.kind == query.kind,
            )
            .toList(growable: false);
      } on ApiException catch (error) {
        if (error.statusCode == 401) {
          await ref.read(authControllerProvider.notifier).signOut();
        }
        rethrow;
      }
    });

final menuProductsProvider = FutureProvider.autoDispose
    .family<List<MenuProduct>, ProductQuery>((
      Ref ref,
      ProductQuery query,
    ) async {
      final Location? current = await ref.watch(currentLocationProvider.future);
      if (current == null ||
          current.id != query.locationId ||
          current.slug != query.locationSlug) {
        return const <MenuProduct>[];
      }
      try {
        final products = await ref
            .watch(menuRepositoryProvider)
            .getProducts(
              locationSlug: query.locationSlug,
              categoryId: query.categoryId,
            );
        return products
            .where((product) => product.categoryId == query.categoryId)
            .toList(growable: false);
      } on ApiException catch (error) {
        if (error.statusCode == 401) {
          await ref.read(authControllerProvider.notifier).signOut();
        }
        rethrow;
      }
    });

final menuProductDetailProvider = FutureProvider.autoDispose
    .family<MenuProduct, ProductDetailQuery>((
      Ref ref,
      ProductDetailQuery query,
    ) async {
      final Location? current = await ref.watch(currentLocationProvider.future);
      if (current == null || current.id != query.locationId) {
        throw const MenuContextChangedException();
      }
      try {
        final product = await ref
            .watch(menuRepositoryProvider)
            .getProduct(query.productId);
        if (product.categoryId != query.categoryId) {
          throw const MenuContextChangedException();
        }
        return product;
      } on ApiException catch (error) {
        if (error.statusCode == 401) {
          await ref.read(authControllerProvider.notifier).signOut();
        }
        rethrow;
      }
    });

class MenuContextChangedException implements Exception {
  const MenuContextChangedException();
  @override
  String toString() =>
      'This menu item does not belong to the selected menu context.';
}
