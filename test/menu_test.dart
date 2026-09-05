import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/menu/data/menu_repository.dart';
import 'package:pelines_admin_app/features/menu/models/menu_models.dart';
import 'package:pelines_admin_app/features/menu/presentation/menu_screens.dart';
import 'package:pelines_admin_app/features/menu/providers/menu_providers.dart';
import 'package:pelines_admin_app/features/menu/providers/modifier_providers.dart';

void main() {
  test('models preserve kinds, cents, nulls, availability and modifiers', () {
    final MenuCategory category = MenuCategory.fromJson(_category());
    expect(category.kind, MenuKind.store);
    expect(category.locationId, 'location-a');
    expect(category.isActive, isFalse);
    expect(MenuKind.fromJson('future'), MenuKind.unknown);
    expect(MenuKind.store.label, 'Regular Menu');
    expect(MenuKind.catering.label, 'Catering Menu');

    final MenuProduct product = MenuProduct.fromJson(_product(full: true));
    expect(product.priceCents, 1250);
    expect(product.imageUrl, isNull);
    expect(product.isAvailable, isFalse);
    expect(product.modifierGroups.single.options.single.priceDeltaCents, 150);
  });

  test('repository sends exact category query and parses empty list', () async {
    final _Adapter adapter = _Adapter('[]');
    final MenuRepository repository = _api(adapter);
    expect(
      await repository.getCategories(
        locationSlug: 'tualatin',
        kind: MenuKind.catering,
      ),
      isEmpty,
    );
    expect(adapter.options?.method, 'GET');
    expect(adapter.options?.path, 'categories');
    expect(adapter.options?.queryParameters, <String, dynamic>{
      'kind': 'catering',
      'location': 'tualatin',
    });
  });

  for (final bool create in <bool>[true, false]) {
    test(
      'category ${create ? 'POST' : 'PATCH'} sends only the safe contract',
      () async {
        final _Adapter adapter = _Adapter(jsonEncode(_category()));
        final MenuRepository repository = _api(adapter);
        const CategoryWriteInput input = CategoryWriteInput(
          locationId: 'location-a',
          kind: MenuKind.catering,
          name: '  Family & Friends!  ',
          sortOrder: 4,
          isActive: false,
        );

        if (create) {
          await repository.createCategory(input);
        } else {
          await repository.updateCategory('category-a', input);
        }

        expect(adapter.options?.method, create ? 'POST' : 'PATCH');
        expect(
          adapter.options?.path,
          create ? 'categories' : 'categories/category-a',
        );
        expect(adapter.options?.data, <String, dynamic>{
          if (create) 'locationId': 'location-a',
          'name': '  Family & Friends!  ',
          'slug': 'family-friends',
          if (create) 'kind': 'catering',
          'sortOrder': 4,
          'isActive': false,
        });
        final Map<dynamic, dynamic> body = adapter.options?.data as Map;
        expect(body.containsKey('subcategorySchedulesJson'), isFalse);
        expect(body.containsKey('id'), isFalse);
        expect(body.containsKey('createdAt'), isFalse);
        expect(body.containsKey('updatedAt'), isFalse);
      },
    );
  }

  test('category errors use category-specific messages', () async {
    final MenuRepository repository = _api(_Adapter('{}', status: 409));
    await expectLater(
      repository.createCategory(
        const CategoryWriteInput(
          locationId: 'location-a',
          kind: MenuKind.store,
          name: 'Duplicate',
          sortOrder: 0,
          isActive: true,
        ),
      ),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.message,
          'message',
          contains('category'),
        ),
      ),
    );
  });

  test(
    'repository sends exact products query and list has group names',
    () async {
      final _Adapter adapter = _Adapter(jsonEncode(<Object>[_product()]));
      final MenuRepository repository = _api(adapter);
      final products = await repository.getProducts(
        locationSlug: 'troutdale',
        categoryId: 'category-a',
      );
      expect(adapter.options?.queryParameters, <String, dynamic>{
        'categoryId': 'category-a',
        'location': 'troutdale',
      });
      expect(products.single.modifierGroups.single.name, 'Sauce');
      expect(products.single.modifierGroups.single.options, isEmpty);
    },
  );

  test('repository product detail path parses full modifiers', () async {
    final _Adapter adapter = _Adapter(jsonEncode(_product(full: true)));
    final MenuProduct product = await _api(adapter).getProduct('product-uuid');
    expect(adapter.options?.path, 'products/product-uuid');
    expect(product.modifierGroups.single.options, hasLength(1));
  });

  test('price parser is deterministic', () {
    expect(parsePriceCents('12'), 1200);
    expect(parsePriceCents('12.5'), 1250);
    expect(parsePriceCents('12.50'), 1250);
    expect(parsePriceCents('0.99'), 99);
    expect(parsePriceCents('invalid'), isNull);
    expect(parsePriceCents('-1'), isNull);
    expect(parsePriceCents('1.999'), isNull);
  });

  test('signed modifier price parser is deterministic', () {
    expect(parseSignedPriceCents('0'), 0);
    expect(parseSignedPriceCents('1.5'), 150);
    expect(parseSignedPriceCents('1.50'), 150);
    expect(parseSignedPriceCents('-0.50'), -50);
    expect(parseSignedPriceCents('1.999'), isNull);
    expect(parseSignedPriceCents('NaN'), isNull);
  });

  test('modifier group POST sends exact granular body', () async {
    final _Adapter adapter = _Adapter(jsonEncode(_modifierGroup()));
    await _api(adapter).createModifierGroup(
      'product-uuid',
      const ModifierGroupWriteInput(
        name: 'Size',
        isRequired: true,
        minSelect: 1,
        maxSelect: 2,
        sortOrder: 3,
      ),
    );
    expect(adapter.options?.method, 'POST');
    expect(adapter.options?.path, 'products/product-uuid/modifier-groups');
    expect(adapter.options?.data, <String, dynamic>{
      'name': 'Size',
      'isRequired': true,
      'minSelect': 1,
      'maxSelect': 2,
      'sortOrder': 3,
    });
  });

  test('modifier group PATCH does not send options or parent', () async {
    final _Adapter adapter = _Adapter(jsonEncode(_modifierGroup()));
    await _api(adapter).updateModifierGroup(
      'group',
      const ModifierGroupWriteInput(
        name: 'Size',
        isRequired: false,
        minSelect: 0,
        maxSelect: 1,
        sortOrder: 1,
      ),
    );
    expect(adapter.options?.method, 'PATCH');
    expect(adapter.options?.path, 'modifier-groups/group');
    final body = adapter.options?.data as Map<dynamic, dynamic>;
    expect(
      body.keys,
      unorderedEquals(<String>[
        'name',
        'isRequired',
        'minSelect',
        'maxSelect',
        'sortOrder',
      ]),
    );
  });

  for (final bool create in <bool>[true, false]) {
    test('modifier option ${create ? 'POST' : 'PATCH'} is granular', () async {
      final _Adapter adapter = _Adapter(jsonEncode(_modifierOption()));
      const input = ModifierOptionWriteInput(
        name: 'Large',
        priceDeltaCents: -50,
        isDefault: true,
        sortOrder: 2,
      );
      if (create) {
        await _api(adapter).createModifierOption('group', input);
      } else {
        await _api(adapter).updateModifierOption('option', input);
      }
      expect(adapter.options?.method, create ? 'POST' : 'PATCH');
      expect(
        adapter.options?.path,
        create ? 'modifier-groups/group/options' : 'modifier-options/option',
      );
      expect(adapter.options?.data, <String, dynamic>{
        'name': 'Large',
        'priceDeltaCents': -50,
        'isDefault': true,
        'sortOrder': 2,
      });
    });
  }

  for (final bool create in <bool>[true, false]) {
    test(
      '${create ? 'POST create' : 'PATCH update'} sends exact safe body',
      () async {
        final _Adapter adapter = _Adapter(jsonEncode(_product(full: true)));
        final MenuRepository repository = _api(adapter);
        const ProductWriteInput input = ProductWriteInput(
          categoryId: 'category-a',
          name: 'Test Product',
          description: 'Desc',
          priceCents: 1250,
          isAvailable: true,
          sortOrder: 3,
          subcategory: 'Lunch',
          servesCount: 2,
          disclaimer: 'Notice',
        );
        if (create) {
          await repository.createProduct(input);
        } else {
          await repository.updateProduct('product-uuid', input);
        }
        expect(adapter.options?.method, create ? 'POST' : 'PATCH');
        expect(
          adapter.options?.path,
          create ? 'products' : 'products/product-uuid',
        );
        expect(adapter.options?.data, <String, dynamic>{
          'categoryId': 'category-a',
          'name': 'Test Product',
          'slug': 'test-product',
          'description': 'Desc',
          'priceCents': 1250,
          'isAvailable': true,
          'sortOrder': 3,
          'subcategory': 'Lunch',
          'disclaimer': 'Notice',
          'servesCount': 2,
        });
        expect((adapter.options?.data as Map).containsKey('imageUrl'), isFalse);
        expect(
          (adapter.options?.data as Map).containsKey('modifierGroups'),
          isFalse,
        );
        expect((adapter.options?.data as Map).containsKey('id'), isFalse);
      },
    );
  }

  for (final int status in <int>[401, 403, 404]) {
    test('product detail maps $status', () async {
      final MenuRepository repository = _api(_Adapter('{}', status: status));
      await expectLater(
        repository.getProduct('id'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', status),
        ),
      );
    });
  }

  test('provider isolates location and menu kind defensively', () async {
    final _Repository repository = _Repository();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        currentLocationProvider.overrideWith(_CurrentLocation.new),
        menuRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final CategoryQuery regular = (
      locationId: 'location-a',
      locationSlug: 'a',
      kind: MenuKind.store,
    );
    final CategoryQuery catering = (
      locationId: 'location-a',
      locationSlug: 'a',
      kind: MenuKind.catering,
    );
    expect(
      (await container.read(menuCategoriesProvider(regular).future))
          .single
          .kind,
      MenuKind.store,
    );
    expect(
      (await container.read(menuCategoriesProvider(catering).future))
          .single
          .kind,
      MenuKind.catering,
    );
    (container.read(currentLocationProvider.notifier) as _CurrentLocation)
        .change(_location('location-b', 'b'));
    expect(
      await container.read(menuCategoriesProvider(regular).future),
      isEmpty,
    );
  });

  test('products discard a mismatched category and accept empty', () async {
    final _Repository repository = _Repository()..wrongProductCategory = true;
    final ProviderContainer container = ProviderContainer(
      overrides: [
        currentLocationProvider.overrideWith(_CurrentLocation.new),
        menuRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    const ProductQuery query = (
      locationId: 'location-a',
      locationSlug: 'a',
      categoryId: 'category-a',
    );
    expect(await container.read(menuProductsProvider(query).future), isEmpty);
  });

  test('update timeout reconciles by GET without retrying PATCH', () async {
    final _Repository repository = _Repository()..writeError = _timeout();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        currentLocationProvider.overrideWith(_CurrentLocation.new),
        menuRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    const key = (
      locationId: 'location-a',
      locationSlug: 'a',
      kind: MenuKind.store,
      categoryId: 'category-a',
      productId: 'product-uuid',
    );
    final bool result = await container
        .read(productMutationProvider(key).notifier)
        .save(_writeInput());
    expect(
      result,
      isTrue,
      reason: container.read(productMutationProvider(key)).message,
    );
    expect(repository.updateCalls, 1);
    expect(
      container.read(productMutationProvider(key)).phase,
      ProductMutationPhase.success,
    );
  });

  test('create timeout never retries and warns before duplicate', () async {
    final _Repository repository = _Repository()..writeError = _timeout();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        currentLocationProvider.overrideWith(_CurrentLocation.new),
        menuRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    const key = (
      locationId: 'location-a',
      locationSlug: 'a',
      kind: MenuKind.store,
      categoryId: 'category-a',
      productId: null,
    );
    expect(
      await container
          .read(productMutationProvider(key).notifier)
          .save(_writeInput()),
      isFalse,
    );
    expect(repository.createCalls, 1);
    expect(
      container.read(productMutationProvider(key)).message,
      contains('avoid a duplicate'),
    );
  });

  test('wrong location blocks mutation request', () async {
    final _Repository repository = _Repository();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        currentLocationProvider.overrideWith(_CurrentLocation.new),
        menuRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    const key = (
      locationId: 'wrong',
      locationSlug: 'wrong',
      kind: MenuKind.store,
      categoryId: 'category-a',
      productId: null,
    );
    expect(
      await container
          .read(productMutationProvider(key).notifier)
          .save(_writeInput()),
      isFalse,
    );
    expect(repository.createCalls, 0);
  });

  test('category update timeout reconciles without retrying PATCH', () async {
    final _Repository repository = _Repository()
      ..categoryWriteError = _timeout();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        currentLocationProvider.overrideWith(_CurrentLocation.new),
        menuRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    const CategoryMutationKey key = (
      locationId: 'location-a',
      locationSlug: 'a',
      kind: MenuKind.store,
      categoryId: 'category-a',
    );

    expect(
      await container
          .read(categoryMutationProvider(key).notifier)
          .save(_categoryWriteInput()),
      isTrue,
    );
    expect(repository.categoryUpdateCalls, 1);
    expect(
      container.read(categoryMutationProvider(key)).phase,
      CategoryMutationPhase.success,
    );
  });

  test('category create timeout is never retried', () async {
    final _Repository repository = _Repository()
      ..categoryWriteError = _timeout();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        currentLocationProvider.overrideWith(_CurrentLocation.new),
        menuRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    const CategoryMutationKey key = (
      locationId: 'location-a',
      locationSlug: 'a',
      kind: MenuKind.store,
      categoryId: null,
    );

    expect(
      await container
          .read(categoryMutationProvider(key).notifier)
          .save(_categoryWriteInput()),
      isFalse,
    );
    expect(repository.categoryCreateCalls, 1);
    expect(
      container.read(categoryMutationProvider(key)).message,
      contains('avoid a duplicate'),
    );
  });

  test('wrong menu context blocks category creation', () async {
    final _Repository repository = _Repository();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        currentLocationProvider.overrideWith(_CurrentLocation.new),
        menuRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    const CategoryMutationKey key = (
      locationId: 'location-a',
      locationSlug: 'a',
      kind: MenuKind.catering,
      categoryId: null,
    );

    expect(
      await container
          .read(categoryMutationProvider(key).notifier)
          .save(_categoryWriteInput()),
      isFalse,
    );
    expect(repository.categoryCreateCalls, 0);
  });

  test('modifier group update timeout reconciles without retry', () async {
    final repository = _Repository()..modifierWriteError = _timeout();
    final container = ProviderContainer(
      overrides: [
        currentLocationProvider.overrideWith(_CurrentLocation.new),
        menuRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    const context = (
      locationId: 'location-a',
      locationSlug: 'a',
      kind: MenuKind.store,
      categoryId: 'category-a',
      productId: 'product-uuid',
    );
    const input = ModifierGroupWriteInput(
      name: 'Sauce',
      isRequired: true,
      minSelect: 1,
      maxSelect: 1,
      sortOrder: 0,
    );
    expect(
      await container
          .read(modifierMutationProvider(context).notifier)
          .saveGroup(input, groupId: 'group'),
      isTrue,
    );
    expect(repository.modifierGroupUpdateCalls, 1);
  });

  test('modifier option create timeout is not retried', () async {
    final repository = _Repository()..modifierWriteError = _timeout();
    final container = ProviderContainer(
      overrides: [
        currentLocationProvider.overrideWith(_CurrentLocation.new),
        menuRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    const context = (
      locationId: 'location-a',
      locationSlug: 'a',
      kind: MenuKind.store,
      categoryId: 'category-a',
      productId: 'product-uuid',
    );
    const input = ModifierOptionWriteInput(
      name: 'New option',
      priceDeltaCents: 0,
      isDefault: false,
      sortOrder: 1,
    );
    expect(
      await container
          .read(modifierMutationProvider(context).notifier)
          .saveOption(input, groupId: 'group'),
      isFalse,
    );
    expect(repository.modifierOptionCreateCalls, 1);
    expect(
      container.read(modifierMutationProvider(context)).message,
      contains('avoid a duplicate'),
    );
  });

  test('wrong context blocks modifier write', () async {
    final repository = _Repository();
    final container = ProviderContainer(
      overrides: [
        currentLocationProvider.overrideWith(_CurrentLocation.new),
        menuRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    const context = (
      locationId: 'wrong',
      locationSlug: 'wrong',
      kind: MenuKind.store,
      categoryId: 'category-a',
      productId: 'product-uuid',
    );
    const input = ModifierGroupWriteInput(
      name: 'Sauce',
      isRequired: true,
      minSelect: 1,
      maxSelect: 1,
      sortOrder: 0,
    );
    expect(
      await container
          .read(modifierMutationProvider(context).notifier)
          .saveGroup(input),
      isFalse,
    );
    expect(repository.modifierGroupCreateCalls, 0);
  });

  testWidgets('landing follows Menu to category to product and Back', (
    tester,
  ) async {
    final GoRouter router = GoRouter(
      initialLocation: '/app/menu',
      routes: <RouteBase>[
        GoRoute(
          path: '/app/menu',
          builder: (_, _) => const MenuLandingScreen(),
        ),
        GoRoute(
          path: '/app/menu/:kind',
          builder: (_, state) => MenuCategoriesScreen(
            kind: MenuKind.fromJson(state.pathParameters['kind']),
          ),
        ),
        GoRoute(
          path: '/app/menu/:kind/categories/:categoryId',
          builder: (_, state) => MenuProductsScreen(
            kind: MenuKind.fromJson(state.pathParameters['kind']),
            categoryId: state.pathParameters['categoryId']!,
            categoryName: state.uri.queryParameters['name'] ?? 'Products',
          ),
        ),
        GoRoute(
          path: '/app/menu/:kind/categories/:categoryId/products/:productId',
          builder: (_, state) => MenuProductDetailScreen(
            kind: MenuKind.fromJson(state.pathParameters['kind']),
            categoryId: state.pathParameters['categoryId']!,
            categoryName: state.uri.queryParameters['category'] ?? 'Category',
            productId: state.pathParameters['productId']!,
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentLocationProvider.overrideWith(_CurrentLocation.new),
          menuRepositoryProvider.overrideWithValue(_Repository()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Regular Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Store Category'), findsOneWidget);
    await tester.tap(find.text('Store Category'));
    await tester.pumpAndSettle();
    expect(find.text('Test Product'), findsOneWidget);
    expect(find.textContaining(r'$12.50'), findsOneWidget);
    expect(find.textContaining('Unavailable'), findsOneWidget);
    await tester.tap(find.text('Test Product'));
    await tester.pumpAndSettle();
    expect(find.text('Product Detail'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sauce'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Sauce'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Test Product'), findsOneWidget);
  });
}

MenuRepository _api(_Adapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
    ..httpClientAdapter = adapter;
  return ApiMenuRepository(ApiClient(dio: dio));
}

ProductWriteInput _writeInput() => const ProductWriteInput(
  categoryId: 'category-a',
  name: 'Test Product',
  priceCents: 1250,
  isAvailable: false,
  sortOrder: 1,
);

CategoryWriteInput _categoryWriteInput() => const CategoryWriteInput(
  locationId: 'location-a',
  kind: MenuKind.store,
  name: 'Store Category',
  sortOrder: 2,
  isActive: false,
);
ApiException _timeout() {
  final options = RequestOptions(path: 'products');
  return ApiException(
    message: 'timed out',
    cause: DioException(
      requestOptions: options,
      type: DioExceptionType.receiveTimeout,
    ),
  );
}

Map<String, dynamic> _category({
  String kind = 'store',
  String location = 'location-a',
}) => <String, dynamic>{
  'id': 'category-a',
  'locationId': location,
  'name': kind == 'store' ? 'Store Category' : 'Catering Category',
  'slug': 'category',
  'sortOrder': 2,
  'isActive': false,
  'kind': kind,
  'subcategorySchedulesJson': null,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-02T00:00:00Z',
};
Map<String, dynamic> _product({
  bool full = false,
  String category = 'category-a',
}) => <String, dynamic>{
  'id': 'product-uuid',
  'categoryId': category,
  'name': 'Test Product',
  'slug': 'test-product',
  'description': null,
  'priceCents': 1250,
  'imageUrl': null,
  'isAvailable': false,
  'sortOrder': 1,
  'subcategory': null,
  'servesCount': null,
  'disclaimer': null,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-02T00:00:00Z',
  'modifierGroups': <Object>[
    <String, dynamic>{
      'id': 'group',
      'productId': 'product-uuid',
      'name': 'Sauce',
      'sortOrder': 0,
      if (full) ...<String, dynamic>{
        'isRequired': true,
        'minSelect': 1,
        'maxSelect': 1,
        'options': <Object>[
          <String, dynamic>{
            'id': 'option',
            'groupId': 'group',
            'name': 'Hot',
            'priceDeltaCents': 150,
            'isDefault': false,
            'sortOrder': 0,
          },
        ],
      },
    },
  ],
};

Map<String, dynamic> _modifierGroup() => <String, dynamic>{
  'id': 'group',
  'productId': 'product-uuid',
  'name': 'Size',
  'isRequired': true,
  'minSelect': 1,
  'maxSelect': 2,
  'sortOrder': 3,
  'options': <Object>[],
};

Map<String, dynamic> _modifierOption() => <String, dynamic>{
  'id': 'option',
  'groupId': 'group',
  'name': 'Large',
  'priceDeltaCents': -50,
  'isDefault': true,
  'sortOrder': 2,
};

Location _location(String id, String slug) => Location(
  id: id,
  name: id,
  slug: slug,
  isActive: true,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  isAcceptingOrders: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _CurrentLocation extends CurrentLocationController {
  @override
  Future<Location?> build() async => _location('location-a', 'a');
  void change(Location value) => state = AsyncData<Location?>(value);
}

class _Repository implements MenuRepository {
  bool wrongProductCategory = false;
  Object? writeError;
  int createCalls = 0;
  int updateCalls = 0;
  Object? categoryWriteError;
  int categoryCreateCalls = 0;
  int categoryUpdateCalls = 0;
  Object? modifierWriteError;
  int modifierGroupCreateCalls = 0;
  int modifierGroupUpdateCalls = 0;
  int modifierOptionCreateCalls = 0;
  int modifierOptionUpdateCalls = 0;
  @override
  Future<List<MenuCategory>> getCategories({
    required String locationSlug,
    required MenuKind kind,
  }) async => <MenuCategory>[MenuCategory.fromJson(_category(kind: kind.name))];
  @override
  Future<List<MenuProduct>> getProducts({
    required String locationSlug,
    required String categoryId,
  }) async => <MenuProduct>[
    MenuProduct.fromJson(
      _product(category: wrongProductCategory ? 'wrong' : categoryId),
    ),
  ];
  @override
  Future<MenuProduct> getProduct(String productId) async =>
      MenuProduct.fromJson(_product(full: true));
  @override
  Future<MenuProduct> createProduct(ProductWriteInput input) async =>
      (++createCalls > 0 && writeError != null)
      ? throw writeError!
      : MenuProduct.fromJson(_product(full: true));
  @override
  Future<MenuProduct> updateProduct(
    String productId,
    ProductWriteInput input,
  ) async {
    updateCalls++;
    if (writeError != null) throw writeError!;
    return MenuProduct.fromJson(_product(full: true));
  }

  @override
  Future<MenuCategory> getCategory(String categoryId) async =>
      MenuCategory.fromJson(_category());
  @override
  Future<MenuCategory> createCategory(CategoryWriteInput input) async =>
      (++categoryCreateCalls > 0 && categoryWriteError != null)
      ? throw categoryWriteError!
      : MenuCategory.fromJson(_category());
  @override
  Future<MenuCategory> updateCategory(
    String categoryId,
    CategoryWriteInput input,
  ) async {
    categoryUpdateCalls++;
    if (categoryWriteError != null) throw categoryWriteError!;
    return MenuCategory.fromJson(_category());
  }

  @override
  Future<List<MenuModifierGroup>> getModifierGroups(String productId) async =>
      MenuProduct.fromJson(_product(full: true)).modifierGroups;

  @override
  Future<MenuModifierGroup> createModifierGroup(
    String productId,
    ModifierGroupWriteInput input,
  ) async {
    modifierGroupCreateCalls++;
    if (modifierWriteError != null) throw modifierWriteError!;
    return MenuProduct.fromJson(_product(full: true)).modifierGroups.single;
  }

  @override
  Future<MenuModifierGroup> updateModifierGroup(
    String groupId,
    ModifierGroupWriteInput input,
  ) async {
    modifierGroupUpdateCalls++;
    if (modifierWriteError != null) throw modifierWriteError!;
    return MenuProduct.fromJson(_product(full: true)).modifierGroups.single;
  }

  @override
  Future<MenuModifierOption> createModifierOption(
    String groupId,
    ModifierOptionWriteInput input,
  ) async {
    modifierOptionCreateCalls++;
    if (modifierWriteError != null) throw modifierWriteError!;
    return MenuProduct.fromJson(_product(full: true))
        .modifierGroups
        .single
        .options
        .single;
  }

  @override
  Future<MenuModifierOption> updateModifierOption(
    String optionId,
    ModifierOptionWriteInput input,
  ) async {
    modifierOptionUpdateCalls++;
    if (modifierWriteError != null) throw modifierWriteError!;
    return MenuProduct.fromJson(_product(full: true))
        .modifierGroups
        .single
        .options
        .single;
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body, {this.status = 200});
  final String body;
  final int status;
  RequestOptions? options;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options = options;
    return ResponseBody.fromString(
      body,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
