part of 'menu_screens.dart';

final cateringCatalogProvider = FutureProvider.autoDispose
    .family<
      ({List<MenuCategory> categories, List<MenuProduct> products}),
      CategoryQuery
    >((ref, query) async {
      final categories = [
        ...await ref.watch(menuCategoriesProvider(query).future),
      ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final lists = await Future.wait([
        for (final category in categories)
          ref.watch(
            menuProductsProvider((
              locationId: query.locationId,
              locationSlug: query.locationSlug,
              categoryId: category.id,
            )).future,
          ),
      ]);
      return (
        categories: categories,
        products: lists.expand((p) => p).toList(),
      );
    });

int cateringNaturalCompare(String left, String right) {
  final parts = RegExp(r'\d+|\D+');
  final a = parts
      .allMatches(left.toLowerCase())
      .map((m) => m.group(0)!)
      .toList();
  final b = parts
      .allMatches(right.toLowerCase())
      .map((m) => m.group(0)!)
      .toList();
  for (var i = 0; i < a.length && i < b.length; i++) {
    final x = int.tryParse(a[i]), y = int.tryParse(b[i]);
    final comparison = x != null && y != null
        ? x.compareTo(y)
        : a[i].compareTo(b[i]);
    if (comparison != 0) return comparison;
  }
  return a.length.compareTo(b.length);
}

/// Shared catalog; kind scopes categories, routes and every mutation.
class MenuCatalogScreen extends ConsumerStatefulWidget {
  const MenuCatalogScreen({required this.kind, super.key});
  final MenuKind kind;
  @override
  ConsumerState<MenuCatalogScreen> createState() => _CateringCatalogState();
}

class _CateringCatalogState extends ConsumerState<MenuCatalogScreen> {
  String search = '';
  String? categoryId;
  bool busy = false;
  String? message;
  final Set<String> uncertainCopies = {};

  String get prefix =>
      widget.kind == MenuKind.catering ? 'catering' : 'regular';

  String productPath(MenuProduct p) =>
      '/app/menu/${widget.kind.name}/categories/${p.categoryId}/products/${p.id}';

  Future<void> action(
    CategoryQuery query,
    MenuProduct p,
    bool duplicate,
  ) async {
    if (busy || (duplicate && uncertainCopies.contains(p.id))) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, duplicate ? 'Duplicate' : 'Delete')),
        content: Text(p.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, duplicate ? 'Duplicate' : 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await validateCateringContext(ref, query, p.categoryId);
      final canonical = await ref.read(menuRepositoryProvider).getProduct(p.id);
      if (canonical.categoryId != p.categoryId) {
        throw const MenuContextChangedException();
      }
      if (duplicate) {
        await duplicateCateringProduct(
          ref.read(menuRepositoryProvider),
          canonical,
          kind: widget.kind,
        );
      } else {
        await ref
            .read(cateringDeleteProvider)
            .delete(CateringEntity.product, p.id);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          message = error is CateringCopyException && error.createdId != null
              ? '${tr(context, 'The copy may be incomplete. Review its modifiers before using it.')} (${error.createdId})'
              : tr(context, error.toString());
          if (error is CateringCopyException) uncertainCopies.add(p.id);
        });
      }
    } finally {
      if (mounted) {
        ref.invalidate(
          menuProductsProvider((
            locationId: query.locationId,
            locationSlug: query.locationSlug,
            categoryId: p.categoryId,
          )),
        );
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(currentLocationProvider);
    return AdminSectionScaffold(
      appBar: AdminAppBar(
        title: Text(tr(context, widget.kind.label)),
        actions: [
          if (!location.isLoading &&
              !location.hasError &&
              location.value != null)
            Consumer(
              builder: (context, ref, _) {
                final loc = location.value!;
                final query = (
                  locationId: loc.id,
                  locationSlug: loc.slug,
                  kind: widget.kind,
                );
                final catalog = ref.watch(cateringCatalogProvider(query));
                if (catalog.isLoading ||
                    catalog.hasError ||
                    catalog.value == null) {
                  return const SizedBox.shrink();
                }
                return AdminHeaderRefresh(
                  onPressed: busy
                      ? null
                      : () {
                          ref.invalidate(menuCategoriesProvider(query));
                          ref.invalidate(menuProductsProvider);
                        },
                );
              },
            ),
        ],
      ),
      body: location.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => MenuError(
          message: e.toString(),
          onRetry: () => ref.invalidate(currentLocationProvider),
        ),
        data: (loc) {
          if (loc == null) {
            return MenuEmpty(
              tr(context, 'Choose a location to view the menu.'),
            );
          }
          final query = (
            locationId: loc.id,
            locationSlug: loc.slug,
            kind: widget.kind,
          );
          final catalog = ref.watch(cateringCatalogProvider(query));
          return catalog.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => MenuError(
              message: e.toString(),
              onRetry: () {
                ref.invalidate(menuCategoriesProvider(query));
                ref.invalidate(menuProductsProvider);
                ref.invalidate(cateringCatalogProvider(query));
              },
            ),
            data: (data) {
              final selected = data.categories.any((c) => c.id == categoryId)
                  ? categoryId
                  : null;
              final needle = search.trim().toLowerCase();
              final visible = data.products
                  .where(
                    (p) =>
                        (selected == null || p.categoryId == selected) &&
                        [
                          p.name,
                          p.description ?? '',
                          p.subcategory ?? '',
                        ].join(' ').toLowerCase().contains(needle),
                  )
                  .toList();
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  PelinesPageBody(
                    width: PelinesPageWidth.dashboard,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          tr(
                            context,
                            widget.kind == MenuKind.catering
                                ? 'Manage catering categories, items, modifiers, photos, and availability.'
                                : 'Browse categories and products',
                          ),
                          key: const Key('menu-catalog-description'),
                          style: const TextStyle(
                            color: PelinesColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (widget.kind == MenuKind.catering)
                          Wrap(
                            spacing: PelinesSpacing.sm,
                            runSpacing: PelinesSpacing.sm,
                            children: [
                              PelinesButton(
                                label: tr(context, 'Categories'),
                                onPressed: busy
                                    ? null
                                    : () => context.push(
                                        '/app/menu/catering/categories',
                                      ),
                              ),
                              PelinesButton(
                                label: tr(context, 'New Item'),
                                onPressed: busy
                                    ? null
                                    : () => context.push(
                                        '/app/menu/catering/products/new',
                                      ),
                              ),
                            ],
                          )
                        else
                          Wrap(
                            spacing: PelinesSpacing.sm,
                            runSpacing: PelinesSpacing.sm,
                            children: [
                              PelinesButton(
                                label: tr(context, 'Categories'),
                                onPressed: busy
                                    ? null
                                    : () => context.push(
                                        '/app/menu/${widget.kind.name}/categories',
                                      ),
                              ),
                              PelinesButton(
                                label: tr(context, 'New Item'),
                                onPressed: busy
                                    ? null
                                    : () => context.push(
                                        '/app/menu/store/products/new',
                                      ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 16),
                        _CatalogFilters(
                          catering: widget.kind == MenuKind.catering,
                          search: PelinesInput(
                            key: ValueKey('$prefix-search'),
                            label: tr(
                              context,
                              widget.kind == MenuKind.catering
                                  ? 'Search catering items'
                                  : 'Search regular items',
                            ),
                            variant: PelinesInputVariant.search,
                            onChanged: (value) =>
                                setState(() => search = value),
                          ),
                          filters: [
                            for (final c in <MenuCategory?>[
                              null,
                              ...data.categories,
                            ])
                              ChoiceChip(
                                key: ValueKey(
                                  '$prefix-category-${c?.id ?? 'all'}',
                                ),
                                showCheckmark: false,
                                label: Text(c?.name ?? tr(context, 'All')),
                                selected: selected == c?.id,
                                selectedColor: PelinesColors.brandPrimary,
                                backgroundColor: PelinesColors.card,
                                shape: const StadiumBorder(),
                                side: BorderSide(
                                  color: selected == c?.id
                                      ? PelinesColors.brandPrimary
                                      : PelinesColors.border,
                                ),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.padded,
                                labelPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                labelStyle: TextStyle(
                                  color: selected == c?.id
                                      ? Colors.white
                                      : PelinesColors.textPrimary,
                                ),
                                onSelected: (_) =>
                                    setState(() => categoryId = c?.id),
                              ),
                          ],
                        ),
                        if (busy) const LinearProgressIndicator(),
                        if (message != null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(message!),
                          ),
                        if (visible.isEmpty)
                          MenuEmpty(
                            tr(
                              context,
                              data.products.isEmpty
                                  ? 'No products in this category.'
                                  : 'No products match your search.',
                            ),
                          ),
                        for (final category in data.categories)
                          if (selected == null || selected == category.id) ...[
                            const SizedBox(height: 24),
                            PelinesCard(
                              key: ValueKey(
                                '$prefix-category-header-${category.id}',
                              ),
                              variant: PelinesCardVariant.compact,
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (widget.kind == MenuKind.catering)
                                    Text(
                                      category.name,
                                      style:
                                          PelinesTypography.pageTitle(
                                            Theme.of(context).textTheme,
                                          )?.copyWith(
                                            color: PelinesColors.brandPrimary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    )
                                  else
                                    Text(
                                      category.name,
                                      style:
                                          PelinesTypography.pageTitle(
                                            Theme.of(context).textTheme,
                                          )?.copyWith(
                                            color: PelinesColors.brandPrimary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: PelinesSpacing.md),
                            for (final sub
                                in visible
                                    .where((p) => p.categoryId == category.id)
                                    .map((p) => p.subcategory?.trim() ?? '')
                                    .toSet()) ...[
                              if (sub.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    sub,
                                    style: PelinesTypography.smallLabel,
                                  ),
                                ),
                              MenuCardGrid(
                                children: [
                                  for (final p
                                      in (visible
                                          .where(
                                            (p) =>
                                                p.categoryId == category.id &&
                                                (p.subcategory?.trim() ?? '') ==
                                                    sub,
                                          )
                                          .toList()
                                        ..sort(
                                          (a, b) => cateringNaturalCompare(
                                            a.name,
                                            b.name,
                                          ),
                                        )))
                                    _ProductTile(
                                      catalogCard: true,
                                      product: p,
                                      category: category.name,
                                      catering:
                                          widget.kind == MenuKind.catering,
                                      onTap: () => context.push(
                                        '${productPath(p)}?category=${Uri.encodeQueryComponent(category.name)}',
                                      ),
                                      onEdit: busy
                                          ? null
                                          : () => context.push(
                                              '${productPath(p)}/edit?category=${Uri.encodeQueryComponent(category.name)}',
                                            ),
                                      actions: MenuActions(
                                        key: ValueKey(
                                          '$prefix-product-actions-${p.id}',
                                        ),
                                        children: [
                                          _CatalogProductAction(
                                            catering: true,
                                            compact: true,
                                            label: tr(context, 'Duplicate'),
                                            icon: Icons.copy_outlined,
                                            onPressed:
                                                busy ||
                                                    uncertainCopies.contains(
                                                      p.id,
                                                    )
                                                ? null
                                                : () => action(query, p, true),
                                          ),
                                          _CatalogProductAction(
                                            catering: true,
                                            compact: true,
                                            label: tr(context, 'Delete'),
                                            icon: Icons.delete_outline,
                                            destructive: true,
                                            onPressed: busy
                                                ? null
                                                : () => action(query, p, false),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Both menu kinds use the same wrapping controls at every viewport.
class _CatalogFilters extends StatelessWidget {
  const _CatalogFilters({
    required this.catering,
    required this.search,
    required this.filters,
  });
  final bool catering;
  final Widget search;
  final List<Widget> filters;
  @override
  Widget build(BuildContext context) => PelinesCard(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        search,
        const SizedBox(height: 12),
        Wrap(
          key: Key(
            catering ? 'catering-category-wrap' : 'regular-category-wrap',
          ),
          alignment: WrapAlignment.start,
          spacing: 8,
          runSpacing: 8,
          children: filters,
        ),
      ],
    ),
  );
}

class _CatalogProductAction extends StatelessWidget {
  const _CatalogProductAction({
    required this.catering,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.compact = false,
    this.destructive = false,
  });
  final bool catering, destructive, compact;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  static ButtonStyle style({
    bool filled = false,
    bool destructive = false,
    Color? backgroundColor,
  }) => TextButton.styleFrom(
    minimumSize: const Size(48, 48),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    foregroundColor: destructive
        ? PelinesColors.destructive
        : PelinesColors.textPrimary,
    backgroundColor: filled ? PelinesColors.mutedSurface : backgroundColor,
    side: BorderSide(
      color: destructive
          ? PelinesColors.destructive
          : PelinesColors.textSecondary,
    ),
    shape: const StadiumBorder(),
  );

  @override
  Widget build(BuildContext context) {
    if (catering && compact) {
      return IconButton(
        tooltip: label,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        color: destructive
            ? PelinesColors.destructive
            : PelinesColors.textSecondary,
        onPressed: onPressed,
        icon: Icon(icon),
      );
    }
    return TextButton.icon(
      style: style(destructive: destructive),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class CateringDeleteButton extends ConsumerStatefulWidget {
  const CateringDeleteButton({
    required this.query,
    required this.categoryId,
    required this.entity,
    required this.id,
    required this.name,
    this.productId,
    this.groupId,
    this.onBusyChanged,
    this.onSettled,
    this.compact = false,
    this.enabled = true,
    super.key,
  });
  final bool enabled;
  final bool compact;
  final CategoryQuery query;
  final String categoryId, id, name;
  final String? productId, groupId;
  final CateringEntity entity;
  final ValueChanged<bool>? onBusyChanged;
  final VoidCallback? onSettled;
  @override
  ConsumerState<CateringDeleteButton> createState() =>
      _CateringDeleteButtonState();
}

class _CateringDeleteButtonState extends ConsumerState<CateringDeleteButton> {
  bool busy = false;
  Future<void> remove() async {
    if (busy || !widget.enabled) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'Delete')),
        content: Text(widget.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Delete')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted || busy || !widget.enabled) return;
    setState(() => busy = true);
    widget.onBusyChanged?.call(true);
    try {
      await validateCateringContext(ref, widget.query, widget.categoryId);
      if (widget.productId != null) {
        final p = await ref
            .read(menuRepositoryProvider)
            .getProduct(widget.productId!);
        if (p.categoryId != widget.categoryId) {
          throw const MenuContextChangedException();
        }
        final groups = await ref
            .read(menuRepositoryProvider)
            .getModifierGroups(p.id);
        final valid = widget.entity == CateringEntity.group
            ? groups.any((g) => g.id == widget.id && g.productId == p.id)
            : groups.any(
                (g) =>
                    g.id == widget.groupId &&
                    g.productId == p.id &&
                    g.options.any(
                      (o) => o.id == widget.id && o.groupId == g.id,
                    ),
              );
        if (!valid) throw const MenuContextChangedException();
      }
      await ref.read(cateringDeleteProvider).delete(widget.entity, widget.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) {
        ref.invalidate(menuCategoriesProvider(widget.query));
        ref.invalidate(menuProductsProvider);
        if (widget.productId != null) {
          ref.invalidate(
            menuProductDetailProvider((
              locationId: widget.query.locationId,
              categoryId: widget.categoryId,
              productId: widget.productId!,
            )),
          );
        }
        setState(() => busy = false);
        widget.onBusyChanged?.call(false);
        widget.onSettled?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      (widget.entity == CateringEntity.option || widget.compact)
      ? IconButton(
          key: ValueKey('catering-delete-${widget.id}'),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: tr(context, 'Delete'),
          onPressed: busy || !widget.enabled ? null : remove,
          icon: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(),
                )
              : const Icon(Icons.delete_outline),
        )
      : TextButton.icon(
          key: ValueKey('catering-delete-${widget.id}'),
          style: _CatalogProductAction.style(
            destructive: true,
            backgroundColor: PelinesColors.card,
          ),
          onPressed: busy || !widget.enabled ? null : remove,
          icon: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(),
                )
              : const Icon(Icons.delete_outline),
          label: Text(tr(context, 'Delete')),
        );
}
