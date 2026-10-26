import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../../../app/theme/app_theme.dart';

/// Keeps the existing creation URL and Navigator result while presenting a modal.
class NewCategoryPage extends Page<bool> {
  const NewCategoryPage({required this.kind, super.key});
  final MenuKind kind;

  @override
  Route<bool> createRoute(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < PelinesLayout.compactWidth) {
      return ModalBottomSheetRoute<bool>(
        settings: this,
        builder: (_) => CategoryFormScreen(kind: kind, sheet: true),
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
    return DialogRoute<bool>(
      settings: this,
      context: context,
      barrierDismissible: false,
      builder: (_) => CategoryFormScreen(kind: kind),
    );
  }
}

class CategoryFormScreen extends ConsumerWidget {
  const CategoryFormScreen({
    required this.kind,
    this.categoryId,
    this.modal = false,
    this.sheet = false,
    super.key,
  });

  final MenuKind kind;
  final String? categoryId;
  final bool modal;
  final bool sheet;

  Widget _pending(BuildContext context, Widget child) => Padding(
    padding: const EdgeInsets.all(PelinesSpacing.md),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: tr(context, 'Close'),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ),
        Flexible(child: child),
      ],
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Location? location = ref.watch(currentLocationProvider).value;
    if (location == null) {
      return Scaffold(
        body: MenuEmpty(tr(context, 'Choose a location to edit categories.')),
      );
    }
    if (categoryId == null) {
      final form = _CategoryForm(kind: kind, location: location, modal: true);
      if (sheet) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(top: false, child: form),
        );
      }
      return Dialog(
        backgroundColor: PelinesColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PelinesRadius.dialog),
        ),
        insetPadding: const EdgeInsets.all(PelinesSpacing.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: form,
        ),
      );
    }

    final CategoryDetailQuery query = (
      locationId: location.id,
      kind: kind,
      categoryId: categoryId!,
    );
    final content = ref
        .watch(menuCategoryDetailProvider(query))
        .when(
          loading: () => modal
              ? _pending(
                  context,
                  const Center(child: CircularProgressIndicator()),
                )
              : const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
          error: (Object error, StackTrace stackTrace) => modal
              ? _pending(
                  context,
                  MenuError(
                    message: error.toString(),
                    onRetry: () =>
                        ref.invalidate(menuCategoryDetailProvider(query)),
                  ),
                )
              : Scaffold(
                  appBar: AdminAppBar(
                    title: Text(tr(context, 'Edit Category')),
                  ),
                  body: MenuError(
                    message: error.toString(),
                    onRetry: () =>
                        ref.invalidate(menuCategoryDetailProvider(query)),
                  ),
                ),
          data: (MenuCategory category) => _CategoryForm(
            kind: kind,
            location: location,
            initial: category,
            modal: modal,
          ),
        );
    if (!modal) return content;
    return Dialog(
      backgroundColor: PelinesColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PelinesRadius.dialog),
      ),
      insetPadding: const EdgeInsets.all(PelinesSpacing.md),
      child: ConstrainedBox(
        key: const ValueKey('category-modal-content'),
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 840),
        child: content,
      ),
    );
  }
}

class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({
    required this.kind,
    required this.location,
    this.initial,
    this.modal = false,
  });

  final MenuKind kind;
  final Location location;
  final MenuCategory? initial;
  final bool modal;

  @override
  ConsumerState<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<_CategoryForm> {
  late final TextEditingController _name;
  late final TextEditingController _sortOrder;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _sortOrder = TextEditingController(
      text: widget.initial?.sortOrder.toString() ?? '0',
    );
    _active = widget.initial?.isActive ?? true;
    _name.addListener(_changed);
    _sortOrder.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  CategoryWriteInput? get _input {
    final int? order = int.tryParse(_sortOrder.text.trim());
    final String value = _name.text.trim();
    if (value.isEmpty || value.length > 80 || order == null || order < 0) {
      return null;
    }
    return CategoryWriteInput(
      locationId: widget.location.id,
      kind: widget.kind,
      name: value,
      sortOrder: order,
      isActive: _active,
    );
  }

  bool get _dirty {
    final MenuCategory? initial = widget.initial;
    final CategoryWriteInput? value = _input;
    if (initial == null) {
      return _name.text.isNotEmpty || _sortOrder.text != '0' || !_active;
    }
    if (value == null) return true;
    return initial.name != value.name ||
        initial.sortOrder != value.sortOrder ||
        initial.isActive != value.isActive;
  }

  Future<void> _leave() async {
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(tr(context, 'Discard unsaved changes?')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr(context, 'Stay')),
          ),
          FilledButton(
            style: PelinesControlStyles.button(PelinesButtonVariant.primary),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr(context, 'Discard')),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  bool _saving = false;

  Future<void> _save(CategoryMutationKey key, CategoryWriteInput input) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(categoryMutationProvider(key).notifier)
          .save(input);
      if (saved && mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _modal(
    CategoryMutationKey key,
    CategoryMutationState mutation,
    CategoryWriteInput? input,
  ) {
    final busy = mutation.isBusy || _saving;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: PelinesSpacing.xs),
      child: Text(
        tr(context, text).toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: PelinesColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return AdminPopScope(
      canPop: !_dirty && !busy,
      onPopInvokedWithResult: (popped, result) async {
        if (!popped && !busy) await _leave();
      },
      child: Padding(
        padding: EdgeInsets.all(
          widget.initial == null ? PelinesSpacing.md : PelinesSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr(
                      context,
                      widget.initial == null ? 'New category' : 'Edit category',
                    ),
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
            const SizedBox(height: PelinesSpacing.lg),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    label('Name'),
                    Semantics(
                      label: tr(context, 'Name'),
                      child: TextField(
                        key: const ValueKey('category-name'),
                        controller: _name,
                        enabled: !busy,
                        maxLength: 80,
                        decoration: PelinesControlStyles.input(
                          hint: widget.initial == null
                              ? tr(context, 'e.g. Salads')
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: PelinesSpacing.md),
                    label('Display order'),
                    Semantics(
                      label: tr(context, 'Display order'),
                      child: TextField(
                        key: const ValueKey('category-order'),
                        controller: _sortOrder,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        decoration: PelinesControlStyles.input(),
                      ),
                    ),
                    const SizedBox(height: PelinesSpacing.md),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: PelinesColors.brandPrimary,
                      title: Text(tr(context, 'Active')),
                      value: _active,
                      onChanged: busy
                          ? null
                          : (value) => setState(() => _active = value!),
                    ),
                    if (widget.initial != null) ...[
                      const Divider(height: PelinesSpacing.xxl),
                      label('Subcategory visibility schedule'),
                      Text(
                        tr(
                          context,
                          'Subcategory schedules are read-only here. Existing settings are preserved when you save.',
                        ),
                      ),
                      const SizedBox(height: PelinesSpacing.md),
                      _CategorySchedules(
                        category: widget.initial!,
                        location: widget.location,
                      ),
                    ],
                    if (input == null)
                      Text(
                        tr(
                          context,
                          'Enter a name up to 80 characters and a non-negative sort order.',
                        ),
                        style: const TextStyle(
                          color: PelinesColors.destructive,
                        ),
                      ),
                    if (mutation.message != null)
                      Text(tr(context, mutation.message!)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: PelinesSpacing.lg),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: PelinesSpacing.sm,
              runSpacing: PelinesSpacing.sm,
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
                  onPressed: busy || input == null || !_dirty
                      ? null
                      : () => _save(key, input),
                  child: PelinesButtonLabel(
                    busy: busy,
                    label: tr(context, busy ? 'Saving...' : 'Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CategoryMutationKey key = (
      locationId: widget.location.id,
      locationSlug: widget.location.slug,
      kind: widget.kind,
      categoryId: widget.initial?.id,
    );
    final CategoryMutationState mutation = ref.watch(
      categoryMutationProvider(key),
    );
    final CategoryWriteInput? input = _input;

    if (widget.modal) return _modal(key, mutation, input);

    return AdminPopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool popped, Object? result) async {
        if (!popped) await _leave();
      },
      child: Scaffold(
        appBar: AdminAppBar(
          title: Text(
            widget.initial == null
                ? tr(context, 'New Category')
                : tr(context, 'Edit Category'),
            style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
          ),
          leading: IconButton(
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: PelinesPageBody(
          child: MenuFormList(
            padding: const EdgeInsets.all(PelinesSpacing.lg),
            children: <Widget>[
              Text('${widget.kind.label} - ${widget.location.name}'),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                enabled: !mutation.isBusy,
                maxLength: 80,
                decoration: PelinesControlStyles.input(
                  label: tr(context, 'Name'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sortOrder,
                enabled: !mutation.isBusy,
                keyboardType: TextInputType.number,
                decoration: PelinesControlStyles.input(
                  label: tr(context, 'Sort order'),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr(context, 'Active')),
                value: _active,
                onChanged: mutation.isBusy
                    ? null
                    : (bool value) => setState(() => _active = value),
              ),
              if (input == null)
                Text(
                  tr(
                    context,
                    'Enter a name up to 80 characters and a non-negative sort order.',
                  ),
                  style: TextStyle(color: PelinesColors.destructive),
                ),
              if (mutation.message != null) Text(mutation.message!),
              const SizedBox(height: 12),
              PelinesActionBar(
                children: <Widget>[
                  OutlinedButton(
                    style: PelinesControlStyles.button(
                      PelinesButtonVariant.secondary,
                    ),
                    onPressed: mutation.isBusy ? null : _leave,
                    child: Text(tr(context, 'Cancel')),
                  ),
                  FilledButton(
                    style: PelinesControlStyles.button(
                      PelinesButtonVariant.primary,
                    ),
                    onPressed: input == null || !_dirty || mutation.isBusy
                        ? null
                        : () async {
                            final bool saved = await ref
                                .read(categoryMutationProvider(key).notifier)
                                .save(input);
                            if (saved && mounted) {
                              Navigator.pop(this.context, true);
                            }
                          },
                    child: PelinesButtonLabel(
                      busy: mutation.isBusy,
                      label: mutation.isBusy
                          ? tr(context, 'Saving...')
                          : widget.initial == null
                          ? tr(context, 'Create Category')
                          : tr(context, 'Save'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                tr(
                  context,
                  'Subcategory schedules are preserved and are not edited in this form.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategorySchedules extends ConsumerWidget {
  const _CategorySchedules({required this.category, required this.location});
  final MenuCategory category;
  final Location location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (
      locationId: location.id,
      locationSlug: location.slug,
      categoryId: category.id,
    );
    return ref
        .watch(menuProductsProvider(query))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => MenuError(
            message: tr(context, 'Subcategories could not be loaded.'),
            onRetry: () => ref.invalidate(menuProductsProvider(query)),
          ),
          data: (products) {
            final schedules =
                category.subcategorySchedules ?? <String, dynamic>{};
            final names = {
              ...products
                  .map((p) => p.subcategory?.trim() ?? '')
                  .where((name) => name.isNotEmpty),
              ...schedules.keys,
            }.toList()..sort();
            if (names.isEmpty) {
              return Text(tr(context, 'No subcategories in this category.'));
            }
            return Column(
              children: names.map((name) {
                final raw = schedules[name];
                final schedule = raw is Map ? raw : null;
                final bool? always = raw == null
                    ? true
                    : schedule?['enabled'] is bool
                    ? !(schedule!['enabled'] as bool)
                    : null;
                final days = schedule?['days'];
                final weekdayLabels = [
                  'Mon',
                  'Tue',
                  'Wed',
                  'Thu',
                  'Fri',
                  'Sat',
                  'Sun',
                ];
                final dayText = days is List
                    ? days
                          .map(
                            (day) => day is int && day >= 0 && day < 7
                                ? tr(context, weekdayLabels[day])
                                : day.toString(),
                          )
                          .join(', ')
                    : '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: PelinesSpacing.xs),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: PelinesColors.border),
                      borderRadius: BorderRadius.circular(
                        PelinesRadius.prominentCard,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(PelinesSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            tristate: true,
                            value: always,
                            onChanged: null,
                            title: Text(tr(context, 'Always visible')),
                          ),
                          if (always == false)
                            Text(
                              '$dayText · ${schedule?['start'] ?? '—'} – ${schedule?['end'] ?? '—'}',
                            ),
                          if (always == false)
                            Text(tr(context, 'Restaurant-local time')),
                          if (!products.any(
                            (product) => product.subcategory?.trim() == name,
                          ))
                            Text(
                              tr(
                                context,
                                'Saved schedule; no items currently use this subcategory.',
                              ),
                            ),
                          if (always == null)
                            Text(
                              tr(
                                context,
                                'Unrecognized schedule. Preserved without changes.',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        );
  }
}
