part of 'product_form_screen.dart';

/// Shared creation presentation; kind still scopes data and persistence.
class NewMenuItemPage extends Page<void> {
  const NewMenuItemPage({
    required this.categoryId,
    required this.categoryName,
    this.kind = MenuKind.store,
    super.key,
  });
  final String categoryId, categoryName;
  final MenuKind kind;

  @override
  Route<void> createRoute(BuildContext context) {
    Widget form(bool sheet) => ProductFormScreen(
      kind: kind,
      categoryId: categoryId,
      categoryName: categoryName,
      sheet: sheet,
    );
    if (MediaQuery.sizeOf(context).width < PelinesLayout.compactWidth) {
      return ModalBottomSheetRoute<void>(
        settings: this,
        builder: (_) => form(true),
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: PelinesColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(PelinesRadius.dialog),
          ),
        ),
      );
    }
    return DialogRoute<void>(
      settings: this,
      context: context,
      barrierDismissible: false,
      builder: (_) => form(false),
    );
  }
}

extension _NewMenuItemPresentation on _FormState {
  Widget buildNewMenuItem(
    ProductMutationKey key,
    ProductMutationState mutation,
  ) {
    final busy = savingNewItem || mutation.isBusy;
    final errorMessage =
        newSaveError ??
        (mutation.phase == ProductMutationPhase.error
            ? mutation.message
            : null);
    final content = AdminPopScope(
      canPop: !anyDirty && !busy,
      onPopInvokedWithResult: (popped, result) async {
        if (!popped && !busy) await _leave();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(PelinesSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr(context, 'New menu item'),
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: tr(context, 'Close'),
                  onPressed: busy ? null : _leave,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PelinesSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _newField(
                      name,
                      'Name',
                      'name',
                      busy,
                      hint: 'e.g. Chicken Quesadilla',
                      maxLength: 120,
                    ),
                    _newLabel('Category'),
                    ref
                        .watch(
                          menuCategoriesProvider((
                            locationId: widget.location.id,
                            locationSlug: widget.location.slug,
                            kind: widget.kind,
                          )),
                        )
                        .when(
                          loading: () => const LinearProgressIndicator(),
                          error: (error, _) => MenuError(
                            message: tr(
                              context,
                              'Categories could not be loaded.',
                            ),
                            onRetry: () => ref.invalidate(
                              menuCategoriesProvider((
                                locationId: widget.location.id,
                                locationSlug: widget.location.slug,
                                kind: widget.kind,
                              )),
                            ),
                          ),
                          data: (categories) => Semantics(
                            label: tr(context, 'Category'),
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(
                                '${widget.kind.name}-edit-category-$selectedCategoryId',
                              ),
                              initialValue:
                                  categories.any(
                                    (c) => c.id == selectedCategoryId,
                                  )
                                  ? selectedCategoryId
                                  : null,
                              isExpanded: true,
                              itemHeight: null,
                              hint: widget.kind == MenuKind.catering
                                  ? Text(tr(context, 'Select a category'))
                                  : null,
                              selectedItemBuilder: (context) => [
                                for (final c in categories)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      c.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              decoration: PelinesControlStyles.input(),
                              items: [
                                for (final c in categories)
                                  DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name),
                                  ),
                              ],
                              onChanged: busy
                                  ? null
                                  : (id) {
                                      if (id != null) changeNewCategory(id);
                                    },
                            ),
                          ),
                        ),
                    const SizedBox(height: PelinesSpacing.md),
                    _newLabel('Subcategory (Optional)'),
                    if (selectedCategoryId.isEmpty)
                      Text(tr(context, 'Select a category before saving.'))
                    else
                      ref
                          .watch(
                            menuProductsProvider((
                              locationId: widget.location.id,
                              locationSlug: widget.location.slug,
                              categoryId: selectedCategoryId,
                            )),
                          )
                          .when(
                            loading: () => const LinearProgressIndicator(),
                            error: (error, _) => MenuError(
                              message: tr(
                                context,
                                'Subcategories could not be loaded.',
                              ),
                              onRetry: () => ref.invalidate(
                                menuProductsProvider((
                                  locationId: widget.location.id,
                                  locationSlug: widget.location.slug,
                                  categoryId: selectedCategoryId,
                                )),
                              ),
                            ),
                            data: (products) {
                              final labels =
                                  products
                                      .map((p) => p.subcategory?.trim() ?? '')
                                      .where((s) => s.isNotEmpty)
                                      .toSet()
                                      .toList()
                                    ..sort();
                              return Semantics(
                                label: tr(context, 'Subcategory (Optional)'),
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey(
                                    '${widget.kind.name}-subcategory-$selectedCategoryId-${subcategory.text}',
                                  ),
                                  initialValue:
                                      labels.contains(subcategory.text)
                                      ? subcategory.text
                                      : '',
                                  isExpanded: true,
                                  itemHeight: null,
                                  selectedItemBuilder: (context) => [
                                    for (final label in ['', ...labels])
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          label.isEmpty
                                              ? tr(context, 'None')
                                              : label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  decoration: PelinesControlStyles.input(),
                                  items: [
                                    DropdownMenuItem(
                                      value: '',
                                      child: Text(tr(context, 'None')),
                                    ),
                                    for (final label in labels)
                                      DropdownMenuItem(
                                        value: label,
                                        child: Text(label),
                                      ),
                                  ],
                                  onChanged: busy
                                      ? null
                                      : (value) {
                                          if (value != null) {
                                            subcategory.text = value;
                                          }
                                        },
                                ),
                              );
                            },
                          ),
                    const SizedBox(height: PelinesSpacing.xs),
                    Text(
                      tr(
                        context,
                        'Groups this item under a subheading on the menu (e.g. Burritos, Enchiladas, Combos).',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: PelinesSpacing.xs),
                    _newField(
                      subcategory,
                      'Subcategory name',
                      'subcategory-name',
                      busy,
                      maxLength: 60,
                    ),
                    _newLabel('Photo'),
                    AspectRatio(
                      aspectRatio: 1.5,
                      child: Container(
                        decoration: BoxDecoration(
                          color: PelinesColors.mutedSurface,
                          border: Border.all(color: PelinesColors.border),
                          borderRadius: BorderRadius.circular(
                            PelinesRadius.prominentCard,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.image_outlined,
                              color: PelinesColors.textSecondary,
                              size: 36,
                            ),
                            const SizedBox(height: PelinesSpacing.xs),
                            Text(
                              tr(context, 'No image yet'),
                              style: const TextStyle(
                                color: PelinesColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: PelinesSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.upload_outlined),
                        label: Text(tr(context, 'Upload image')),
                      ),
                    ),
                    Text(
                      tr(
                        context,
                        'Save the item to add its photo and modifiers.',
                      ),
                    ),
                    const SizedBox(height: PelinesSpacing.xs),
                    Text(
                      tr(
                        context,
                        'Recommended: JPG or PNG, square or horizontal image. WebP is also supported. Processed image limit: 5 MiB. For best results, use images under 2 MB.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: PelinesSpacing.md),
                    _newField(
                      description,
                      widget.kind == MenuKind.catering
                          ? 'Description (Optional)'
                          : 'Description',
                      'description',
                      busy,
                      lines: 4,
                      hint: 'Short description for customers',
                      count: true,
                    ),
                    _newField(
                      disclaimer,
                      'Disclaimer (Optional)',
                      'disclaimer',
                      busy,
                      lines: 2,
                      hint: 'e.g. Must present a valid ID to receive alcohol',
                      maxLength: 300,
                    ),
                    Text(
                      tr(
                        context,
                        'Shown under the description in item details. Leave empty to hide it.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: PelinesSpacing.md),
                    _newField(
                      price,
                      'Price (USD)',
                      'price',
                      busy,
                      number: true,
                      hint: '0.00',
                    ),
                    if (widget.kind == MenuKind.catering) ...[
                      _newField(
                        serves,
                        'Portions For',
                        'serves',
                        busy,
                        number: true,
                      ),
                      Text(
                        tr(
                          context,
                          'Number of people this catering item is intended to serve.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: PelinesSpacing.md),
                    ],
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: PelinesColors.brandPrimary,
                      title: Text(tr(context, 'Active')),
                      value: available,
                      onChanged: busy
                          ? null
                          : (value) {
                              if (value != null) changeNewAvailable(value);
                            },
                    ),
                    ExpansionTile(
                      title: Text(tr(context, 'Advanced options')),
                      children: [
                        _newField(
                          sortOrder,
                          'Sort order',
                          'order',
                          busy,
                          number: true,
                        ),
                      ],
                    ),
                    const Divider(height: PelinesSpacing.xxl),
                    Text(
                      tr(context, 'Add-ons'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      tr(
                        context,
                        'Create selectable add-ons, modifiers, or upgrades for this menu item.',
                      ),
                    ),
                    const SizedBox(height: PelinesSpacing.xs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.add),
                        label: Text(tr(context, 'Add add-on group')),
                      ),
                    ),
                    Text(
                      tr(
                        context,
                        'Save the item before managing add-ons from its details.',
                      ),
                    ),
                    if (input == null)
                      Text(
                        tr(
                          context,
                          'Enter a name, a valid non-negative price, and valid numeric values.',
                        ),
                        style: const TextStyle(
                          color: PelinesColors.destructive,
                        ),
                      ),
                    if (errorMessage case final String message)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          tr(context, message),
                          key: newErrorKey,
                          style: const TextStyle(
                            color: PelinesColors.destructive,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(PelinesSpacing.md),
            child: _EditorActions(
              sideBySide: true,
              children: [
                OutlinedButton(
                  style: PelinesControlStyles.button(
                    PelinesButtonVariant.secondary,
                  ),
                  onPressed: busy ? null : _leave,
                  child: Text(tr(context, 'Cancel')),
                ),
                FilledButton(
                  style: PelinesControlStyles.button(
                    PelinesButtonVariant.primary,
                  ),
                  onPressed: busy || input == null || !dirty
                      ? null
                      : () => _saveProduct(key),
                  child: PelinesButtonLabel(
                    busy: busy,
                    label: tr(context, busy ? 'Saving...' : 'Save'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (widget.sheet) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(top: false, child: content),
      );
    }
    return Dialog(
      backgroundColor: PelinesColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PelinesRadius.dialog),
      ),
      insetPadding: const EdgeInsets.all(PelinesSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: content,
      ),
    );
  }

  Widget _newLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: PelinesSpacing.xs),
    child: Text(
      tr(context, text).toUpperCase(),
      style: PelinesTypography.smallLabel,
    ),
  );

  Widget _newField(
    TextEditingController controller,
    String label,
    String id,
    bool busy, {
    String? hint,
    int lines = 1,
    bool number = false,
    int? maxLength,
    bool count = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: PelinesSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _newLabel(label),
        Semantics(
          label: tr(context, label),
          child: TextField(
            key: ValueKey('new-menu-item-$id'),
            controller: controller,
            enabled: !busy,
            maxLines: lines,
            maxLength: maxLength,
            keyboardType: number
                ? const TextInputType.numberWithOptions(decimal: true)
                : null,
            decoration:
                PelinesControlStyles.input(
                  hint: hint == null ? null : tr(context, hint),
                ).copyWith(
                  prefixText: controller == price ? r'$ ' : null,
                  counterText: count ? '${controller.text.length}' : null,
                ),
          ),
        ),
      ],
    ),
  );
}
