import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../data/menu_repository.dart';
import '../models/menu_models.dart';
import '../providers/menu_providers.dart';
import 'menu_screens.dart';

class ProductFormScreen extends ConsumerWidget {
  const ProductFormScreen({
    required this.kind,
    required this.categoryId,
    required this.categoryName,
    this.productId,
    super.key,
  });
  final MenuKind kind;
  final String categoryId;
  final String categoryName;
  final String? productId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Location? location = ref.watch(currentLocationProvider).value;
    if (location == null) {
      return const Scaffold(
        body: MenuEmpty('Choose a location to edit products.'),
      );
    }
    if (productId == null) {
      return _Form(
        kind: kind,
        categoryId: categoryId,
        categoryName: categoryName,
        location: location,
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
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, stack) => Scaffold(
            appBar: AppBar(title: const Text('Edit Product')),
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
  });
  final MenuKind kind;
  final String categoryId;
  final String categoryName;
  final Location location;
  final MenuProduct? initial;
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
    if (name.text.trim().isEmpty ||
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
      categoryId: widget.categoryId,
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
    return p.name != i.name ||
        (p.description ?? '') != i.description ||
        p.priceCents != i.priceCents ||
        p.isAvailable != i.isAvailable ||
        p.sortOrder != i.sortOrder ||
        (p.subcategory ?? '') != i.subcategory ||
        p.servesCount != i.servesCount ||
        (p.disclaimer ?? '') != i.disclaimer;
  }

  Future<void> _leave() async {
    if (!dirty) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
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
      categoryId: widget.categoryId,
      productId: widget.initial?.id,
    );
    final mutation = ref.watch(productMutationProvider(key));
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (popped, result) {
        if (!popped) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.initial == null ? 'New Product' : 'Edit Product'),
          leading: IconButton(
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: PelinesPageBody(
          child: ListView(
            padding: const EdgeInsets.all(PelinesSpacing.lg),
            children: <Widget>[
              Text('${widget.categoryName} · ${widget.location.name}'),
              const SizedBox(height: 16),
              _text(name, 'Name'),
              _text(description, 'Description', lines: 3),
              _text(price, 'Price', number: true),
              _text(subcategory, 'Subcategory'),
              _text(serves, 'Serves', number: true),
              _text(disclaimer, 'Disclaimer', lines: 2),
              _text(sortOrder, 'Sort order', number: true),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Available'),
                value: available,
                onChanged: mutation.isBusy
                    ? null
                    : (value) => setState(() => available = value),
              ),
              if (input == null)
                const Text(
                  'Enter a name, a valid non-negative price, and valid numeric values.',
                  style: TextStyle(color: PelinesColors.destructive),
                ),
              if (mutation.message != null) Text(mutation.message!),
              const SizedBox(height: 12),
              PelinesActionBar(
                children: <Widget>[
                  OutlinedButton(
                    onPressed: mutation.isBusy ? null : _leave,
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: input == null || !dirty || mutation.isBusy
                        ? null
                        : () async {
                            final ok = await ref
                                .read(productMutationProvider(key).notifier)
                                .save(input!);
                            if (ok && mounted) {
                              Navigator.of(this.context).pop(true);
                            }
                          },
                    child: PelinesButtonLabel(
                      busy: mutation.isBusy,
                      label: mutation.isBusy
                          ? 'Saving...'
                          : widget.initial == null
                          ? 'Create Product'
                          : 'Save',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

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
      decoration: InputDecoration(
        labelText: label,
        prefixText: label == 'Price' ? r'$' : null,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
