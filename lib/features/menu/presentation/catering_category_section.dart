part of 'menu_screens.dart';

/// Uses the catalog's complete, location-scoped category list, not product filters.
class _CateringCategorySection extends StatelessWidget {
  const _CateringCategorySection({
    required this.query,
    required this.categories,
    this.showHeading = true,
  });
  final bool showHeading;
  final CategoryQuery query;
  final List<MenuCategory> categories;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('catering-categories-section'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showHeading) ...[
        PelinesSectionHeading(tr(context, 'Categories')),
        const SizedBox(height: PelinesSpacing.xs),
      ],
      Text(
        tr(context, 'Reorder, rename, and toggle category visibility.'),
        style: const TextStyle(color: PelinesColors.textSecondary),
      ),
      const SizedBox(height: PelinesSpacing.md),
      LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >=
              720 * MediaQuery.textScalerOf(context).scale(1);
          return PelinesCard(
            padding: EdgeInsets.zero,
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  if (wide)
                    Padding(
                      padding: const EdgeInsets.all(PelinesSpacing.md),
                      child: _categoryColumns([
                        _columnLabel(context, 'Display order'),
                        _columnLabel(context, 'Category'),
                        _columnLabel(context, 'Active'),
                        _columnLabel(context, 'Actions'),
                      ]),
                    ),
                  if (categories.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(PelinesSpacing.lg),
                      child: Text(tr(context, 'No categories yet.')),
                    ),
                  for (var i = 0; i < categories.length; i++) ...[
                    if (i > 0 || wide) const Divider(height: 1),
                    _CateringCategoryRow(
                      key: ValueKey(
                        'catering-category-row-${query.locationId}-${categories[i].id}',
                      ),
                      query: query,
                      category: categories[i],
                      wide: wide,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    ],
  );

  Widget _columnLabel(BuildContext context, String value) => Text(
    tr(context, value).toUpperCase(),
    style: PelinesTypography.smallLabel.copyWith(
      color: PelinesColors.textSecondary,
    ),
  );
}

Widget _categoryColumns(List<Widget> cells) => Row(
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    SizedBox(width: 72, child: cells[0]),
    Expanded(child: cells[1]),
    const SizedBox(width: PelinesSpacing.md),
    SizedBox(width: 172, child: cells[2]),
    SizedBox(width: 112, child: cells[3]),
  ],
);

class _CateringCategoryRow extends ConsumerStatefulWidget {
  const _CateringCategoryRow({
    required this.query,
    required this.category,
    required this.wide,
    super.key,
  });
  final CategoryQuery query;
  final MenuCategory category;
  final bool wide;
  @override
  ConsumerState<_CateringCategoryRow> createState() =>
      _CateringCategoryRowState();
}

class _CateringCategoryRowState extends ConsumerState<_CateringCategoryRow> {
  bool changing = false;
  bool deleting = false;
  String? error;

  Future<void> toggle(bool next) async {
    if (changing || deleting) return;
    setState(() {
      changing = true;
      error = null;
    });
    try {
      // Preserve current name/order, rather than resubmitting a stale catalog row.
      final current = await ref
          .read(menuRepositoryProvider)
          .getCategory(widget.category.id);
      if (!mounted) return;
      final query = widget.query;
      if (current.id != widget.category.id ||
          current.locationId != query.locationId ||
          current.kind != query.kind) {
        throw const MenuContextChangedException();
      }
      final key = (
        locationId: query.locationId,
        locationSlug: query.locationSlug,
        kind: query.kind,
        categoryId: widget.category.id,
      );
      final saved = await ref
          .read(categoryMutationProvider(key).notifier)
          .save(
            CategoryWriteInput(
              locationId: query.locationId,
              kind: query.kind,
              name: current.name,
              sortOrder: current.sortOrder,
              isActive: next,
            ),
          );
      if (!saved && mounted) {
        setState(
          () => error =
              ref.read(categoryMutationProvider(key)).message ??
              'The category could not be saved.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => error = 'The category could not be saved.');
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final key = (
      locationId: widget.query.locationId,
      locationSlug: widget.query.locationSlug,
      kind: widget.query.kind,
      categoryId: category.id,
    );
    final mutation = ref.watch(categoryMutationProvider(key));
    final busy = changing || deleting || mutation.isBusy;
    final name = Text(
      category.name,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w600),
    );
    final order = Text(
      widget.wide
          ? '${category.sortOrder}'
          : '${tr(context, 'Display order')}: ${category.sortOrder}',
    );
    final active = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          key: ValueKey('category-active-${category.id}'),
          value: category.isActive,
          activeColor: PelinesColors.brandPrimary,
          checkColor: Colors.white,
          side: WidgetStateBorderSide.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.selected)
                  ? PelinesColors.brandPrimary
                  : PelinesColors.border,
            ),
          ),
          semanticLabel:
              '${category.name}: ${tr(context, category.isActive ? 'Active' : 'Inactive')}',
          onChanged: busy ? null : (value) => toggle(value!),
        ),
        Flexible(
          child: Text(tr(context, category.isActive ? 'Active' : 'Inactive')),
        ),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey('category-edit-${category.id}'),
          tooltip: tr(context, 'Edit'),
          color: PelinesColors.textSecondary,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: busy
              ? null
              : () => showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => CategoryFormScreen(
                    kind: widget.query.kind,
                    categoryId: category.id,
                    modal: true,
                  ),
                ),
          icon: const Icon(Icons.edit_outlined),
        ),
        CateringDeleteButton(
          enabled: !changing && !mutation.isBusy,
          query: widget.query,
          categoryId: category.id,
          entity: CateringEntity.category,
          id: category.id,
          name: category.name,
          compact: true,
          onBusyChanged: (value) {
            if (mounted) setState(() => deleting = value);
          },
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(PelinesSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.wide)
            _categoryColumns([order, name, active, actions])
          else ...[
            name,
            const SizedBox(height: PelinesSpacing.xs),
            order,
            const SizedBox(height: PelinesSpacing.xs),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: PelinesSpacing.sm,
              runSpacing: PelinesSpacing.xs,
              children: [active, actions],
            ),
          ],
          if (changing) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: PelinesSpacing.xs),
              child: Text(
                tr(context, error!),
                style: const TextStyle(color: PelinesColors.destructive),
              ),
            ),
        ],
      ),
    );
  }
}

/// Category administration is independent of product search, filters and loads.
class CateringCategoriesScreen extends ConsumerWidget {
  const CateringCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(currentLocationProvider);
    final current = location.value;
    final CategoryQuery? query = current == null
        ? null
        : (
            locationId: current.id,
            locationSlug: current.slug,
            kind: MenuKind.catering,
          );
    return AdminSectionScaffold(
      appBar: AdminAppBar(
        title: Text(tr(context, 'Categories')),
        leading: IconButton(
          tooltip: tr(context, 'Back'),
          onPressed: () => context.go('/app/menu/catering'),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          if (query != null && !location.isLoading && !location.hasError) ...[
            AdminHeaderRefresh(
              onPressed: () => ref.invalidate(menuCategoriesProvider(query)),
            ),
          ],
        ],
      ),
      body: location.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => MenuError(
          message: error.toString(),
          onRetry: () => ref.invalidate(currentLocationProvider),
        ),
        data: (current) {
          if (current == null) {
            return MenuEmpty(
              tr(context, 'Choose a location to view the menu.'),
            );
          }
          final query = (
            locationId: current.id,
            locationSlug: current.slug,
            kind: MenuKind.catering,
          );
          return ListView(
            padding: const EdgeInsets.all(PelinesSpacing.md),
            children: [
              PelinesPageBody(
                width: PelinesPageWidth.dashboard,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PelinesButton(
                        key: const ValueKey('catering-new-category'),
                        label: tr(context, 'New Category'),
                        onPressed: () =>
                            context.push('/app/menu/catering/categories/new'),
                      ),
                    ),
                    const SizedBox(height: PelinesSpacing.md),
                    ref
                        .watch(menuCategoriesProvider(query))
                        .when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, _) => MenuError(
                            message: error.toString(),
                            onRetry: () =>
                                ref.invalidate(menuCategoriesProvider(query)),
                          ),
                          data: (categories) {
                            final ordered = [...categories]
                              ..sort(
                                (a, b) => a.sortOrder.compareTo(b.sortOrder),
                              );
                            return _CateringCategorySection(
                              query: query,
                              categories: ordered,
                              showHeading: false,
                            );
                          },
                        ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
