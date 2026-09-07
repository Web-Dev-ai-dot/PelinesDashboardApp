import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pelines_tokens.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../data/menu_repository.dart';
import '../models/menu_models.dart';
import '../providers/menu_providers.dart';
import 'menu_screens.dart';

class CategoryFormScreen extends ConsumerWidget {
  const CategoryFormScreen({required this.kind, this.categoryId, super.key});

  final MenuKind kind;
  final String? categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Location? location = ref.watch(currentLocationProvider).value;
    if (location == null) {
      return const Scaffold(
        body: MenuEmpty('Choose a location to edit categories.'),
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
            appBar: AppBar(title: const Text('Edit Category')),
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
        title: const Text('Discard unsaved changes?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
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

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool popped, Object? result) {
        if (!popped) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.initial == null ? 'New Category' : 'Edit Category',
          ),
          leading: IconButton(
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(PelinesSpacing.lg),
          children: <Widget>[
            Text('${widget.kind.label} - ${widget.location.name}'),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              enabled: !mutation.isBusy,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sortOrder,
              enabled: !mutation.isBusy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sort order',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              value: _active,
              onChanged: mutation.isBusy
                  ? null
                  : (bool value) => setState(() => _active = value),
            ),
            if (input == null)
              const Text(
                'Enter a name up to 80 characters and a non-negative sort order.',
                style: TextStyle(color: PelinesColors.destructive),
              ),
            if (mutation.message != null) Text(mutation.message!),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: mutation.isBusy ? null : _leave,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
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
                    child: mutation.isBusy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.initial == null ? 'Create Category' : 'Save',
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Subcategory schedules are preserved and are not edited in this form.',
            ),
          ],
        ),
      ),
    );
  }
}
