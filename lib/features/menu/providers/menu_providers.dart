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
typedef CategoryDetailQuery = ({
  String locationId,
  MenuKind kind,
  String categoryId,
});

final menuCategoryDetailProvider = FutureProvider.autoDispose
    .family<MenuCategory, CategoryDetailQuery>((
      Ref ref,
      CategoryDetailQuery query,
    ) async {
      final Location? current = await ref.watch(currentLocationProvider.future);
      if (current == null || current.id != query.locationId) {
        throw const MenuContextChangedException();
      }
      final MenuCategory category = await ref
          .watch(menuRepositoryProvider)
          .getCategory(query.categoryId);
      if (category.locationId != query.locationId ||
          category.kind != query.kind) {
        throw const MenuContextChangedException();
      }
      return category;
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
      final products = await ref
          .watch(menuRepositoryProvider)
          .getProducts(
            locationSlug: query.locationSlug,
            categoryId: query.categoryId,
          );
      return products
          .where((product) => product.categoryId == query.categoryId)
          .toList(growable: false);
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
      final product = await ref
          .watch(menuRepositoryProvider)
          .getProduct(query.productId);
      if (product.categoryId != query.categoryId) {
        throw const MenuContextChangedException();
      }
      return product;
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

typedef CategoryMutationKey = ({
  String locationId,
  String locationSlug,
  MenuKind kind,
  String? categoryId,
});

enum CategoryMutationPhase { idle, submitting, reconciling, success, error }

class CategoryMutationState {
  const CategoryMutationState({
    this.phase = CategoryMutationPhase.idle,
    this.category,
    this.message,
  });
  final CategoryMutationPhase phase;
  final MenuCategory? category;
  final String? message;
  bool get isBusy =>
      phase == CategoryMutationPhase.submitting ||
      phase == CategoryMutationPhase.reconciling;
}

final categoryMutationProvider = NotifierProvider.autoDispose
    .family<
      CategoryMutationController,
      CategoryMutationState,
      CategoryMutationKey
    >(CategoryMutationController.new);

class CategoryMutationController extends Notifier<CategoryMutationState> {
  CategoryMutationController(this.key);
  final CategoryMutationKey key;
  @override
  CategoryMutationState build() => const CategoryMutationState();
  Future<bool> save(CategoryWriteInput input) async {
    if (state.isBusy || !await _valid(input)) return false;
    state = const CategoryMutationState(
      phase: CategoryMutationPhase.submitting,
    );
    try {
      final provisional = key.categoryId == null
          ? await ref.read(menuRepositoryProvider).createCategory(input)
          : await ref
                .read(menuRepositoryProvider)
                .updateCategory(key.categoryId!, input);
      state = CategoryMutationState(
        phase: CategoryMutationPhase.reconciling,
        category: provisional,
      );
      final canonical = await ref
          .read(menuRepositoryProvider)
          .getCategory(provisional.id);
      if (!_matches(canonical, input)) {
        state = CategoryMutationState(
          phase: CategoryMutationPhase.error,
          category: canonical,
          message: 'The saved category differs from the submitted values. Review it before retrying.',
        );
        return false;
      }
      state = CategoryMutationState(
        phase: CategoryMutationPhase.success,
        category: canonical,
        message: key.categoryId == null
            ? 'Category created.'
            : 'Category updated.',
      );
      _refresh();
      return true;
    } on ApiException catch (error) {
      if (_ambiguousCategory(error) && key.categoryId != null) {
        return _reconcile(input, error);
      }
      state = CategoryMutationState(
        phase: CategoryMutationPhase.error,
        message: _ambiguousCategory(error) && key.categoryId == null
            ? '${error.message} Refresh the category list before trying again to avoid a duplicate.'
            : error.message,
      );
      return false;
    } on Object {
      state = const CategoryMutationState(
        phase: CategoryMutationPhase.error,
        message: 'The category could not be saved.',
      );
      return false;
    }
  }

  Future<bool> _valid(CategoryWriteInput input) async {
    final location = await ref.read(currentLocationProvider.future);
    if (location == null ||
        location.id != key.locationId ||
        location.slug != key.locationSlug ||
        input.locationId != key.locationId ||
        input.kind != key.kind) {
      state = const CategoryMutationState(
        phase: CategoryMutationPhase.error,
        message: 'The selected location or menu changed.',
      );
      return false;
    }
    if (key.categoryId != null) {
      final current = await ref
          .read(menuRepositoryProvider)
          .getCategory(key.categoryId!);
      if (current.locationId != key.locationId || current.kind != key.kind) {
        state = const CategoryMutationState(
          phase: CategoryMutationPhase.error,
          message: 'This category does not belong to the selected menu.',
        );
        return false;
      }
    }
    return true;
  }

  Future<bool> _reconcile(CategoryWriteInput input, ApiException error) async {
    state = const CategoryMutationState(
      phase: CategoryMutationPhase.reconciling,
    );
    try {
      final canonical = await ref
          .read(menuRepositoryProvider)
          .getCategory(key.categoryId!);
      if (_matches(canonical, input)) {
        state = CategoryMutationState(
          phase: CategoryMutationPhase.success,
          category: canonical,
          message: 'Category updated.',
        );
        _refresh();
        return true;
      }
      state = CategoryMutationState(
        phase: CategoryMutationPhase.error,
        category: canonical,
        message:
            '${error.message} The update was not confirmed; retry manually.',
      );
    } on Object {
      state = CategoryMutationState(
        phase: CategoryMutationPhase.error,
        message: '${error.message} The category could not be verified.',
      );
    }
    return false;
  }

  bool _matches(MenuCategory c, CategoryWriteInput i) =>
      c.locationId == i.locationId &&
      c.kind == i.kind &&
      c.name == i.name &&
      c.sortOrder == i.sortOrder &&
      c.isActive == i.isActive;
  bool _ambiguousCategory(ApiException error) =>
      error.cause is DioException &&
      const <DioExceptionType>{
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      }.contains((error.cause! as DioException).type);
  void _refresh() {
    ref.invalidate(
      menuCategoriesProvider((
        locationId: key.locationId,
        locationSlug: key.locationSlug,
        kind: key.kind,
      )),
    );
    if (key.categoryId case final String categoryId) {
      ref.invalidate(
        menuCategoryDetailProvider((
          locationId: key.locationId,
          kind: key.kind,
          categoryId: categoryId,
        )),
      );
    }
  }
}
