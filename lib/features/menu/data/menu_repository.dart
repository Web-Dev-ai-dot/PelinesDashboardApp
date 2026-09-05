import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../models/menu_models.dart';

abstract interface class MenuRepository {
  Future<List<MenuCategory>> getCategories({
    required String locationSlug,
    required MenuKind kind,
  });
  Future<List<MenuProduct>> getProducts({
    required String locationSlug,
    required String categoryId,
  });
  Future<MenuProduct> getProduct(String productId);
  Future<MenuProduct> createProduct(ProductWriteInput input);
  Future<MenuProduct> updateProduct(String productId, ProductWriteInput input);
  Future<MenuCategory> getCategory(String categoryId);
  Future<MenuCategory> createCategory(CategoryWriteInput input);
  Future<MenuCategory> updateCategory(
    String categoryId,
    CategoryWriteInput input,
  );
  Future<List<MenuModifierGroup>> getModifierGroups(String productId);
  Future<MenuModifierGroup> createModifierGroup(
    String productId,
    ModifierGroupWriteInput input,
  );
  Future<MenuModifierGroup> updateModifierGroup(
    String groupId,
    ModifierGroupWriteInput input,
  );
  Future<MenuModifierOption> createModifierOption(
    String groupId,
    ModifierOptionWriteInput input,
  );
  Future<MenuModifierOption> updateModifierOption(
    String optionId,
    ModifierOptionWriteInput input,
  );
}

class ModifierGroupWriteInput {
  const ModifierGroupWriteInput({
    required this.name,
    required this.isRequired,
    required this.minSelect,
    required this.maxSelect,
    required this.sortOrder,
  });
  final String name;
  final bool isRequired;
  final int minSelect;
  final int maxSelect;
  final int sortOrder;
  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'isRequired': isRequired,
    'minSelect': minSelect,
    'maxSelect': maxSelect,
    'sortOrder': sortOrder,
  };
}

class ModifierOptionWriteInput {
  const ModifierOptionWriteInput({
    required this.name,
    required this.priceDeltaCents,
    required this.isDefault,
    required this.sortOrder,
  });
  final String name;
  final int priceDeltaCents;
  final bool isDefault;
  final int sortOrder;
  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'priceDeltaCents': priceDeltaCents,
    'isDefault': isDefault,
    'sortOrder': sortOrder,
  };
}

class CategoryWriteInput {
  const CategoryWriteInput({
    required this.locationId,
    required this.kind,
    required this.name,
    required this.sortOrder,
    required this.isActive,
  });
  final String locationId;
  final MenuKind kind;
  final String name;
  final int sortOrder;
  final bool isActive;
  Map<String, dynamic> toCreateJson() => <String, dynamic>{
    'locationId': locationId,
    'name': name,
    'slug': productSlug(name),
    'kind': kind.name,
    'sortOrder': sortOrder,
    'isActive': isActive,
  };
  Map<String, dynamic> toUpdateJson() => <String, dynamic>{
    'name': name,
    'slug': productSlug(name),
    'sortOrder': sortOrder,
    'isActive': isActive,
  };
}

class ProductWriteInput {
  const ProductWriteInput({
    required this.categoryId,
    required this.name,
    required this.priceCents,
    required this.isAvailable,
    required this.sortOrder,
    this.description = '',
    this.subcategory = '',
    this.servesCount,
    this.disclaimer = '',
  });
  final String categoryId;
  final String name;
  final String description;
  final int priceCents;
  final bool isAvailable;
  final int sortOrder;
  final String subcategory;
  final int? servesCount;
  final String disclaimer;
  Map<String, dynamic> toJson() => <String, dynamic>{
    'categoryId': categoryId,
    'name': name,
    'slug': productSlug(name),
    'description': description,
    'priceCents': priceCents,
    'isAvailable': isAvailable,
    'sortOrder': sortOrder,
    'subcategory': subcategory,
    'disclaimer': disclaimer,
    if (servesCount != null) 'servesCount': servesCount,
  };
}

String productSlug(String value) {
  final String slug = value
      .toLowerCase()
      .trim()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'item' : slug;
}

int? parsePriceCents(String value) {
  final RegExpMatch? match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$')
      .firstMatch(value.trim());
  if (match == null) return null;
  final int dollars = int.parse(match.group(1)!);
  final String fraction = (match.group(2) ?? '').padRight(2, '0');
  return dollars * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
}

int? parseSignedPriceCents(String value) {
  final RegExpMatch? match = RegExp(r'^(-)?(\d+)(?:\.(\d{1,2}))?$')
      .firstMatch(value.trim());
  if (match == null) return null;
  final int dollars = int.parse(match.group(2)!);
  final String fraction = (match.group(3) ?? '').padRight(2, '0');
  final int cents =
      dollars * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
  return match.group(1) == '-' ? -cents : cents;
}

class ApiMenuRepository implements MenuRepository {
  ApiMenuRepository(this._client);
  final ApiClient _client;

  @override
  Future<List<MenuCategory>> getCategories({
    required String locationSlug,
    required MenuKind kind,
  }) => _list(
    'categories',
    <String, dynamic>{'kind': kind.name, 'location': locationSlug},
    MenuCategory.fromJson,
    'categories',
  );

  @override
  Future<List<MenuProduct>> getProducts({
    required String locationSlug,
    required String categoryId,
  }) => _list(
    'products',
    <String, dynamic>{'categoryId': categoryId, 'location': locationSlug},
    MenuProduct.fromJson,
    'products',
  );

  @override
  Future<MenuProduct> getProduct(String productId) async {
    try {
      final Response<dynamic> response = await _client.dio.get<dynamic>(
        'products/$productId',
      );
      if (response.data is! Map<String, dynamic>) {
        throw const FormatException('Invalid product.');
      }
      return MenuProduct.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw _error(error, entity: 'Product');
    } on Object catch (error) {
      throw ApiException(
        message: 'The server returned an invalid product.',
        cause: error,
      );
    }
  }

  @override
  Future<MenuProduct> createProduct(ProductWriteInput input) =>
      _write('products', input, create: true);

  @override
  Future<MenuProduct> updateProduct(
    String productId,
    ProductWriteInput input,
  ) => _write('products/$productId', input, create: false);

  Future<MenuProduct> _write(
    String path,
    ProductWriteInput input, {
    required bool create,
  }) async {
    try {
      final Response<dynamic> response = create
          ? await _client.dio.post<dynamic>(path, data: input.toJson())
          : await _client.dio.patch<dynamic>(path, data: input.toJson());
      if (response.data is! Map<String, dynamic>) {
        throw const FormatException('Invalid product.');
      }
      return MenuProduct.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw _error(error, entity: 'Product');
    } on Object catch (error) {
      throw ApiException(
        message: 'The server returned an invalid product.',
        cause: error,
      );
    }
  }

  @override
  Future<MenuCategory> getCategory(String categoryId) =>
      _categoryWrite('categories/$categoryId');
  @override
  Future<MenuCategory> createCategory(CategoryWriteInput input) =>
      _categoryWrite('categories', input: input, create: true);
  @override
  Future<MenuCategory> updateCategory(
    String categoryId,
    CategoryWriteInput input,
  ) => _categoryWrite('categories/$categoryId', input: input);

  @override
  Future<List<MenuModifierGroup>> getModifierGroups(String productId) => _list(
    'products/$productId/modifier-groups',
    const <String, dynamic>{},
    MenuModifierGroup.fromJson,
    'modifier groups',
  );

  @override
  Future<MenuModifierGroup> createModifierGroup(
    String productId,
    ModifierGroupWriteInput input,
  ) => _modifierWrite(
    'products/$productId/modifier-groups',
    input.toJson(),
    MenuModifierGroup.fromJson,
    'modifier group',
    create: true,
  );

  @override
  Future<MenuModifierGroup> updateModifierGroup(
    String groupId,
    ModifierGroupWriteInput input,
  ) => _modifierWrite(
    'modifier-groups/$groupId',
    input.toJson(),
    MenuModifierGroup.fromJson,
    'modifier group',
  );

  @override
  Future<MenuModifierOption> createModifierOption(
    String groupId,
    ModifierOptionWriteInput input,
  ) => _modifierWrite(
    'modifier-groups/$groupId/options',
    input.toJson(),
    MenuModifierOption.fromJson,
    'modifier option',
    create: true,
  );

  @override
  Future<MenuModifierOption> updateModifierOption(
    String optionId,
    ModifierOptionWriteInput input,
  ) => _modifierWrite(
    'modifier-options/$optionId',
    input.toJson(),
    MenuModifierOption.fromJson,
    'modifier option',
  );

  Future<T> _modifierWrite<T>(
    String path,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) parse,
    String label, {
    bool create = false,
  }) async {
    try {
      final Response<dynamic> response = create
          ? await _client.dio.post<dynamic>(path, data: body)
          : await _client.dio.patch<dynamic>(path, data: body);
      if (response.data is! Map<String, dynamic>) {
        throw FormatException('Invalid $label.');
      }
      return parse(response.data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw _error(error, entity: label);
    } on Object catch (error) {
      throw ApiException(
        message: 'The server returned an invalid $label.',
        cause: error,
      );
    }
  }

  Future<MenuCategory> _categoryWrite(
    String path, {
    CategoryWriteInput? input,
    bool create = false,
  }) async {
    try {
      final Response<dynamic> response = input == null
          ? await _client.dio.get<dynamic>(path)
          : create
          ? await _client.dio.post<dynamic>(path, data: input.toCreateJson())
          : await _client.dio.patch<dynamic>(path, data: input.toUpdateJson());
      if (response.data is! Map<String, dynamic>) {
        throw const FormatException('Invalid category.');
      }
      return MenuCategory.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw _error(error, entity: 'Category');
    } on Object catch (error) {
      throw ApiException(
        message: 'The server returned an invalid category.',
        cause: error,
      );
    }
  }

  Future<List<T>> _list<T>(
    String path,
    Map<String, dynamic> query,
    T Function(Map<String, dynamic>) parse,
    String label,
  ) async {
    try {
      final response = await _client.dio.get<dynamic>(
        path,
        queryParameters: query,
      );
      if (response.data is! List<dynamic>) {
        throw const FormatException('Invalid list.');
      }
      return (response.data as List<dynamic>)
          .map((value) => parse(value as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (error) {
      throw _error(error);
    } on Object catch (error) {
      throw ApiException(
        message: 'The server returned invalid $label.',
        cause: error,
      );
    }
  }

  ApiException _error(DioException error, {String? entity}) {
    final int? status = error.response?.statusCode;
    final String message = switch (status) {
      401 => 'Your session is no longer valid. Please sign in again.',
      403 => 'Administrator access is required.',
      404 when entity != null => '$entity no longer available.',
      409 when entity != null =>
        'A ${entity.toLowerCase()} with that slug already exists.',
      400 when entity != null =>
        'The ${entity.toLowerCase()} information is invalid.',
      _
          when error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.sendTimeout =>
        'The Pelines server timed out. Please try again.',
      _ when error.type == DioExceptionType.connectionError =>
        'Could not connect to the Pelines server.',
      _ =>
        entity != null
            ? 'The ${entity.toLowerCase()} could not be loaded.'
            : 'The menu could not be loaded.',
    };
    return ApiException(message: message, statusCode: status, cause: error);
  }
}
