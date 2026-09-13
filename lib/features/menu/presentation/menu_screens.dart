import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../../orders/presentation/order_ui_helpers.dart';
import '../models/menu_models.dart';
import '../providers/menu_providers.dart';
import '../providers/product_image_providers.dart';

class MenuLandingScreen extends StatelessWidget {
  const MenuLandingScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Menu')),
    body: ListView(
      padding: const EdgeInsets.all(PelinesSpacing.md),
      children: <Widget>[
        const PelinesSectionHeading('Choose a menu'),
        _MenuChoice(kind: MenuKind.store, icon: Icons.restaurant_menu),
        _MenuChoice(kind: MenuKind.catering, icon: Icons.room_service_outlined),
      ],
    ),
  );
}

class _MenuChoice extends StatelessWidget {
  const _MenuChoice({required this.kind, required this.icon});
  final MenuKind kind;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: PelinesColors.brandPrimarySoft,
          borderRadius: BorderRadius.circular(PelinesRadius.control),
        ),
        child: Icon(icon, color: PelinesColors.brandPrimary),
      ),
      title: Text(kind.label),
      subtitle: const Text('Browse categories and products'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/app/menu/${kind.name}'),
    ),
  );
}

class MenuCategoriesScreen extends ConsumerWidget {
  const MenuCategoriesScreen({required this.kind, super.key});
  final MenuKind kind;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Location?> location = ref.watch(currentLocationProvider);
    return Scaffold(
      appBar: AppBar(title: Text(kind.label)),
      floatingActionButton: location.value == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  context.push('/app/menu/${kind.name}/categories/new'),
              icon: const Icon(Icons.add),
              label: const Text('Add Category'),
            ),
      body: location.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => MenuError(
          message: error.toString(),
          onRetry: () => ref.invalidate(currentLocationProvider),
        ),
        data: (Location? value) {
          if (value == null) {
            return const MenuEmpty('Choose a location to view the menu.');
          }
          final CategoryQuery query = (
            locationId: value.id,
            locationSlug: value.slug,
            kind: kind,
          );
          final AsyncValue<List<MenuCategory>> categories = ref.watch(
            menuCategoriesProvider(query),
          );
          return Column(
            children: <Widget>[
              _LocationHeader(
                name: value.name,
                onRefresh: () => ref.invalidate(menuCategoriesProvider(query)),
              ),
              Expanded(
                child: categories.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => MenuError(
                    message: error.toString(),
                    onRetry: () =>
                        ref.invalidate(menuCategoriesProvider(query)),
                  ),
                  data: (items) => RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(menuCategoriesProvider(query));
                      await ref.read(menuCategoriesProvider(query).future);
                    },
                    child: items.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: <Widget>[
                              MenuEmpty(
                                kind == MenuKind.store
                                    ? 'No regular menu categories for this location.'
                                    : 'No catering categories for this location.',
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final category = items[index];
                              return Card(
                                child: ListTile(
                                  title: Text(category.name),
                                  subtitle: Text(
                                    '${category.isActive ? 'Active' : 'Inactive'} · Order ${category.sortOrder}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      IconButton(
                                        tooltip: 'Edit Category',
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => context.push(
                                          '/app/menu/${kind.name}/categories/${category.id}/edit',
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right),
                                    ],
                                  ),
                                  onTap: () => context.push(
                                    '/app/menu/${kind.name}/categories/${category.id}?name=${Uri.encodeQueryComponent(category.name)}',
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class MenuProductsScreen extends ConsumerWidget {
  const MenuProductsScreen({
    required this.kind,
    required this.categoryId,
    required this.categoryName,
    super.key,
  });
  final MenuKind kind;
  final String categoryId;
  final String categoryName;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Location?> location = ref.watch(currentLocationProvider);
    return Scaffold(
      appBar: AppBar(title: Text(categoryName)),
      floatingActionButton: location.value == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(
                '/app/menu/${kind.name}/categories/$categoryId/products/new?category=${Uri.encodeQueryComponent(categoryName)}',
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add Product'),
            ),
      body: location.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => MenuError(
          message: error.toString(),
          onRetry: () => ref.invalidate(currentLocationProvider),
        ),
        data: (Location? value) {
          if (value == null) {
            return const MenuEmpty('Choose a location to view products.');
          }
          final ProductQuery query = (
            locationId: value.id,
            locationSlug: value.slug,
            categoryId: categoryId,
          );
          final products = ref.watch(menuProductsProvider(query));
          return products.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => MenuError(
              message: error.toString(),
              onRetry: () => ref.invalidate(menuProductsProvider(query)),
            ),
            data: (items) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(menuProductsProvider(query));
                await ref.read(menuProductsProvider(query).future);
              },
              child: items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: <Widget>[
                        MenuEmpty('No products in this category.'),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (context, index) => _ProductTile(
                        product: items[index],
                        onTap: () => context.push(
                          '/app/menu/${kind.name}/categories/$categoryId/products/${items[index].id}?category=${Uri.encodeQueryComponent(categoryName)}',
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});
  final MenuProduct product;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: _ProductImage(url: product.imageUrl, size: 56),
      title: Text(product.name),
      subtitle: Text(
        <String>[
          money(product.priceCents),
          product.isAvailable ? 'Available' : 'Unavailable',
          if (product.description?.isNotEmpty == true) product.description!,
        ].join(' · '),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class MenuProductDetailScreen extends ConsumerWidget {
  const MenuProductDetailScreen({
    required this.kind,
    required this.categoryId,
    required this.categoryName,
    required this.productId,
    super.key,
  });
  final MenuKind kind;
  final String categoryId;
  final String categoryName;
  final String productId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Location? location = ref.watch(currentLocationProvider).value;
    if (location == null) {
      return const Scaffold(
        body: MenuEmpty('Choose a location to view this product.'),
      );
    }
    final ProductDetailQuery query = (
      locationId: location.id,
      categoryId: categoryId,
      productId: productId,
    );
    final product = ref.watch(menuProductDetailProvider(query));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Detail'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Edit Product',
            onPressed: () => context.push(
              '/app/menu/${kind.name}/categories/$categoryId/products/$productId/edit?category=${Uri.encodeQueryComponent(categoryName)}',
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: product.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => MenuError(
          message: error.toString(),
          onRetry: () => ref.invalidate(menuProductDetailProvider(query)),
        ),
        data: (item) => ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            _ProductImageAdministration(
              imageUrl: item.imageUrl,
              locationId: location.id,
              locationSlug: location.slug,
              kind: kind,
              categoryId: categoryId,
              productId: productId,
            ),
            const SizedBox(height: 20),
            Text(item.name, style: Theme.of(context).textTheme.headlineMedium),
            Text(
              money(item.priceCents),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (item.description != null) Text(item.description!),
            const SizedBox(height: 16),
            PelinesStateBadge(
              label: item.isAvailable ? 'Available' : 'Unavailable',
              foreground: item.isAvailable
                  ? PelinesColors.successForeground
                  : PelinesColors.destructive,
              background: item.isAvailable
                  ? PelinesColors.successBackground
                  : PelinesColors.brandPrimarySoft,
            ),
            const SizedBox(height: PelinesSpacing.md),
            _Field('Category', categoryName),
            _Field('Menu', kind.label),
            _Field('Location', location.name),
            _Field('Slug', item.slug),
            if (item.subcategory != null)
              _Field('Subcategory', item.subcategory!),
            if (item.servesCount != null)
              _Field('Serves', '${item.servesCount}'),
            if (item.disclaimer != null) _Field('Disclaimer', item.disclaimer!),
            _Field('Sort order', '${item.sortOrder}'),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Modifier Administration',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => context.push(
                    '/app/menu/${kind.name}/categories/$categoryId/products/$productId/modifiers/new',
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Group'),
                ),
              ],
            ),
            if (item.modifierGroups.isEmpty)
              const MenuEmpty('No modifier groups.'),
            for (final group in item.modifierGroups)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        group.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(_modifierRule(group)),
                      if (!group.optionsLoaded)
                        const Text('Options have not been loaded.'),
                      if (group.optionsLoaded && group.options.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No options in this group.'),
                        ),
                      for (final option in group.options)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(option.name),
                          subtitle: Text(
                            '${_signedMoney(option.priceDeltaCents)}${option.isDefault ? ' - Default' : ''}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Edit Option',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => context.push(
                              '/app/menu/${kind.name}/categories/$categoryId/products/$productId/modifiers/${group.id}/options/${option.id}/edit',
                            ),
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: () => context.push(
                              '/app/menu/${kind.name}/categories/$categoryId/products/$productId/modifiers/${group.id}/edit',
                            ),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit Group'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.push(
                              '/app/menu/${kind.name}/categories/$categoryId/products/$productId/modifiers/${group.id}/options/new',
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Option'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _modifierRule(MenuModifierGroup group) {
  if (!group.isFullyLoaded) return 'Modifier details have not been loaded.';
  final String requirement = group.isRequired == true ? 'Required' : 'Optional';
  if (group.minSelect == group.maxSelect) {
    return '$requirement - Choose ${group.maxSelect}';
  }
  return '$requirement - Choose ${group.minSelect}-${group.maxSelect}';
}

String _signedMoney(int cents) {
  if (cents == 0) return money(0);
  return '${cents > 0 ? '+' : '-'}${money(cents.abs())}';
}

class _ProductImageAdministration extends ConsumerWidget {
  const _ProductImageAdministration({
    required this.imageUrl,
    required this.locationId,
    required this.locationSlug,
    required this.kind,
    required this.categoryId,
    required this.productId,
  });
  final String? imageUrl;
  final String locationId;
  final String locationSlug;
  final MenuKind kind;
  final String categoryId;
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProductImageContext imageContext = (
      locationId: locationId,
      locationSlug: locationSlug,
      kind: kind,
      categoryId: categoryId,
      productId: productId,
    );
    final ProductImageState state = ref.watch(
      productImageMutationProvider(imageContext),
    );
    final String? stage = switch (state.phase) {
      ProductImagePhase.picking => 'Opening gallery...',
      ProductImagePhase.processing => 'Processing image...',
      ProductImagePhase.requestingUploadUrl => 'Preparing secure upload...',
      ProductImagePhase.uploading =>
        state.progress == null
            ? 'Uploading image...'
            : 'Uploading image... ${(state.progress! * 100).round()}%',
      ProductImagePhase.updatingProduct => 'Saving product...',
      ProductImagePhase.reconciling => 'Verifying product...',
      _ => null,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Product Image',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 12),
            _ProductImage(url: imageUrl, size: 180),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: state.isBusy
                  ? null
                  : () => ref
                        .read(
                          productImageMutationProvider(imageContext).notifier,
                        )
                        .changeImage(),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Change Image'),
            ),
            if (state.canRetryPatch)
              TextButton(
                onPressed: () => ref
                    .read(productImageMutationProvider(imageContext).notifier)
                    .retryProductUpdate(),
                child: const Text('Retry saving uploaded image'),
              ),
            if (stage != null) ...<Widget>[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Text(stage),
            ],
            if (!state.isBusy && state.message != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(state.message!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: PelinesLabelValueRow(
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      value: Text(value),
    ),
  );
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.url, required this.size});
  final String? url;
  final double size;
  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.image_not_supported_outlined),
    );
    final Uri? uri = url == null ? null : Uri.tryParse(url!);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return placeholder;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(PelinesRadius.card),
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

class _LocationHeader extends StatelessWidget {
  const _LocationHeader({required this.name, required this.onRefresh});
  final String name;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      PelinesSpacing.lg,
      PelinesSpacing.sm,
      PelinesSpacing.xs,
      PelinesSpacing.xxs,
    ),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: PelinesStateBadge(
              label: name,
              foreground: PelinesColors.brandPrimary,
              background: PelinesColors.brandPrimarySoft,
              icon: Icons.storefront_outlined,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
  );
}

class MenuEmpty extends StatelessWidget {
  const MenuEmpty(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(PelinesSpacing.xxl),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: PelinesColors.textSecondary,
          ),
          const SizedBox(height: PelinesSpacing.md),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class MenuError extends StatelessWidget {
  const MenuError({required this.message, required this.onRetry, super.key});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
