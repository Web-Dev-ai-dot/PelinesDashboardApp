import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../../orders/presentation/order_ui_helpers.dart';
import '../models/menu_models.dart';
import '../providers/menu_providers.dart';
import '../providers/product_image_providers.dart';
import '../../../app/theme/app_theme.dart';
import 'menu_parity_widgets.dart';
import '../providers/catering_actions.dart';

part 'catering_catalog.dart';

class MenuLandingScreen extends StatelessWidget {
  const MenuLandingScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AdminAppBar(
      title: Text(
        tr(context, 'Menu'),
        style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(PelinesSpacing.md),
      children: <Widget>[
        PelinesSectionHeading(tr(context, 'Choose a menu')),
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
      title: Text(tr(context, kind.label)),
      subtitle: Text(tr(context, 'Browse categories and products')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/app/menu/${kind.name}'),
    ),
  );
}

class MenuCategoriesScreen extends StatelessWidget {
  const MenuCategoriesScreen({required this.kind, super.key});
  final MenuKind kind;
  @override
  Widget build(BuildContext context) =>
      MenuCatalogScreen(key: ValueKey(kind), kind: kind);
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
      appBar: AdminAppBar(
        title: Text(
          categoryName,
          style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
        ),
      ),
      body: location.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => MenuError(
          message: error.toString(),
          onRetry: () => ref.invalidate(currentLocationProvider),
        ),
        data: (Location? value) {
          if (value == null) {
            return MenuEmpty(
              tr(context, 'Choose a location to view products.'),
            );
          }
          final ProductQuery query = (
            locationId: value.id,
            locationSlug: value.slug,
            categoryId: categoryId,
          );
          final products = ref.watch(menuProductsProvider(query));
          return Column(
            children: [
              _LocationHeader(
                name: value.name,
                onRefresh: () => ref.invalidate(menuProductsProvider(query)),
                action: PelinesButton(
                  key: const Key('menu-new-product'),
                  label: tr(context, 'New Item'),
                  onPressed: () => context.push(
                    '/app/menu/${kind.name}/categories/$categoryId/products/new?category=${Uri.encodeQueryComponent(categoryName)}',
                  ),
                ),
              ),
              Expanded(
                child: products.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => MenuError(
                    message: error.toString(),
                    onRetry: () => ref.invalidate(menuProductsProvider(query)),
                  ),
                  data: (items) => RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(menuProductsProvider(query));
                      await ref.read(menuProductsProvider(query).future);
                    },
                    child: _ProductsCatalog(
                      items: items,
                      categoryName: categoryName,
                      onOpen: (item) => context.push(
                        '/app/menu/${kind.name}/categories/$categoryId/products/${item.id}?category=${Uri.encodeQueryComponent(categoryName)}',
                      ),
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

class _ProductsCatalog extends StatefulWidget {
  const _ProductsCatalog({
    required this.items,
    required this.categoryName,
    required this.onOpen,
  });
  final List<MenuProduct> items;
  final String categoryName;
  final ValueChanged<MenuProduct> onOpen;
  @override
  State<_ProductsCatalog> createState() => _ProductsCatalogState();
}

class _ProductsCatalogState extends State<_ProductsCatalog> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final visible = widget.items
        .where(
          (p) => [
            p.name,
            p.description ?? '',
            p.subcategory ?? '',
          ].join(' ').toLowerCase().contains(needle),
        )
        .toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        PelinesPageBody(
          width: PelinesPageWidth.dashboard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PelinesFilterBar(
                search: PelinesInput(
                  key: const Key('menu-product-search'),
                  label: tr(context, 'Search products'),
                  variant: PelinesInputVariant.search,
                  onChanged: (value) => setState(() => query = value),
                ),
                filters: [
                  Semantics(
                    selected: true,
                    child: PelinesStateBadge(
                      key: const Key('menu-active-category'),
                      label: widget.categoryName,
                      foreground: PelinesColors.card,
                      background: PelinesColors.brandPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (visible.isEmpty)
                MenuEmpty(
                  tr(
                    context,
                    widget.items.isEmpty
                        ? 'No products in this category.'
                        : 'No products match your search.',
                  ),
                )
              else
                MenuCardGrid(
                  children: [
                    for (final item in visible)
                      _ProductTile(
                        product: item,
                        category: widget.categoryName,
                        onTap: () => widget.onOpen(item),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.category,
    required this.onTap,
    this.catering = false,
    this.actions,
  });
  final MenuProduct product;
  final String category;
  final VoidCallback onTap;
  final bool catering;
  final Widget? actions;
  @override
  Widget build(BuildContext context) => PelinesCard(
    key: ValueKey('menu-product-${product.id}'),
    padding: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MenuPhoto(url: product.imageUrl),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PelinesLabelValueRow(
                  label: Text(
                    product.name,
                    style: PelinesTypography.sectionTitle(
                      Theme.of(context).textTheme,
                    )?.copyWith(fontSize: 24),
                  ),
                  value: Text(
                    money(product.priceCents),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    category,
                    if (product.subcategory?.isNotEmpty == true)
                      product.subcategory!,
                  ].join(' · '),
                  style: PelinesTypography.smallLabel,
                ),
                if (product.description?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Text(
                    product.description!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PelinesColors.textSecondary),
                  ),
                ],
                const Divider(height: 32),
                if (catering && product.servesCount != null)
                  Text('${tr(context, 'Serves')}: ${product.servesCount}'),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: PelinesStateBadge(
                    label: tr(
                      context,
                      product.isAvailable ? 'Available' : 'Unavailable',
                    ),
                    foreground: product.isAvailable
                        ? PelinesColors.successForeground
                        : PelinesColors.textSecondary,
                    background: product.isAvailable
                        ? PelinesColors.successBackground
                        : PelinesColors.mutedSurface,
                  ),
                ),
                const SizedBox(height: 12),
                PelinesButton(
                  label: tr(context, 'View'),
                  variant: PelinesButtonVariant.secondary,
                  onPressed: onTap,
                ),
                if (actions != null) ...[const Divider(height: 24), actions!],
              ],
            ),
          ),
        ],
      ),
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
      return Scaffold(
        body: MenuEmpty(tr(context, 'Choose a location to view this product.')),
      );
    }
    final ProductDetailQuery query = (
      locationId: location.id,
      categoryId: categoryId,
      productId: productId,
    );
    final product = ref.watch(menuProductDetailProvider(query));
    return Scaffold(
      appBar: AdminAppBar(
        title: Text(
          tr(context, 'Product Detail'),
          style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: tr(context, 'Edit Product'),
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
        data: (item) => MenuFormList(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            ProductImageAdministration(
              imageUrl: item.imageUrl,
              locationId: location.id,
              locationSlug: location.slug,
              kind: kind,
              categoryId: categoryId,
              productId: productId,
            ),
            const SizedBox(height: 20),
            Text(
              item.name,
              style: PelinesTypography.pageTitle(Theme.of(context).textTheme)
                  ?.copyWith(fontSize: 32),
            ),
            Text(
              money(item.priceCents),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (item.description != null) Text(item.description!),
            const SizedBox(height: 16),
            PelinesStateBadge(
              label: item.isAvailable
                  ? tr(context, 'Available')
                  : tr(context, 'Unavailable'),
              foreground: item.isAvailable
                  ? PelinesColors.successForeground
                  : PelinesColors.destructive,
              background: item.isAvailable
                  ? PelinesColors.successBackground
                  : PelinesColors.brandPrimarySoft,
            ),
            const SizedBox(height: PelinesSpacing.md),
            _Field(tr(context, 'Category'), categoryName),
            _Field(tr(context, 'Menu'), tr(context, kind.label)),
            _Field(tr(context, 'Location'), location.name),
            _Field(tr(context, 'Slug'), item.slug),
            if (item.subcategory != null)
              _Field(tr(context, 'Subcategory'), item.subcategory!),
            if (kind == MenuKind.catering && item.servesCount != null)
              _Field(tr(context, 'Serves'), '${item.servesCount}'),
            if (item.disclaimer != null)
              _Field(tr(context, 'Disclaimer'), item.disclaimer!),
            _Field(tr(context, 'Sort order'), '${item.sortOrder}'),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  tr(context, 'Modifiers'),
                  style: PelinesTypography.sectionTitle(
                    Theme.of(context).textTheme,
                  )?.copyWith(fontSize: 26),
                ),
                FilledButton.icon(
                  style: PelinesControlStyles.button(
                    PelinesButtonVariant.primary,
                  ),
                  onPressed: () => context.push(
                    '/app/menu/${kind.name}/categories/$categoryId/products/$productId/modifiers/new',
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(tr(context, 'Add Group')),
                ),
              ],
            ),
            if (item.modifierGroups.isEmpty)
              MenuEmpty(tr(context, 'No modifier groups.')),
            for (final group in item.modifierGroups)
              PelinesCard(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        group.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(_modifierRule(context, group)),
                      if (!group.optionsLoaded)
                        Text(tr(context, 'Options have not been loaded.')),
                      if (group.optionsLoaded && group.options.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(tr(context, 'No options in this group.')),
                        ),
                      for (final option in group.options)
                        Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(option.name),
                            subtitle: Text(
                              '${_signedMoney(option.priceDeltaCents)}${option.isDefault ? ' - ${tr(context, 'Default option')}' : ''}',
                            ),
                            leading: CateringDeleteButton(
                              query: (
                                locationId: location.id,
                                locationSlug: location.slug,
                                kind: kind,
                              ),
                              categoryId: categoryId,
                              entity: CateringEntity.option,
                              id: option.id,
                              name: option.name,
                              productId: productId,
                              groupId: group.id,
                            ),
                            trailing: IconButton(
                              tooltip: tr(context, 'Edit Option'),
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => context.push(
                                '/app/menu/${kind.name}/categories/$categoryId/products/$productId/modifiers/${group.id}/options/${option.id}/edit',
                              ),
                            ),
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        children: <Widget>[
                          CateringDeleteButton(
                            query: (
                              locationId: location.id,
                              locationSlug: location.slug,
                              kind: kind,
                            ),
                            categoryId: categoryId,
                            entity: CateringEntity.group,
                            id: group.id,
                            name: group.name,
                            productId: productId,
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.push(
                              '/app/menu/${kind.name}/categories/$categoryId/products/$productId/modifiers/${group.id}/edit',
                            ),
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(tr(context, 'Edit Group')),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.push(
                              '/app/menu/${kind.name}/categories/$categoryId/products/$productId/modifiers/${group.id}/options/new',
                            ),
                            icon: const Icon(Icons.add),
                            label: Text(tr(context, 'Add Option')),
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

String _modifierRule(BuildContext context, MenuModifierGroup group) {
  if (!group.isFullyLoaded) {
    return tr(context, 'Modifier details have not been loaded.');
  }
  final String requirement = tr(
    context,
    group.isRequired == true ? 'Required' : 'Optional',
  );
  if (group.minSelect == group.maxSelect) {
    return '$requirement - ${tr(context, 'Choose')} ${group.maxSelect}';
  }
  return '$requirement - ${tr(context, 'Choose')} ${group.minSelect}-${group.maxSelect}';
}

String _signedMoney(int cents) {
  if (cents == 0) return money(0);
  return '${cents > 0 ? '+' : '-'}${money(cents.abs())}';
}

class ProductImageAdministration extends ConsumerWidget {
  const ProductImageAdministration({
    required this.imageUrl,
    required this.locationId,
    required this.locationSlug,
    required this.kind,
    required this.categoryId,
    required this.productId,
    super.key,
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
      ProductImagePhase.picking => tr(context, 'Opening gallery...'),
      ProductImagePhase.processing => tr(context, 'Processing image...'),
      ProductImagePhase.requestingUploadUrl => tr(
        context,
        'Preparing secure upload...',
      ),
      ProductImagePhase.uploading =>
        state.progress == null
            ? tr(context, 'Uploading image...')
            : 'Uploading image... ${(state.progress! * 100).round()}%',
      ProductImagePhase.updatingProduct => tr(context, 'Saving product...'),
      ProductImagePhase.reconciling => tr(context, 'Verifying product...'),
      _ => null,
    };
    return PelinesCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr(
                  context,
                  kind == MenuKind.catering ? 'Photo' : 'Product Image',
                ),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 12),
            MenuPhoto(url: imageUrl, height: 220),
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
              label: Text(
                tr(
                  context,
                  kind == MenuKind.catering ? 'Replace Photo' : 'Change Image',
                ),
              ),
            ),
            if (state.canRetryPatch)
              TextButton(
                onPressed: () => ref
                    .read(productImageMutationProvider(imageContext).notifier)
                    .retryProductUpdate(),
                child: Text(tr(context, 'Retry saving uploaded image')),
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

class _LocationHeader extends StatelessWidget {
  const _LocationHeader({
    required this.name,
    required this.onRefresh,
    this.action,
  });
  final Widget? action;
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
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PelinesStateBadge(
          label: name,
          foreground: PelinesColors.brandPrimary,
          background: PelinesColors.brandPrimarySoft,
          icon: Icons.storefront_outlined,
        ),
        ?action,
        IconButton(
          tooltip: tr(context, 'Refresh'),
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
          FilledButton(
            onPressed: onRetry,
            child: Text(tr(context, 'Try again')),
          ),
        ],
      ),
    ),
  );
}
