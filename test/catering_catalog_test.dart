import 'dart:async';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';
import 'package:pelines_admin_app/features/locations/presentation/pelines_location_context.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/menu/data/menu_repository.dart';
import 'package:pelines_admin_app/features/menu/models/menu_models.dart';
import 'package:pelines_admin_app/features/menu/presentation/menu_screens.dart';
import 'package:pelines_admin_app/features/menu/presentation/product_form_screen.dart';
import 'package:pelines_admin_app/features/menu/presentation/category_form_screen.dart';
import 'package:pelines_admin_app/features/menu/providers/menu_providers.dart';
import 'package:pelines_admin_app/features/menu/providers/catering_actions.dart';
import 'package:pelines_admin_app/features/menu/providers/product_image_providers.dart';
import 'package:pelines_admin_app/features/menu/data/product_image_service.dart';

import 'analytics_providers_test.dart' show FakeLocation;

MenuCategory category(String id, {MenuKind kind = MenuKind.catering}) =>
    MenuCategory(
      id: id,
      locationId: 'a',
      name: 'Category $id',
      slug: id,
      sortOrder: 0,
      isActive: true,
      kind: kind,
      rawKind: kind.name,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
MenuProduct product(
  String id,
  String cat, {
  String? name,
  String? image,
  List<MenuModifierGroup> groups = const [],
}) => MenuProduct(
  id: id,
  categoryId: cat,
  name: name ?? 'Meal $id',
  slug: id,
  priceCents: 1250,
  isAvailable: true,
  sortOrder: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  modifierGroups: groups,
  description: 'Backend description',
  disclaimer: 'Backend disclaimer',
  subcategory: 'Buffet',
  servesCount: 12,
  imageUrl: image,
);

class Repo implements MenuRepository {
  Repo({this.kind = MenuKind.catering});
  final MenuKind kind;
  @override
  Future<MenuCategory> getCategory(String id) async => category(id, kind: kind);
  String image = 'https://example.test/old.jpg';
  int imagePatches = 0;
  @override
  Future<ProductUploadTarget> createProductUploadTarget({
    required String filename,
    required String contentType,
    required int sizeBytes,
  }) async => ProductUploadTarget(
    uploadUrl: Uri.parse('https://storage.test/signed'),
    publicUrl: Uri.parse('https://example.test/new.jpg'),
    path: 'photo.jpg',
    token: 'test',
  );
  @override
  Future<MenuProduct> updateProductImage(
    String productId,
    String imageUrl,
  ) async {
    imagePatches++;
    image = imageUrl;
    return product(productId, 'c', image: image);
  }

  int reads = 0, creates = 0, groupsCreated = 0, optionsCreated = 0;
  bool fail = false, failGroups = false, failOptions = false;
  ProductWriteInput? copied;
  List<MenuProduct> products = [
    product('10', 'c'),
    product('2', 'c'),
    product('b', 'd'),
  ];
  List<MenuModifierGroup> groups = [];
  @override
  Future<List<MenuCategory>> getCategories({
    required String locationSlug,
    required MenuKind kind,
  }) async => [
    category('c', kind: kind),
    category('d', kind: kind),
    category(
      'wrong',
      kind: kind == MenuKind.store ? MenuKind.catering : MenuKind.store,
    ),
  ];
  @override
  Future<List<MenuProduct>> getProducts({
    required String locationSlug,
    required String categoryId,
  }) async {
    reads++;
    if (fail) throw Exception('explicit menu failure');
    return products.where((p) => p.categoryId == categoryId).toList();
  }

  @override
  Future<MenuProduct> getProduct(String id) async =>
      product(id, 'c', image: image, groups: groups);
  @override
  Future<List<MenuModifierGroup>> getModifierGroups(String productId) async {
    if (failGroups) throw Exception('cannot read modifiers');
    return groups;
  }

  @override
  Future<MenuProduct> createProduct(ProductWriteInput input) async {
    creates++;
    copied = input;
    return product('copy', input.categoryId);
  }

  @override
  Future<MenuModifierGroup> createModifierGroup(
    String productId,
    ModifierGroupWriteInput input,
  ) async {
    groupsCreated++;
    return MenuModifierGroup(
      id: 'new-group',
      productId: productId,
      name: input.name,
      sortOrder: input.sortOrder,
      isRequired: input.isRequired,
      minSelect: input.minSelect,
      maxSelect: input.maxSelect,
      options: [],
    );
  }

  @override
  Future<MenuModifierOption> createModifierOption(
    String groupId,
    ModifierOptionWriteInput input,
  ) async {
    optionsCreated++;
    if (failOptions) throw Exception('timeout');
    return MenuModifierOption(
      id: 'new-option',
      groupId: groupId,
      name: input.name,
      priceDeltaCents: input.priceDeltaCents,
      isDefault: input.isDefault,
      sortOrder: input.sortOrder,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Picker implements ProductImagePicker {
  @override
  Future<XFile?> pick() async =>
      XFile.fromData(Uint8List.fromList([255, 216, 255]));
}

class Processor implements ProductImageProcessor {
  @override
  Future<ProcessedProductImage> process(XFile file) async =>
      ProcessedProductImage(
        bytes: Uint8List.fromList([255, 216, 255]),
        type: ProductImageType.jpeg,
        filename: 'photo.jpg',
      );
}

class Uploader implements ProductStorageUploader {
  bool fail = true;
  @override
  Future<void> upload({
    required Uri uploadUrl,
    required Uint8List bytes,
    required String contentType,
    void Function(int, int)? onProgress,
  }) async {
    if (fail) throw const ProductImageException('Upload failed');
    onProgress?.call(bytes.length, bytes.length);
  }
}

class DeleteApi extends CateringDeleteApi {
  DeleteApi() : super(Dio());
  int calls = 0;
  Completer<void>? hold;
  @override
  Future<void> delete(CateringEntity entity, String id) async {
    calls++;
    await hold?.future;
  }
}

Future<GoRouter> mount(
  WidgetTester tester,
  Repo repo, {
  String lang = 'en',
  double width = 390,
  double scale = 1,
  DeleteApi? deletion,
}) async {
  final kind = repo.kind;
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/app/menu/${kind.name}',
    routes: [
      GoRoute(
        path: '/app/menu/${kind.name}',
        builder: (_, _) => MenuCategoriesScreen(kind: kind),
      ),
      GoRoute(
        path: '/app/menu/${kind.name}/categories/new',
        pageBuilder: (_, state) =>
            NewCategoryPage(key: state.pageKey, kind: kind),
      ),
      GoRoute(
        path: '/app/menu/${kind.name}/categories/:category/edit',
        builder: (_, s) => CategoryFormScreen(
          kind: kind,
          categoryId: s.pathParameters['category'],
        ),
      ),
      GoRoute(
        path: '/app/menu/${kind.name}/categories/:category/products/new',
        builder: (_, s) => ProductFormScreen(
          kind: kind,
          categoryId: s.pathParameters['category']!,
          categoryName: 'Category',
        ),
      ),
      GoRoute(
        path: '/app/menu/${kind.name}/categories/:category/products/:id/edit',
        builder: (_, s) => ProductFormScreen(
          kind: kind,
          categoryId: s.pathParameters['category']!,
          categoryName: 'Category',
          productId: s.pathParameters['id'],
        ),
      ),
      GoRoute(
        path: '/app/menu/${kind.name}/categories/:category/products/:id',
        builder: (_, s) => MenuProductDetailScreen(
          kind: kind,
          categoryId: s.pathParameters['category']!,
          categoryName: 'Category',
          productId: s.pathParameters['id']!,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        menuRepositoryProvider.overrideWithValue(repo),
        currentLocationProvider.overrideWith(FakeLocation.new),
        cateringDeleteProvider.overrideWithValue(deletion ?? DeleteApi()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: Locale(lang),
        supportedLocales: AdminLocalizations.supportedLocales,
        localizationsDelegates: const [
          AdminLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() => menuCatalogTests(MenuKind.catering);

void menuCatalogTests(MenuKind kind) {
  final prefix = kind == MenuKind.catering ? 'catering' : 'regular';
  testWidgets('category edit action retains navigation', (tester) async {
    await mount(tester, Repo(kind: kind));
    final edit = find.descendant(
      of: find.byKey(ValueKey('$prefix-category-header-c')),
      matching: find.widgetWithText(TextButton, 'Edit Category'),
    );
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CategoryFormScreen>(find.byType(CategoryFormScreen))
          .categoryId,
      'c',
    );
  });
  testWidgets('in-card actions retain edit, duplicate and delete callbacks', (
    tester,
  ) async {
    final repo = Repo(kind: kind);
    final deletion = DeleteApi();
    final router = await mount(tester, repo, deletion: deletion);
    Finder action(String label) => find.descendant(
      of: find.byKey(const ValueKey('menu-product-2')),
      matching: kind == MenuKind.catering
          ? find.byWidgetPredicate((w) => w is IconButton && w.tooltip == label)
          : find.widgetWithText(TextButton, label),
    );
    Future<void> reveal(String label) async {
      await tester.ensureVisible(action(label));
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 10 && action(label).hitTestable().evaluate().isEmpty;
        i++
      ) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
        await tester.pumpAndSettle();
      }
      expect(action(label).hitTestable(), findsOneWidget);
    }

    if (kind == MenuKind.catering) {
      final view = find.descendant(
        of: find.byKey(const ValueKey('menu-product-2')),
        matching: find.widgetWithText(OutlinedButton, 'View'),
      );
      await tester.ensureVisible(view);
      await tester.pumpAndSettle();
      for (var i = 0; i < 10 && view.hitTestable().evaluate().isEmpty; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
        await tester.pumpAndSettle();
      }
      expect(view.hitTestable(), findsOneWidget);
      await tester.tap(view);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MenuProductDetailScreen>(
              find.byType(MenuProductDetailScreen),
            )
            .productId,
        '2',
      );
      router.go('/app/menu/${kind.name}');
      await tester.pumpAndSettle();
    }
    await reveal('Edit');
    await tester.tap(action('Edit'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ProductFormScreen>(find.byType(ProductFormScreen))
          .productId,
      '2',
    );
    router.go('/app/menu/${kind.name}');
    await tester.pumpAndSettle();
    await reveal('Duplicate');
    await tester.tap(action('Duplicate'));
    await tester.pumpAndSettle();
    expect(repo.creates, 0);
    await tester.tap(find.widgetWithText(FilledButton, 'Duplicate'));
    await tester.pumpAndSettle();
    expect(repo.creates, 1);
    await reveal('Delete');
    await tester.tap(action('Delete'));
    await tester.pumpAndSettle();
    expect(deletion.calls, 0);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(deletion.calls, 0);
    await reveal('Delete');
    await tester.tap(action('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(deletion.calls, 1);
    expect(tester.takeException(), isNull);
  });
  test('delete uses confirmed backend resources', () async {
    final requests = <String>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add('${options.method} ${options.path}');
            handler.resolve(Response(requestOptions: options, statusCode: 204));
          },
        ),
      );
    final api = CateringDeleteApi(dio);
    for (final entity in CateringEntity.values) {
      await api.delete(entity, 'id');
    }
    expect(requests, [
      'DELETE products/id',
      'DELETE categories/id',
      'DELETE modifier-groups/id',
      'DELETE modifier-options/id',
    ]);
  });
  for (final lang in ['en', 'es']) {
    for (final viewport in [
      (320.0, 2.0),
      (390.0, 2.0),
      (800.0, 1.0),
      (1440.0, 1.0),
      (800.0, 2.0),
    ]) {
      testWidgets(
        '${kind.label} editor and modifier detail fit $lang/$viewport',
        (tester) async {
          final repo = Repo(kind: kind)
            ..groups = [
              MenuModifierGroup(
                id: 'g',
                productId: 'p',
                name: 'Sides',
                sortOrder: 0,
                isRequired: true,
                minSelect: 1,
                maxSelect: 2,
                options: [
                  MenuModifierOption(
                    id: 'o',
                    groupId: 'g',
                    name: 'Rice',
                    priceDeltaCents: 200,
                    isDefault: false,
                    sortOrder: 0,
                  ),
                ],
              ),
            ];
          final router = await mount(
            tester,
            repo,
            lang: lang,
            width: viewport.$1,
            scale: viewport.$2,
          );
          router.go('/app/menu/${kind.name}/categories/c/products/p/edit');
          await tester.pumpAndSettle();
          expect(
            find.text(
              lang == 'en'
                  ? (kind == MenuKind.catering ? 'Photo' : 'Product Image')
                  : (kind == MenuKind.catering
                        ? 'Foto'
                        : 'Imagen del producto'),
            ),
            findsOneWidget,
          );
          for (var i = 0; i < 7; i++) {
            await tester.drag(
              find.byType(ListView).first,
              const Offset(0, -500),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          router.go('/app/menu/${kind.name}/categories/c/products/p');
          await tester.pumpAndSettle();
          for (var i = 0; i < 7; i++) {
            await tester.drag(
              find.byType(ListView).first,
              const Offset(0, -500),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          expect(find.text('Sides'), findsOneWidget);
          expect(find.text('Rice'), findsOneWidget);
        },
      );
    }
  }
  test(
    '${kind.label} upload failure preserves old image and retry persists URL',
    () async {
      final repo = Repo(kind: kind), uploader = Uploader();
      final container = ProviderContainer(
        overrides: [
          currentLocationProvider.overrideWith(FakeLocation.new),
          menuRepositoryProvider.overrideWithValue(repo),
          productImagePickerProvider.overrideWithValue(Picker()),
          productImageProcessorProvider.overrideWithValue(Processor()),
          productStorageUploaderProvider.overrideWithValue(uploader),
        ],
      );
      addTearDown(container.dispose);
      final key = (
        locationId: 'a',
        locationSlug: 'a',
        kind: kind,
        categoryId: 'c',
        productId: 'p',
      );
      final subscription = container.listen(
        productImageMutationProvider(key),
        (_, _) {},
      );
      addTearDown(subscription.close);
      final controller = container.read(
        productImageMutationProvider(key).notifier,
      );
      expect(await controller.changeImage(), isFalse);
      expect(repo.image, 'https://example.test/old.jpg');
      expect(repo.imagePatches, 0);
      expect(
        container.read(productImageMutationProvider(key)).phase,
        ProductImagePhase.error,
      );
      uploader.fail = false;
      expect(await controller.changeImage(), isTrue);
      expect(repo.image, 'https://example.test/new.jpg');
      expect(repo.imagePatches, 1);
    },
  );
  test(
    'duplicate copies web fields, photo, serves and complete modifiers',
    () async {
      final repo = Repo(kind: kind)
        ..groups = [
          MenuModifierGroup(
            id: 'g',
            productId: 'p',
            name: 'Sides',
            sortOrder: 0,
            isRequired: true,
            minSelect: 1,
            maxSelect: 2,
            options: [
              MenuModifierOption(
                id: 'o',
                groupId: 'g',
                name: 'Rice',
                priceDeltaCents: 200,
                isDefault: false,
                sortOrder: 0,
              ),
            ],
          ),
        ];
      await duplicateCateringProduct(
        repo,
        product('p', 'c', image: 'https://example.test/photo.jpg'),
        kind: kind,
      );
      expect(repo.creates, 1);
      expect(repo.groupsCreated, 1);
      expect(repo.optionsCreated, 1);
      expect(repo.copied!.name, 'Meal p (Copy)');
      expect(repo.copied!.servesCount, 12);
      expect(repo.copied!.imageUrl, 'https://example.test/photo.jpg');
      expect(
        repo.copied!.subcategory,
        kind == MenuKind.catering ? '' : 'Buffet',
      );
      expect(
        repo.copied!.disclaimer,
        kind == MenuKind.catering ? '' : 'Backend disclaimer',
      );
      repo.failOptions = true;
      await expectLater(
        duplicateCateringProduct(repo, product('p', 'c'), kind: kind),
        throwsA(
          isA<CateringCopyException>().having(
            (e) => e.createdId,
            'created id',
            'copy',
          ),
        ),
      );
      expect(repo.creates, 2); // No automatic retry after a partial copy.
      repo.failGroups = true;
      await expectLater(
        duplicateCateringProduct(repo, product('p', 'c'), kind: kind),
        throwsException,
      );
      expect(
        repo.creates,
        2,
      ); // Never copy without reading modifiers successfully.
    },
  );
  for (final lang in ['en', 'es']) {
    for (final viewport in [
      (390.0, 1.0, 1),
      (320.0, 1.0, 1),
      (800.0, 1.0, 2),
      (1440.0, 1.0, 3),
      (390.0, 2.0, 1),
      (320.0, 2.0, 1),
      (800.0, 2.0, 1),
    ]) {
      testWidgets(
        '${kind.label} grouping, search and responsive $lang $viewport',
        (tester) async {
          final repo = Repo(kind: kind);
          await mount(
            tester,
            repo,
            lang: lang,
            width: viewport.$1,
            scale: viewport.$2,
          );
          expect(
            find.text(
              lang == 'en'
                  ? kind.label
                  : kind == MenuKind.catering
                  ? 'Menú de catering'
                  : 'Menú regular',
            ),
            findsOneWidget,
          );
          final description = find.byKey(const Key('menu-catalog-description'));
          expect(description, findsOneWidget);
          expect(find.byType(PelinesLocationContext), findsOneWidget);
          expect(
            tester.getRect(description).top,
            greaterThanOrEqualTo(
              tester.getRect(find.byType(PelinesLocationContext)).bottom,
            ),
          );
          final create = kind == MenuKind.catering
              ? find.byTooltip(
                  lang == 'en' ? 'New Category' : 'Nueva categoría',
                )
              : find.text(lang == 'en' ? 'New Category' : 'Nueva categoría');
          expect(
            tester.getRect(create).top,
            greaterThan(tester.getRect(description).bottom),
          );
          expect(
            find.byKey(ValueKey('menu-grid-${viewport.$3}')),
            findsWidgets,
          );
          expect(find.text('Category wrong'), findsNothing);
          {
            final wrap = find.byKey(ValueKey('$prefix-category-wrap'));
            expect(tester.widget<Wrap>(wrap).alignment, WrapAlignment.start);
            final all = find.byKey(ValueKey('$prefix-category-all'));
            final first = find.byKey(ValueKey('$prefix-category-c'));
            final last = find.byKey(ValueKey('$prefix-category-d'));
            expect(tester.getTopLeft(all).dx, tester.getTopLeft(wrap).dx);
            if (viewport.$2 == 1 && viewport.$1 >= 390) {
              expect(tester.getTopLeft(first).dy, tester.getTopLeft(all).dy);
            }
            if (viewport.$1 == 320) {
              expect(
                tester.getTopLeft(last).dy,
                greaterThan(tester.getTopLeft(all).dy),
              );
            }
            expect(tester.widget<ChoiceChip>(all).selected, isTrue);
            if (kind == MenuKind.catering) {
              expect(tester.widget<ChoiceChip>(all).showCheckmark, isFalse);
            }
            expect(tester.widget<ChoiceChip>(all).shape, isA<StadiumBorder>());
            expect(tester.getSize(all).height, greaterThanOrEqualTo(48));
            expect(
              tester.widget<ChoiceChip>(all).selectedColor,
              PelinesColors.brandPrimary,
            );
          }
          expect(
            tester.getTopLeft(find.text('Meal 2')).dy,
            lessThanOrEqualTo(tester.getTopLeft(find.text('Meal 10')).dy),
          );
          expect(
            find.textContaining(lang == 'en' ? 'Serves: 12' : 'Porciones: 12'),
            kind == MenuKind.catering ? findsWidgets : findsNothing,
          );
          expect(find.byKey(const Key('menu-image-fallback')), findsWidgets);
          final card = find.byKey(const ValueKey('menu-product-2'));
          final header = find.byKey(ValueKey('$prefix-category-header-c'));
          if (kind == MenuKind.catering) {
            final edit = find.descendant(
              of: card,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is IconButton &&
                    w.tooltip == (lang == 'en' ? 'Edit' : 'Editar'),
              ),
            );
            final photo = find.descendant(
              of: card,
              matching: find.byKey(const Key('menu-image-fallback')),
            );
            final view = find.descendant(
              of: card,
              matching: find.widgetWithText(
                OutlinedButton,
                lang == 'en' ? 'View' : 'Ver',
              ),
            );
            expect(view, findsOneWidget);
            expect(
              tester.getRect(photo).contains(tester.getCenter(edit)),
              isTrue,
            );
            expect(
              tester.getRect(view).width,
              closeTo(tester.getRect(card).width - 34, 1),
            );
            expect(
              tester
                  .widget<Text>(
                    find.descendant(
                      of: header,
                      matching: find.text('Category c'),
                    ),
                  )
                  .style!
                  .color,
              PelinesColors.brandPrimary,
            );
          }

          {
            for (final edit in [true, false]) {
              final action = edit
                  ? find.descendant(
                      of: header,
                      matching: find.widgetWithText(
                        TextButton,
                        lang == 'en' ? 'Edit Category' : 'Editar categoría',
                      ),
                    )
                  : find.descendant(
                      of: header,
                      matching: find.byKey(const ValueKey('catering-delete-c')),
                    );
              final button = tester.widget<TextButton>(action);
              expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
              expect(
                tester.getRect(header).contains(tester.getCenter(action)),
                isTrue,
              );
              expect(
                find.descendant(
                  of: action,
                  matching: find.byIcon(
                    edit ? Icons.edit_outlined : Icons.delete_outline,
                  ),
                ),
                findsOneWidget,
              );
              expect(
                button.style!.backgroundColor!.resolve({}),
                edit ? PelinesColors.mutedSurface : Colors.white,
              );
              expect(
                button.style!.foregroundColor!.resolve({}),
                edit ? PelinesColors.textPrimary : PelinesColors.destructive,
              );
              expect(button.style!.side!.resolve({})!.width, greaterThan(0));
              expect(button.style!.shape!.resolve({}), isA<StadiumBorder>());
            }
          }
          for (final label
              in lang == 'en'
                  ? ['Edit', 'Duplicate', 'Delete']
                  : ['Editar', 'Duplicar', 'Eliminar']) {
            final action = find.descendant(
              of: card,
              matching: kind == MenuKind.catering
                  ? find.byWidgetPredicate(
                      (w) => w is IconButton && w.tooltip == label,
                    )
                  : find.widgetWithText(TextButton, label),
            );
            expect(action, findsOneWidget);
            if (kind == MenuKind.catering) {
              expect(tester.widget<IconButton>(action).onPressed, isNotNull);
              expect(
                find.descendant(of: action, matching: find.byType(Icon)),
                findsOneWidget,
              );
            } else {
              final button = tester.widget<TextButton>(action);
              expect(button.style!.side!.resolve({})!.width, greaterThan(0));
              expect(
                find.descendant(of: action, matching: find.byType(Icon)),
                findsOneWidget,
              );
              if (label == 'Edit' || label == 'Editar') {
                expect(
                  button.style!.backgroundColor!.resolve({}),
                  PelinesColors.mutedSurface,
                );
              }
              if (label == 'Delete' || label == 'Eliminar') {
                expect(
                  button.style!.foregroundColor!.resolve({}),
                  PelinesColors.destructive,
                );
                expect(
                  button.style!.side!.resolve({})!.color,
                  PelinesColors.destructive,
                );
              }
            }
            expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
            expect(
              tester.getRect(card).contains(tester.getCenter(action)),
              isTrue,
            );
          }
          expect(
            find.descendant(of: header, matching: find.text('Category c')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: header,
              matching: find.text(
                lang == 'en' ? 'Edit Category' : 'Editar categoría',
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: header,
              matching: find.byKey(const ValueKey('catering-delete-c')),
            ),
            findsOneWidget,
          );
          final reads = repo.reads;
          await tester.enterText(find.byType(TextField).first, '  MEAL 2  ');
          await tester.pumpAndSettle();
          expect(find.text('Meal 2'), findsOneWidget);
          expect(find.text('Meal 10'), findsNothing);
          expect(repo.reads, reads);
          await tester.enterText(find.byType(TextField).first, '');
          await tester.tap(find.byKey(ValueKey('$prefix-category-d')));
          await tester.pumpAndSettle();
          expect(find.text('Meal b'), findsOneWidget);
          expect(
            tester
                .widget<ChoiceChip>(find.byKey(ValueKey('$prefix-category-d')))
                .selected,
            isTrue,
          );
          expect(find.text('Meal 2'), findsNothing);
          await tester.drag(find.byType(ListView).first, const Offset(0, -700));
          await tester.pumpAndSettle();
          final persistentHeader = find.byKey(
            const Key('persistent-section-header'),
          );
          expect(persistentHeader.hitTestable(), findsOneWidget);
          expect(
            find.descendant(
              of: persistentHeader,
              matching: find.text(
                lang == 'en'
                    ? kind.label
                    : kind == MenuKind.catering
                    ? 'Menú de catering'
                    : 'Menú regular',
              ),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('error retry and true empty are distinct', (tester) async {
    final repo = Repo(kind: kind)..fail = true;
    await mount(tester, repo);
    expect(find.textContaining('explicit menu failure'), findsOneWidget);
    repo.fail = false;
    repo.products = [];
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No products in this category.'), findsOneWidget);
  });
  testWidgets(
    'create chooses category by ID and edit exposes real photo controls',
    (tester) async {
      final router = await mount(tester, Repo(kind: kind));
      await tester.tap(
        kind == MenuKind.catering
            ? find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'New Item',
              )
            : find.text('New Item'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Category d'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ProductFormScreen>(find.byType(ProductFormScreen))
            .categoryId,
        'd',
      );
      expect(
        find.text('Save the item to add its photo and modifiers.'),
        findsOneWidget,
      );
      router.go('/app/menu/${kind.name}/categories/c/products/2/edit');
      await tester.pumpAndSettle();
      expect(
        find.text(kind == MenuKind.catering ? 'Photo' : 'Product Image'),
        findsOneWidget,
      );
      expect(
        find.text(kind == MenuKind.catering ? 'Change image' : 'Change Image'),
        findsOneWidget,
      );
      expect(
        find.text(kind == MenuKind.catering ? 'Add-ons' : 'Manage modifiers'),
        findsOneWidget,
      );
    },
  );
  testWidgets('delete requires confirmation and protects double taps', (
    tester,
  ) async {
    final api = DeleteApi()..hold = Completer<void>();
    await mount(tester, Repo(kind: kind), deletion: api);
    final button = find.descendant(
      of: find.byKey(ValueKey('$prefix-category-header-c')),
      matching: find.byKey(const ValueKey('catering-delete-c')),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(api.calls, 0);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    await tester.pump();
    expect(api.calls, 1);
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    api.hold!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
