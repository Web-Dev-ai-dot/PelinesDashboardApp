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

class CategoryFormScreen extends ConsumerWidget {
  const CategoryFormScreen({required this.kind, this.categoryId, super.key});

  final MenuKind kind;
  final String? categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Location? location = ref.watch(currentLocationProvider).value;
    if (location == null) {
      return Scaffold(
        body: MenuEmpty(tr(context, 'Choose a location to edit categories.')),
      );
    }
    if (categoryId == null) {
      return _CategoryForm(kind: kind, location: location);
    }

    final CategoryDetailQuery query = (
      locationId: location.id,
      kind: kind,
      categoryId: categoryId!,
    );
    return ref
        .watch(menuCategoryDetailProvider(query))
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (Object error, StackTrace stackTrace) => Scaffold(
            appBar: AdminAppBar(title: Text(tr(context, 'Edit Category'))),
            body: MenuError(
              message: error.toString(),
              onRetry: () => ref.invalidate(menuCategoryDetailProvider(query)),
            ),
          ),
          data: (MenuCategory category) =>
              _CategoryForm(kind: kind, location: location, initial: category),
        );
  }
}

class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({
    required this.kind,
    required this.location,
    this.initial,
  });

  final MenuKind kind;
  final Location location;
  final MenuCategory? initial;

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
