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

  Future<void> newItem(List<MenuCategory> categories) async {
    final selected = await showDialog<MenuCategory>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(tr(context, 'Category')),
        children: [
          for (final c in categories)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, c),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(c.name),
              ),
            ),
        ],
      ),
    );
    if (selected != null && mounted) {
      await context.push(
        '/app/menu/${widget.kind.name}/categories/${selected.id}/products/new?category=${Uri.encodeQueryComponent(selected.name)}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(currentLocationProvider);
    return Scaffold(
      appBar: AdminAppBar(title: Text(tr(context, widget.kind.label))),
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
                        const SectionLocationContext(),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            PelinesButton(
                              label: tr(context, 'New Category'),
                              onPressed: busy
                                  ? null
                                  : () => context.push(
                                      '/app/menu/${widget.kind.name}/categories/new',
                                    ),
                            ),
                            PelinesButton(
                              label: tr(context, 'New Item'),
                              onPressed: busy || data.categories.isEmpty
                                  ? null
                                  : () => newItem(data.categories),
                            ),
                            IconButton(
                              tooltip: tr(context, 'Refresh'),
                              onPressed: busy
                                  ? null
                                  : () {
                                      ref.invalidate(
                                        menuCategoriesProvider(query),
                                      );
                                      ref.invalidate(menuProductsProvider);
                                    },
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        PelinesFilterBar(
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
                                label: Text(c?.name ?? tr(context, 'All')),
                                selected: selected == c?.id,
                                selectedColor: PelinesColors.brandPrimary,
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  PelinesSectionHeading(category.name),
                                  const SizedBox(height: 8),
                                  MenuActions(
                                    children: [
                                      TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => context.push(
                                                '/app/menu/${widget.kind.name}/categories/${category.id}/edit',
                                              ),
                                        child: Text(
                                          tr(context, 'Edit Category'),
                                        ),
                                      ),
                                      CateringDeleteButton(
                                        query: query,
                                        categoryId: category.id,
                                        entity: CateringEntity.category,
                                        id: category.id,
                                        name: category.name,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
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
                                      product: p,
                                      category: category.name,
                                      catering:
                                          widget.kind == MenuKind.catering,
                                      onTap: () => context.push(
                                        '${productPath(p)}?category=${Uri.encodeQueryComponent(category.name)}',
                                      ),
                                      actions: MenuActions(
                                        key: ValueKey(
                                          '$prefix-product-actions-${p.id}',
                                        ),
                                        children: [
                                          TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => context.push(
                                                    '${productPath(p)}/edit?category=${Uri.encodeQueryComponent(category.name)}',
                                                  ),
                                            child: Text(tr(context, 'Edit')),
                                          ),
                                          TextButton(
                                            onPressed:
                                                busy ||
                                                    uncertainCopies.contains(
                                                      p.id,
                                                    )
                                                ? null
                                                : () => action(query, p, true),
                                            child: Text(
                                              tr(context, 'Duplicate'),
                                            ),
                                          ),
                                          TextButton(
                                            style: MenuActions.style(
                                              destructive: true,
                                            ),
                                            onPressed: busy
                                                ? null
                                                : () => action(query, p, false),
                                            child: Text(tr(context, 'Delete')),
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

class CateringDeleteButton extends ConsumerStatefulWidget {
  const CateringDeleteButton({
    required this.query,
    required this.categoryId,
    required this.entity,
    required this.id,
    required this.name,
    this.productId,
    this.groupId,
    super.key,
  });
  final CategoryQuery query;
  final String categoryId, id, name;
  final String? productId, groupId;
  final CateringEntity entity;
  @override
  ConsumerState<CateringDeleteButton> createState() =>
      _CateringDeleteButtonState();
}

class _CateringDeleteButtonState extends ConsumerState<CateringDeleteButton> {
  bool busy = false;
  Future<void> remove() async {
    if (busy) return;
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
    if (confirm != true || !mounted || busy) return;
    setState(() => busy = true);
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
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.entity == CateringEntity.option
      ? IconButton(
          key: ValueKey('catering-delete-${widget.id}'),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: tr(context, 'Delete'),
          onPressed: busy ? null : remove,
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
          style: widget.entity == CateringEntity.category
              ? MenuActions.style(destructive: true)
              : null,
          onPressed: busy ? null : remove,
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
