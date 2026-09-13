import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../locations/providers/locations_providers.dart';
import '../data/menu_repository.dart';
import '../models/menu_models.dart';
import '../providers/modifier_providers.dart';
import 'menu_screens.dart';

class ModifierFormScreen extends ConsumerWidget {
  const ModifierFormScreen({
    required this.kind,
    required this.categoryId,
    required this.productId,
    this.groupId,
    this.optionId,
    this.optionForm = false,
    super.key,
  });

  final MenuKind kind;
  final String categoryId;
  final String productId;
  final String? groupId;
  final String? optionId;
  final bool optionForm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(currentLocationProvider).value;
    if (location == null) {
      return const Scaffold(body: MenuEmpty('Choose a location to continue.'));
    }
    final ModifierContext modifierContext = (
      locationId: location.id,
      locationSlug: location.slug,
      kind: kind,
      categoryId: categoryId,
      productId: productId,
    );
    if (groupId == null) {
      return ModifierGroupForm(contextKey: modifierContext);
    }
    return ref
        .watch(modifierGroupsProvider(modifierContext))
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, stack) => Scaffold(
            body: MenuError(
              message: error.toString(),
              onRetry: () =>
                  ref.invalidate(modifierGroupsProvider(modifierContext)),
            ),
          ),
          data: (groups) {
            final group = groups
                .where((value) => value.id == groupId)
                .firstOrNull;
            if (group == null) {
              return const Scaffold(
                body: MenuEmpty('Modifier group not found.'),
              );
            }
            if (!optionForm) {
              return ModifierGroupForm(
                contextKey: modifierContext,
                initial: group,
              );
            }
            final option = optionId == null
                ? null
                : group.options
                      .where((value) => value.id == optionId)
                      .firstOrNull;
            if (optionId != null && option == null) {
              return const Scaffold(
                body: MenuEmpty('Modifier option not found.'),
              );
            }
            return ModifierOptionForm(
              contextKey: modifierContext,
              group: group,
              initial: option,
            );
          },
        );
  }
}

class ModifierGroupForm extends ConsumerStatefulWidget {
  const ModifierGroupForm({required this.contextKey, this.initial, super.key});
  final ModifierContext contextKey;
  final MenuModifierGroup? initial;

  @override
  ConsumerState<ModifierGroupForm> createState() => _ModifierGroupFormState();
}

class _ModifierGroupFormState extends ConsumerState<ModifierGroupForm> {
  late final TextEditingController _name;
  late final TextEditingController _min;
  late final TextEditingController _max;
  late final TextEditingController _sort;
  late bool _required;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _min = TextEditingController(text: '${initial?.minSelect ?? 0}');
    _max = TextEditingController(text: '${initial?.maxSelect ?? 1}');
    _sort = TextEditingController(text: '${initial?.sortOrder ?? 0}');
    _required = initial?.isRequired ?? false;
    for (final controller in <TextEditingController>[
      _name,
      _min,
      _max,
      _sort,
    ]) {
      controller.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  ModifierGroupWriteInput? get _input {
    final name = _name.text.trim();
    final min = int.tryParse(_min.text.trim());
    final max = int.tryParse(_max.text.trim());
    final sort = int.tryParse(_sort.text.trim());
    if (name.isEmpty ||
        name.length > 80 ||
        min == null ||
        min < 0 ||
        max == null ||
        max < 1 ||
        min > max ||
        sort == null ||
        sort < 0 ||
        (_required && min < 1) ||
        (!_required && min != 0)) {
      return null;
    }
    return ModifierGroupWriteInput(
      name: name,
      isRequired: _required,
      minSelect: min,
      maxSelect: max,
      sortOrder: sort,
    );
  }

  bool get _dirty {
    final initial = widget.initial;
    final input = _input;
    if (initial == null) {
      return _name.text.isNotEmpty ||
          _min.text != '0' ||
          _max.text != '1' ||
          _sort.text != '0' ||
          _required;
    }
    if (input == null) return true;
    return input.name != initial.name ||
        input.isRequired != initial.isRequired ||
        input.minSelect != initial.minSelect ||
        input.maxSelect != initial.maxSelect ||
        input.sortOrder != initial.sortOrder;
  }

  @override
  void dispose() {
    _name.dispose();
    _min.dispose();
    _max.dispose();
    _sort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mutation = ref.watch(modifierMutationProvider(widget.contextKey));
    final input = _input;
    return _ModifierScaffold(
      title: widget.initial == null
          ? 'Add Modifier Group'
          : 'Edit Modifier Group',
      dirty: _dirty,
      busy: mutation.isBusy,
      message: mutation.message,
      saveLabel: widget.initial == null ? 'Create Group' : 'Save Group',
      onSave: input == null || !_dirty
          ? null
          : () async {
              final saved = await ref
                  .read(modifierMutationProvider(widget.contextKey).notifier)
                  .saveGroup(input, groupId: widget.initial?.id);
              if (saved && mounted) Navigator.pop(this.context, true);
            },
      children: <Widget>[
        _textField(_name, 'Name', enabled: !mutation.isBusy, maxLength: 80),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Required'),
          value: _required,
          onChanged: mutation.isBusy
              ? null
              : (value) => setState(() => _required = value),
        ),
        _textField(_min, 'Minimum selections', enabled: !mutation.isBusy),
        _textField(_max, 'Maximum selections', enabled: !mutation.isBusy),
        _textField(_sort, 'Sort order', enabled: !mutation.isBusy),
        if (input == null)
          const Text(
            'Name is required. Use max >= 1, min <= max, and sort >= 0. Required groups need min >= 1; optional groups need min = 0.',
            style: TextStyle(color: PelinesColors.destructive),
          ),
      ],
    );
  }
}

class ModifierOptionForm extends ConsumerStatefulWidget {
  const ModifierOptionForm({
    required this.contextKey,
    required this.group,
    this.initial,
    super.key,
  });
  final ModifierContext contextKey;
  final MenuModifierGroup group;
  final MenuModifierOption? initial;

  @override
  ConsumerState<ModifierOptionForm> createState() => _ModifierOptionFormState();
}

class _ModifierOptionFormState extends ConsumerState<ModifierOptionForm> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _sort;
  late bool _default;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _price = TextEditingController(
      text: ((initial?.priceDeltaCents ?? 0) / 100).toStringAsFixed(2),
    );
    _sort = TextEditingController(text: '${initial?.sortOrder ?? 0}');
    _default = initial?.isDefault ?? false;
    for (final controller in <TextEditingController>[_name, _price, _sort]) {
      controller.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  ModifierOptionWriteInput? get _input {
    final name = _name.text.trim();
    final cents = parseSignedPriceCents(_price.text);
    final sort = int.tryParse(_sort.text.trim());
    if (name.isEmpty || name.length > 80 || cents == null || sort == null) {
      return null;
    }
    return ModifierOptionWriteInput(
      name: name,
      priceDeltaCents: cents,
      isDefault: _default,
      sortOrder: sort,
    );
  }

  bool get _dirty {
    final initial = widget.initial;
    final input = _input;
    if (initial == null) {
      return _name.text.isNotEmpty ||
          _price.text != '0.00' ||
          _sort.text != '0' ||
          _default;
    }
    if (input == null) return true;
    return input.name != initial.name ||
        input.priceDeltaCents != initial.priceDeltaCents ||
        input.isDefault != initial.isDefault ||
        input.sortOrder != initial.sortOrder;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _sort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mutation = ref.watch(modifierMutationProvider(widget.contextKey));
    final input = _input;
    return _ModifierScaffold(
      title: widget.initial == null ? 'Add Option' : 'Edit Option',
      dirty: _dirty,
      busy: mutation.isBusy,
      message: mutation.message,
      saveLabel: widget.initial == null ? 'Create Option' : 'Save Option',
      onSave: input == null || !_dirty
          ? null
          : () async {
              final saved = await ref
                  .read(modifierMutationProvider(widget.contextKey).notifier)
                  .saveOption(
                    input,
                    groupId: widget.group.id,
                    optionId: widget.initial?.id,
                  );
              if (saved && mounted) Navigator.pop(this.context, true);
            },
      children: <Widget>[
        Text('Group: ${widget.group.name}'),
        _textField(_name, 'Name', enabled: !mutation.isBusy, maxLength: 80),
        _textField(
          _price,
          'Price delta (dollars)',
          enabled: !mutation.isBusy,
          decimal: true,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Default option'),
          value: _default,
          onChanged: mutation.isBusy
              ? null
              : (value) => setState(() => _default = value),
        ),
        _textField(_sort, 'Sort order', enabled: !mutation.isBusy),
        if (input == null)
          const Text(
            'Name is required. Price accepts up to two decimals, including negative values. Sort order must be an integer.',
            style: TextStyle(color: PelinesColors.destructive),
          ),
      ],
    );
  }
}

Widget _textField(
  TextEditingController controller,
  String label, {
  required bool enabled,
  int? maxLength,
  bool decimal = false,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: TextField(
    controller: controller,
    enabled: enabled,
    maxLength: maxLength,
    keyboardType: label == 'Name'
        ? TextInputType.text
        : TextInputType.numberWithOptions(signed: decimal, decimal: decimal),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  ),
);

class _ModifierScaffold extends StatelessWidget {
  const _ModifierScaffold({
    required this.title,
    required this.dirty,
    required this.busy,
    required this.saveLabel,
    required this.onSave,
    required this.children,
    this.message,
  });
  final String title;
  final bool dirty;
  final bool busy;
  final String saveLabel;
  final VoidCallback? onSave;
  final List<Widget> children;
  final String? message;

  Future<void> _leave(BuildContext context) async {
    if (!dirty) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
    if (discard == true && context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty,
    onPopInvokedWithResult: (popped, result) {
      if (!popped) _leave(context);
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          onPressed: busy ? null : () => _leave(context),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: PelinesPageBody(
        child: ListView(
          padding: const EdgeInsets.all(PelinesSpacing.lg),
          children: <Widget>[
            ...children,
            if (message != null) Text(message!),
            const SizedBox(height: 12),
            PelinesActionBar(
              children: <Widget>[
                OutlinedButton(
                  onPressed: busy ? null : () => _leave(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: busy ? null : onSave,
                  child: PelinesButtonLabel(
                    busy: busy,
                    label: busy ? 'Saving...' : saveLabel,
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
