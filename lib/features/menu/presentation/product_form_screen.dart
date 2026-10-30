import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../data/menu_repository.dart';
import '../models/menu_models.dart';
import '../providers/menu_providers.dart';
import 'menu_screens.dart';
import 'menu_parity_widgets.dart';
import 'catering_inline_addons.dart';
import '../../../app/theme/app_theme.dart';

part 'new_menu_item_form.dart';

class ProductFormScreen extends ConsumerWidget {
  const ProductFormScreen({
    required this.kind,
    required this.categoryId,
    required this.categoryName,
    this.productId,
    this.sheet = false,
    super.key,
  });
  final MenuKind kind;
  final String categoryId;
  final String categoryName;
  final String? productId;
  final bool sheet;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Location? location = ref.watch(currentLocationProvider).value;
    if (location == null) {
      return Scaffold(
        body: MenuEmpty(tr(context, 'Choose a location to edit products.')),
      );
    }
    if (productId == null) {
      return _Form(
        kind: kind,
        categoryId: categoryId,
        categoryName: categoryName,
        location: location,
        sheet: sheet,
      );
    }
    final query = (
      locationId: location.id,
      categoryId: categoryId,
      productId: productId!,
    );
    return ref
        .watch(menuProductDetailProvider(query))
        .when(
          skipLoadingOnReload: true,
          skipError: true,
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, stack) => Scaffold(
            appBar: AdminAppBar(title: Text(tr(context, 'Edit Product'))),
            body: MenuError(
              message: error.toString(),
              onRetry: () => ref.invalidate(menuProductDetailProvider(query)),
            ),
          ),
          data: (product) => _Form(
            kind: kind,
            categoryId: categoryId,
            categoryName: categoryName,
            location: location,
            initial: product,
          ),
        );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({
    required this.kind,
    required this.categoryId,
    required this.categoryName,
    required this.location,
    this.initial,
    this.sheet = false,
  });
  final MenuKind kind;
  final String categoryId;
  final String categoryName;
  final Location location;
  final MenuProduct? initial;
  final bool sheet;
  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final List<TextEditingController> fields;
  TextEditingController get name => fields[0];
  TextEditingController get description => fields[1];
  TextEditingController get price => fields[2];
  TextEditingController get subcategory => fields[3];
  TextEditingController get serves => fields[4];
  TextEditingController get disclaimer => fields[5];
  TextEditingController get sortOrder => fields[6];
  late bool available;
  bool addonDirty = false, addonBusy = false;
  bool get creatingItem =>
      widget.initial == null &&
      (widget.kind == MenuKind.store || widget.kind == MenuKind.catering);
  bool savingNewItem = false;
  String? newSaveError;
  final newErrorKey = GlobalKey();

  void changeNewCategory(String id) => setState(() => selectedCategoryId = id);
  void changeNewAvailable(bool value) => setState(() => available = value);
  bool get anyDirty => dirty || addonDirty;
  late String selectedCategoryId;
  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    fields = <TextEditingController>[
      TextEditingController(text: p?.name ?? ''),
      TextEditingController(text: p?.description ?? ''),
      TextEditingController(
        text: p == null
            ? ''
            : '${p.priceCents ~/ 100}.${(p.priceCents % 100).toString().padLeft(2, '0')}',
      ),
      TextEditingController(text: p?.subcategory ?? ''),
      TextEditingController(text: p?.servesCount?.toString() ?? ''),
      TextEditingController(text: p?.disclaimer ?? ''),
      TextEditingController(text: p?.sortOrder.toString() ?? '0'),
    ];
    available = p?.isAvailable ?? true;
    selectedCategoryId = widget.categoryId;
    for (final field in fields) {
      field.addListener(_changed);
    }
  }

  void _changed() => setState(() {});
  @override
  void dispose() {
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  ProductWriteInput? get input {
    final cents = parsePriceCents(price.text);
    final order = int.tryParse(sortOrder.text.trim());
    final count = serves.text.trim().isEmpty
        ? null
        : int.tryParse(serves.text.trim());
    if ((widget.kind == MenuKind.catering && selectedCategoryId.isEmpty) ||
        name.text.trim().isEmpty ||
        name.text.trim().length > 120 ||
        cents == null ||
        order == null ||
        order < 0 ||
        (serves.text.trim().isNotEmpty && (count == null || count < 1)) ||
        subcategory.text.length > 60 ||
        disclaimer.text.length > 300) {
      return null;
    }
    return ProductWriteInput(
      categoryId: selectedCategoryId,
      name: name.text.trim(),
      description: description.text,
      priceCents: cents,
      isAvailable: available,
      sortOrder: order,
      subcategory: subcategory.text,
      servesCount: count,
      disclaimer: disclaimer.text,
    );
  }

  bool get dirty {
    final p = widget.initial;
    final i = input;
    if (p == null) {
      return fields.take(6).any((f) => f.text.isNotEmpty) ||
          sortOrder.text != '0' ||
          !available;
    }
    if (i == null) return true;
    return p.categoryId != i.categoryId ||
        p.name != i.name ||
        (p.description ?? '') != i.description ||
        p.priceCents != i.priceCents ||
        p.isAvailable != i.isAvailable ||
        p.sortOrder != i.sortOrder ||
        (p.subcategory ?? '') != i.subcategory ||
        p.servesCount != i.servesCount ||
        (p.disclaimer ?? '') != i.disclaimer;
  }

  Future<void> _leave() async {
    if (addonBusy || (creatingItem && savingNewItem)) return;
    if (!anyDirty) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'Discard unsaved changes?')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Stay')),
          ),
          FilledButton(
            style: PelinesControlStyles.button(PelinesButtonVariant.primary),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Discard')),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = (
      locationId: widget.location.id,
      locationSlug: widget.location.slug,
      kind: widget.kind,
      categoryId: selectedCategoryId,
      productId: widget.initial?.id,
    );
    final mutation = ref.watch(productMutationProvider(key));
    if (creatingItem) return buildNewMenuItem(key, mutation);
    return AdminPopScope(
      canPop: !anyDirty && !addonBusy,
      onPopInvokedWithResult: (popped, result) async {
        if (!popped) await _leave();
      },
      child: Scaffold(
        appBar: AdminAppBar(
          title: Text(
            widget.kind == MenuKind.catering && widget.initial != null
                ? tr(context, 'Edit item')
                : widget.initial == null
                ? tr(context, 'New Product')
                : tr(context, 'Edit Product'),
            style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
          ),
          leading: widget.kind == MenuKind.catering
              ? null
              : IconButton(
                  onPressed: _leave,
                  icon: const Icon(Icons.arrow_back),
                ),
          actions: widget.kind == MenuKind.catering
              ? [
                  IconButton(
                    tooltip: tr(context, 'Close'),
                    onPressed: mutation.isBusy || addonBusy ? null : _leave,
                    icon: const Icon(Icons.close),
                  ),
                ]
              : null,
        ),
        body: SafeArea(
          top: false,
          bottom: widget.kind == MenuKind.catering,
          child: PelinesPageBody(
            child: MenuFormList(
              padding: const EdgeInsets.all(PelinesSpacing.lg),
              children: <Widget>[
                Text(
                  '${widget.categoryName.isEmpty ? tr(context, widget.kind.label) : widget.categoryName} · ${widget.location.name}',
                ),
                const SizedBox(height: 16),
                if (widget.kind == MenuKind.catering)
                  ..._cateringFields(mutation.isBusy)
                else ...[
                  if (widget.initial != null) ...[
                    ProductImageAdministration(
                      imageUrl: widget.initial!.imageUrl,
                      locationId: widget.location.id,
                      locationSlug: widget.location.slug,
                      kind: widget.kind,
                      categoryId: widget.categoryId,
                      productId: widget.initial!.id,
                    ),
                    Text(tr(context, 'Photo changes are saved separately.')),
                    TextButton(
                      onPressed: mutation.isBusy
                          ? null
                          : () => context.push(
                              '/app/menu/${widget.kind.name}/categories/${widget.categoryId}/products/${widget.initial!.id}?category=${Uri.encodeQueryComponent(widget.categoryName)}',
                            ),
                      child: Text(tr(context, 'Manage modifiers')),
                    ),
                  ],
                  ...[
                    if (widget.initial == null)
                      Text(
                        tr(
                          context,
                          'Save the item to add its photo and modifiers.',
                        ),
                      ),
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
                          error: (e, _) => Text(e.toString()),
                          data: (categories) => DropdownButtonFormField<String>(
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
                            decoration: PelinesControlStyles.input(
                              label: tr(context, 'Category'),
                            ),
                            items: [
                              for (final c in categories)
                                DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name),
                                ),
                            ],
                            onChanged: mutation.isBusy
                                ? null
                                : (id) {
                                    if (id != null) {
                                      setState(() => selectedCategoryId = id);
                                    }
                                  },
                          ),
                        ),
                    const SizedBox(height: 16),
                  ],
                  _text(name, tr(context, 'Name')),
                  _text(description, tr(context, 'Description'), lines: 3),
                  MenuFieldPair(
                    first: _text(price, tr(context, 'Price'), number: true),
                    second: Column(
                      children: [
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
                              error: (error, _) => Text(error.toString()),
                              data: (products) {
                                final labels =
                                    products
                                        .map((p) => p.subcategory?.trim() ?? '')
                                        .where((s) => s.isNotEmpty)
                                        .toSet()
                                        .toList()
                                      ..sort();
                                return DropdownButtonFormField<String>(
                                  key: ValueKey(
                                    '${widget.kind.name}-subcategory-$selectedCategoryId-${subcategory.text}',
                                  ),
                                  initialValue:
                                      labels.contains(subcategory.text)
                                      ? subcategory.text
                                      : null,
                                  isExpanded: true,
                                  decoration: PelinesControlStyles.input(
                                    label: tr(context, 'Subcategory'),
                                  ),
                                  items: [
                                    for (final label in labels)
                                      DropdownMenuItem(
                                        value: label,
                                        child: Text(label),
                                      ),
                                  ],
                                  onChanged: mutation.isBusy
                                      ? null
                                      : (label) {
                                          if (label != null) {
                                            subcategory.text = label;
                                          }
                                        },
                                );
                              },
                            ),
                        _text(subcategory, tr(context, 'Subcategory name')),
                      ],
                    ),
                  ),
                  if (widget.kind == MenuKind.catering)
                    _text(serves, tr(context, 'Serves'), number: true),
                  _text(disclaimer, tr(context, 'Disclaimer'), lines: 2),
                  _text(sortOrder, tr(context, 'Sort order'), number: true),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr(context, 'Available')),
                    value: available,
                    onChanged: mutation.isBusy
                        ? null
                        : (value) => setState(() => available = value),
                  ),
                ],
                if (input == null)
                  Text(
                    tr(
                      context,
                      'Enter a name, a valid non-negative price, and valid numeric values.',
                    ),
                    style: TextStyle(color: PelinesColors.destructive),
                  ),
                if (mutation.message != null) Text(mutation.message!),
                const SizedBox(height: 12),
                if (addonDirty)
                  Text(
                    tr(
                      context,
                      'Save or reset add-on drafts before saving the item.',
                    ),
                  ),
                _EditorActions(
                  sideBySide: widget.kind == MenuKind.catering,
                  children: <Widget>[
                    OutlinedButton(
                      style: PelinesControlStyles.button(
                        PelinesButtonVariant.secondary,
                      ),
                      onPressed: mutation.isBusy || addonBusy ? null : _leave,
                      child: Text(tr(context, 'Cancel')),
                    ),
                    FilledButton(
                      style: PelinesControlStyles.button(
                        PelinesButtonVariant.primary,
                      ),
                      onPressed:
                          input == null ||
                              !dirty ||
                              mutation.isBusy ||
                              addonBusy ||
                              addonDirty
                          ? null
                          : () => _saveProduct(key),
                      child: PelinesButtonLabel(
                        busy: mutation.isBusy,
                        label: mutation.isBusy
                            ? tr(context, 'Saving...')
                            : widget.initial == null
                            ? tr(context, 'Create Product')
                            : tr(context, 'Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveProduct(ProductMutationKey key) async {
    if (creatingItem && savingNewItem) return;
    if (creatingItem) {
      setState(() {
        savingNewItem = true;
        newSaveError = null;
      });
    }
    try {
      final ok = await ref
          .read(productMutationProvider(key).notifier)
          .save(input!);
      if (ok && mounted) {
        final saved = ref.read(productMutationProvider(key)).product!;
        final categories = ref
            .read(
              menuCategoriesProvider((
                locationId: widget.location.id,
                locationSlug: widget.location.slug,
                kind: widget.kind,
              )),
            )
            .value;
        final categoryName =
            categories
                ?.where((c) => c.id == saved.categoryId)
                .firstOrNull
                ?.name ??
            widget.categoryName;
        context.pushReplacement(
          '/app/menu/${widget.kind.name}/categories/${saved.categoryId}/products/${saved.id}?category=${Uri.encodeQueryComponent(categoryName)}',
        );
      }
    } catch (_) {
      if (!creatingItem) rethrow;
      if (mounted) {
        setState(() => newSaveError = 'The product could not be saved.');
      }
    } finally {
      if (creatingItem && mounted) {
        setState(() => savingNewItem = false);
        if (newSaveError != null ||
            ref.read(productMutationProvider(key)).phase ==
                ProductMutationPhase.error) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final errorContext = newErrorKey.currentContext;
            if (mounted && errorContext != null) {
              Scrollable.ensureVisible(
                errorContext,
                alignment: 1,
                duration: const Duration(milliseconds: 200),
              );
            }
          });
        }
      }
    }
  }

  List<Widget> _cateringFields(bool busy) => [
    _text(name, tr(context, 'Name')),
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
          error: (e, _) => Text(e.toString()),
          data: (categories) => DropdownButtonFormField<String>(
            key: ValueKey(
              '${widget.kind.name}-edit-category-$selectedCategoryId',
            ),
            initialValue: categories.any((c) => c.id == selectedCategoryId)
                ? selectedCategoryId
                : null,
            isExpanded: true,
            hint: Text(tr(context, 'Select a category')),
            decoration: PelinesControlStyles.input(
              label: tr(context, 'Category'),
            ),
            items: [
              for (final c in categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: busy
                ? null
                : (id) {
                    if (id != null) setState(() => selectedCategoryId = id);
                  },
          ),
        ),
    const SizedBox(height: 16),
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
            error: (e, _) => Text(e.toString()),
            data: (products) {
              final labels =
                  products
                      .map((p) => p.subcategory?.trim() ?? '')
                      .where((s) => s.isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort();
              return DropdownButtonFormField<String>(
                key: ValueKey(
                  'catering-subcategory-$selectedCategoryId-${subcategory.text}',
                ),
                initialValue: labels.contains(subcategory.text)
                    ? subcategory.text
                    : '',
                isExpanded: true,
                decoration: PelinesControlStyles.input(
                  label: tr(context, 'Subcategory (Optional)'),
                ),
                items: [
                  DropdownMenuItem(value: '', child: Text(tr(context, 'None'))),
                  for (final label in labels)
                    DropdownMenuItem(value: label, child: Text(label)),
                ],
                onChanged: busy
                    ? null
                    : (label) {
                        if (label != null) subcategory.text = label;
                      },
              );
            },
          ),
    const SizedBox(height: 8),
    Text(
      tr(
        context,
        'Groups this item under a subheading on the menu (e.g. Burritos, Enchiladas, Combos).',
      ),
      style: Theme.of(context).textTheme.bodySmall,
    ),
    const SizedBox(height: 12),
    _text(subcategory, tr(context, 'Subcategory name')),
    if (widget.initial != null) ...[
      ProductImageAdministration(
        imageUrl: widget.initial!.imageUrl,
        locationId: widget.location.id,
        locationSlug: widget.location.slug,
        kind: widget.kind,
        categoryId: widget.categoryId,
        productId: widget.initial!.id,
        editor: true,
      ),
      Text(tr(context, 'Photo changes are saved separately.')),
    ] else
      Text(tr(context, 'Save the item to add its photo and modifiers.')),
    const SizedBox(height: 16),
    _text(description, tr(context, 'Description (Optional)'), lines: 4),
    _text(disclaimer, tr(context, 'Disclaimer (Optional)'), lines: 2),
    Text(
      tr(
        context,
        'Shown under the description in item details. Leave empty to hide it.',
      ),
      style: Theme.of(context).textTheme.bodySmall,
    ),
    const SizedBox(height: 16),
    MenuFieldPair(
      first: _text(price, tr(context, 'Price (USD)'), number: true),
      second: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _text(serves, tr(context, 'Portions For'), number: true),
          Text(
            tr(
              context,
              'Number of people this catering item is intended to serve.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    const SizedBox(height: 20),
    _text(sortOrder, tr(context, 'Sort order'), number: true),
    CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(tr(context, 'Active')),
      value: available,
      onChanged: busy
          ? null
          : (value) {
              if (value != null) setState(() => available = value);
            },
    ),
    if (widget.initial != null) ...[
      const Divider(height: 24),
      CateringInlineAddons(
        key: ValueKey('addons-${widget.location.id}-${widget.initial!.id}'),
        contextKey: (
          locationId: widget.location.id,
          locationSlug: widget.location.slug,
          kind: widget.kind,
          categoryId: widget.categoryId,
          productId: widget.initial!.id,
        ),
        productBusy: busy,
        onStateChanged: (d, b) {
          if (mounted && (addonDirty != d || addonBusy != b)) {
            setState(() {
              addonDirty = d;
              addonBusy = b;
            });
          }
        },
      ),
    ],
  ];

  Widget _text(
    TextEditingController controller,
    String label, {
    int lines = 1,
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      maxLines: lines,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      decoration: PelinesControlStyles.input(label: label).copyWith(
        prefixText: controller == price ? r'$' : null,
        counterText: widget.kind != MenuKind.catering
            ? null
            : controller == name
            ? '${controller.text.length}/120'
            : controller == description
            ? '${controller.text.length}'
            : null,
      ),
    ),
  );
}

class _EditorActions extends StatelessWidget {
  const _EditorActions({required this.children, required this.sideBySide});
  final List<Widget> children;
  final bool sideBySide;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (sideBySide &&
          constraints.maxWidth >=
              250 * MediaQuery.textScalerOf(context).scale(1)) {
        return Row(
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 16),
            Expanded(child: children[1]),
          ],
        );
      }
      return PelinesActionBar(children: children);
    },
  );
}
