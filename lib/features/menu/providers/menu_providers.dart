import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

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

typedef ProductMutationKey = ({
  String locationId,
  String locationSlug,
  MenuKind kind,
  String categoryId,
  String? productId,
});

enum ProductMutationPhase { idle, submitting, reconciling, success, error }

class ProductMutationState {
  const ProductMutationState({
    this.phase = ProductMutationPhase.idle,
    this.product,
    this.message,
  });
  final ProductMutationPhase phase;
  final MenuProduct? product;
  final String? message;
  bool get isBusy =>
      phase == ProductMutationPhase.submitting ||
      phase == ProductMutationPhase.reconciling;
}

final productMutationProvider = NotifierProvider.autoDispose
    .family<
      ProductMutationController,
      ProductMutationState,
      ProductMutationKey
    >(ProductMutationController.new);

class ProductMutationController extends Notifier<ProductMutationState> {
  ProductMutationController(this.key);
  final ProductMutationKey key;
  @override
  ProductMutationState build() => const ProductMutationState();

  Future<bool> save(ProductWriteInput input) async {
    if (state.isBusy || !await _contextValid(input)) return false;
    state = const ProductMutationState(phase: ProductMutationPhase.submitting);
    try {
      final MenuProduct response = key.productId == null
          ? await ref.read(menuRepositoryProvider).createProduct(input)
          : await ref
                .read(menuRepositoryProvider)
                .updateProduct(key.productId!, input);
      state = ProductMutationState(
        phase: ProductMutationPhase.reconciling,
        product: response,
      );
      final MenuProduct canonical = await ref
          .read(menuRepositoryProvider)
          .getProduct(response.id);
      if (!_matches(canonical, input)) {
        state = ProductMutationState(
          phase: ProductMutationPhase.error,
          product: canonical,
          message: 'The saved product differs from the submitted values. Review it before retrying.',
        );
        return false;
      }
      state = ProductMutationState(
        phase: ProductMutationPhase.success,
        product: canonical,
        message: key.productId == null
            ? 'Product created.'
            : 'Product updated.',
      );
      _refresh(canonical.id);
      return true;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await ref.read(authControllerProvider.notifier).signOut();
      }
      if (_ambiguous(error) && key.productId != null) {
        return _reconcileUpdate(input, error);
      }
      state = ProductMutationState(
        phase: ProductMutationPhase.error,
        message: _ambiguous(error) && key.productId == null
            ? '${error.message} Refresh the product list before trying again to avoid a duplicate.'
            : error.message,
      );
      return false;
    } on Object {
      state = const ProductMutationState(
        phase: ProductMutationPhase.error,
        message: 'The product could not be saved.',
      );
      return false;
    }
  }

  Future<bool> _contextValid(ProductWriteInput input) async {
    final Location? location = await ref.read(currentLocationProvider.future);
    if (location == null ||
        location.id != key.locationId ||
        location.slug != key.locationSlug ||
        input.categoryId != key.categoryId) {
      state = const ProductMutationState(
        phase: ProductMutationPhase.error,
        message: 'The selected location or category changed.',
      );
      return false;
    }
    final categories = await ref
        .read(menuRepositoryProvider)
        .getCategories(locationSlug: key.locationSlug, kind: key.kind);
    if (!categories.any(
      (category) =>
          category.id == key.categoryId &&
          category.locationId == key.locationId &&
          category.kind == key.kind,
    )) {
      state = const ProductMutationState(
        phase: ProductMutationPhase.error,
        message: 'This category does not belong to the selected menu.',
      );
      return false;
    }
    return true;
  }

  Future<bool> _reconcileUpdate(
    ProductWriteInput input,
    ApiException patchError,
  ) async {
    state = const ProductMutationState(phase: ProductMutationPhase.reconciling);
    try {
      final canonical = await ref
          .read(menuRepositoryProvider)
          .getProduct(key.productId!);
      if (_matches(canonical, input)) {
        state = ProductMutationState(
          phase: ProductMutationPhase.success,
          product: canonical,
          message: 'Product updated.',
        );
        _refresh(canonical.id);
        return true;
      }
      state = ProductMutationState(
        phase: ProductMutationPhase.error,
        product: canonical,
        message:
            '${patchError.message} The update was not confirmed; review and retry manually.',
      );
    } on Object {
      state = ProductMutationState(
        phase: ProductMutationPhase.error,
        message:
            '${patchError.message} The current product could not be verified.',
      );
    }
    return false;
  }

  bool _matches(MenuProduct p, ProductWriteInput i) =>
      p.categoryId == i.categoryId &&
      p.name == i.name &&
      (p.description ?? '') == i.description &&
      p.priceCents == i.priceCents &&
      p.isAvailable == i.isAvailable &&
      p.sortOrder == i.sortOrder &&
      (p.subcategory ?? '') == i.subcategory &&
      p.servesCount == i.servesCount &&
      (p.disclaimer ?? '') == i.disclaimer;
  bool _ambiguous(ApiException error) =>
      error.cause is DioException &&
      const <DioExceptionType>{
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      }.contains((error.cause! as DioException).type);
  void _refresh(String productId) {
    ref.invalidate(
      menuProductsProvider((
        locationId: key.locationId,
        locationSlug: key.locationSlug,
        categoryId: key.categoryId,
      )),
    );
    ref.invalidate(
      menuProductDetailProvider((
        locationId: key.locationId,
        categoryId: key.categoryId,
        productId: productId,
      )),
    );
  }
}
