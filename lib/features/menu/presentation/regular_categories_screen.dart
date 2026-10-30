part of 'menu_screens.dart';

/// Category administration is independent of product search, filters and loads.
class RegularCategoriesScreen extends ConsumerWidget {
  const RegularCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(currentLocationProvider);
    final current = location.value;
    final CategoryQuery? query = current == null
        ? null
        : (
            locationId: current.id,
            locationSlug: current.slug,
            kind: MenuKind.store,
          );
    return AdminSectionScaffold(
      appBar: AdminAppBar(
        title: Text(tr(context, 'Categories')),
        leading: IconButton(
          tooltip: tr(context, 'Back'),
          onPressed: () => context.go('/app/menu/store'),
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
            kind: MenuKind.store,
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
                        key: const ValueKey('regular-new-category'),
                        label: tr(context, 'New Category'),
                        onPressed: () =>
                            context.push('/app/menu/store/categories/new'),
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
