import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../locations/providers/locations_providers.dart';
import '../data/menu_repository.dart';
import '../models/menu_models.dart';
import '../providers/modifier_providers.dart';
import 'menu_screens.dart';
import 'menu_parity_widgets.dart';
import '../../../app/theme/app_theme.dart';

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
      return Scaffold(
        body: MenuEmpty(tr(context, 'Choose a location to continue.')),
      );
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
              return Scaffold(
                body: MenuEmpty(tr(context, 'Modifier group not found.')),
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
              return Scaffold(
                body: MenuEmpty(tr(context, 'Modifier option not found.')),
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
  const ModifierGroupForm({
    required this.contextKey,
    this.initial,
    this.inline = false,
    this.onSaved,
    this.onCancel,
    this.onStateChanged,
    this.trailing,
    super.key,
  });
  final ModifierContext contextKey;
  final MenuModifierGroup? initial;
  final bool inline;
  final Widget? trailing;
  final VoidCallback? onSaved, onCancel;
  final void Function(bool dirty, bool busy)? onStateChanged;

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
    final reportedDirty = _dirty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onStateChanged?.call(reportedDirty, mutation.isBusy);
    });
    return _ModifierScaffold(
      inline: widget.inline,
      inlineCard: widget.initial == null,
      onCancel: widget.onCancel,
      title: widget.initial == null
          ? tr(context, 'Add Modifier Group')
          : tr(context, 'Edit Modifier Group'),
      dirty: _dirty,
      busy: mutation.isBusy,
      message: widget.inline ? null : mutation.message,
      saveLabel: widget.initial == null
          ? tr(context, 'Create Group')
          : tr(context, 'Save Group'),
      onSave: input == null || !_dirty
          ? null
          : () async {
              final saved = await ref
                  .read(modifierMutationProvider(widget.contextKey).notifier)
                  .saveGroup(input, groupId: widget.initial?.id);
              if (saved && mounted) {
                if (widget.inline) {
                  widget.onSaved?.call();
                } else {
                  Navigator.pop(this.context, true);
                }
              }
            },
      children: widget.inline
          ? _inlineFields(mutation.isBusy)
          : <Widget>[
              _textField(
                _name,
                tr(context, 'Name'),
                enabled: !mutation.isBusy,
                maxLength: 80,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr(context, 'Required')),
                value: _required,
                onChanged: mutation.isBusy
                    ? null
                    : (value) => setState(() => _required = value),
              ),
              _textField(
                _min,
                tr(context, 'Minimum selections'),
                enabled: !mutation.isBusy,
              ),
              _textField(
                _max,
                tr(context, 'Maximum selections'),
                enabled: !mutation.isBusy,
              ),
              _textField(
                _sort,
                tr(context, 'Sort order'),
                enabled: !mutation.isBusy,
              ),
              if (input == null)
                Text(
                  tr(
                    context,
                    'Name is required. Use max >= 1, min <= max, and sort >= 0. Required groups need min >= 1; optional groups need min = 0.',
                  ),
                  style: TextStyle(color: PelinesColors.destructive),
                ),
            ],
    );
  }

  List<Widget> _inlineFields(bool busy) => [
    _InlineName(
      field: _textField(
        _name,
        tr(context, 'Name'),
        enabled: !busy,
        maxLength: 80,
        compact: true,
      ),
      trailing: widget.trailing,
    ),
    _InlinePair(
      first: DropdownButtonFormField<String>(
        key: ValueKey('selection-${_max.text}'),
        initialValue: _max.text == '1' ? 'one' : 'multiple',
        isExpanded: true,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: PelinesControlStyles.input(
          label: tr(context, 'Selection Rule'),
        ).copyWith(isDense: true),
        items: [
          DropdownMenuItem(
            value: 'one',
            child: Text(tr(context, 'Choose one')),
          ),
          DropdownMenuItem(
            value: 'multiple',
            child: Text(tr(context, 'Multiple selections')),
          ),
        ],
        onChanged: busy
            ? null
            : (value) {
                if (value == 'one') {
                  _max.text = '1';
                  if ((int.tryParse(_min.text) ?? 0) > 1) _min.text = '1';
                } else if (_max.text == '1') {
                  _max.text = '2';
                }
              },
      ),
      second: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          tr(context, 'Required'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        value: _required,
        onChanged: busy
            ? null
            : (value) {
                if (value == null) return;
                setState(() {
                  _required = value;
                  if (!value) {
                    _min.text = '0';
                  } else if ((int.tryParse(_min.text) ?? 0) < 1) {
                    _min.text = '1';
                  }
                });
              },
      ),
    ),
    _InlineAdvanced(
      initiallyExpanded: _input == null && _name.text.isNotEmpty,
      children: [
        _InlinePair(
          first: _textField(
            _min,
            tr(context, 'Minimum selections'),
            enabled: !busy,
            compact: true,
          ),
          second: _textField(
            _max,
            tr(context, 'Maximum selections'),
            enabled: !busy,
            compact: true,
          ),
        ),
        _textField(
          _sort,
          tr(context, 'Sort order'),
          enabled: !busy,
          compact: true,
        ),
      ],
    ),
    if (_input == null)
      Text(
        tr(
          context,
          'Name is required. Use max >= 1, min <= max, and sort >= 0. Required groups need min >= 1; optional groups need min = 0.',
        ),
        style: TextStyle(color: PelinesColors.destructive),
      ),
  ];
}

class ModifierOptionForm extends ConsumerStatefulWidget {
  const ModifierOptionForm({
    required this.contextKey,
    required this.group,
    this.initial,
    this.inline = false,
    this.onSaved,
    this.onCancel,
    this.onStateChanged,
    this.trailing,
    super.key,
  });
  final bool inline;
  final Widget? trailing;
  final VoidCallback? onSaved, onCancel;
  final void Function(bool dirty, bool busy)? onStateChanged;
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
    final reportedDirty = _dirty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onStateChanged?.call(reportedDirty, mutation.isBusy);
    });
    return _ModifierScaffold(
      inline: widget.inline,
      onCancel: widget.onCancel,
      title: widget.initial == null
          ? tr(context, 'Add Option')
          : tr(context, 'Edit Option'),
      dirty: _dirty,
      busy: mutation.isBusy,
      message: widget.inline ? null : mutation.message,
      saveLabel: widget.initial == null
          ? tr(context, 'Create Option')
          : tr(context, 'Save Option'),
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
              if (saved && mounted) {
                if (widget.inline) {
                  widget.onSaved?.call();
                } else {
                  Navigator.pop(this.context, true);
                }
              }
            },
      inlineCard: true,
      inlineCardBottomPadding: PelinesSpacing.md,
      children: widget.inline
          ? _inlineFields(mutation.isBusy)
          : <Widget>[
              Text('${tr(context, 'Group')}: ${widget.group.name}'),
              _textField(
                _name,
                tr(context, 'Name'),
                enabled: !mutation.isBusy,
                maxLength: 80,
              ),
              _textField(
                _price,
                tr(context, 'Price delta (dollars)'),
                enabled: !mutation.isBusy,
                decimal: true,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr(context, 'Default option')),
                value: _default,
                onChanged: mutation.isBusy
                    ? null
                    : (value) => setState(() => _default = value),
              ),
              _textField(
                _sort,
                tr(context, 'Sort order'),
                enabled: !mutation.isBusy,
              ),
              if (input == null)
                Text(
                  tr(
                    context,
                    'Name is required. Price accepts up to two decimals, including negative values. Sort order must be an integer.',
                  ),
                  style: TextStyle(color: PelinesColors.destructive),
                ),
            ],
    );
  }

  List<Widget> _inlineFields(bool busy) => [
    _InlineName(
      field: _textField(
        _name,
        tr(context, 'Name'),
        enabled: !busy,
        maxLength: 80,
        compact: true,
      ),
      trailing: widget.trailing,
    ),
    _InlinePair(
      first: _textField(
        _price,
        tr(context, 'Price'),
        enabled: !busy,
        decimal: true,
        compact: true,
      ),
      second: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          tr(context, 'Default option'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        value: _default,
        onChanged: busy
            ? null
            : (value) {
                if (value != null) setState(() => _default = value);
              },
      ),
    ),
    _InlineAdvanced(
      children: [
        _textField(
          _sort,
          tr(context, 'Sort order'),
          enabled: !busy,
          compact: true,
        ),
      ],
    ),
    if (_input == null)
      Text(
        tr(
          context,
          'Name is required. Price accepts up to two decimals, including negative values. Sort order must be an integer.',
        ),
        style: TextStyle(color: PelinesColors.destructive),
      ),
  ];
}

Widget _textField(
  TextEditingController controller,
  String label, {
  required bool enabled,
  int? maxLength,
  bool decimal = false,
  bool compact = false,
}) => Builder(
  builder: (context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      enabled: enabled,
      maxLength: maxLength,
      style: compact ? Theme.of(context).textTheme.bodyMedium : null,
      keyboardType: maxLength != null
          ? TextInputType.text
          : TextInputType.numberWithOptions(signed: decimal, decimal: decimal),
      decoration: compact
          ? PelinesControlStyles.input(label: label).copyWith(
              isDense: true,
              prefixText: decimal ? r'$ ' : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              constraints: const BoxConstraints(minHeight: 48),
            )
          : PelinesControlStyles.input(label: label),
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
    this.inline = false,
    this.onCancel,
    this.inlineCard = false,
    this.inlineCardBottomPadding = PelinesSpacing.sm,
  });
  final double inlineCardBottomPadding;
  final bool inlineCard;
  final bool inline;
  final VoidCallback? onCancel;
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
    if (discard == true && context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (inline) {
      final content = Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...children,
            if (message != null)
              Semantics(liveRegion: true, child: Text(message!)),
            if (busy) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            _InlineButtons(
              busy: busy,
              onCancel: onCancel,
              onSave: onSave,
              saveLabel: saveLabel,
            ),
          ],
        ),
      );
      return inlineCard
          ? PelinesCard(
              padding: EdgeInsets.fromLTRB(
                PelinesSpacing.sm,
                PelinesSpacing.sm,
                PelinesSpacing.sm,
                inlineCardBottomPadding,
              ),
              child: content,
            )
          : content;
    }
    return AdminPopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (popped, result) async {
        if (!popped) await _leave(context);
      },
      child: Scaffold(
        appBar: AdminAppBar(
          title: Text(
            title,
            style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
          ),
          leading: IconButton(
            onPressed: busy ? null : () => _leave(context),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: PelinesPageBody(
          child: MenuFormList(
            padding: const EdgeInsets.all(PelinesSpacing.lg),
            children: <Widget>[
              ...children,
              if (message != null) Text(message!),
              const SizedBox(height: 12),
              PelinesActionBar(
                children: <Widget>[
                  OutlinedButton(
                    style: PelinesControlStyles.button(
                      PelinesButtonVariant.secondary,
                    ),
                    onPressed: busy ? null : () => _leave(context),
                    child: Text(tr(context, 'Cancel')),
                  ),
                  FilledButton(
                    style: PelinesControlStyles.button(
                      PelinesButtonVariant.primary,
                    ),
                    onPressed: busy ? null : onSave,
                    child: PelinesButtonLabel(
                      busy: busy,
                      label: busy ? tr(context, 'Saving...') : saveLabel,
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
}

class _InlineName extends StatelessWidget {
  const _InlineName({required this.field, this.trailing});
  final Widget field;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: field),
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
    ],
  );
}

class _InlinePair extends StatelessWidget {
  const _InlinePair({required this.first, required this.second});
  final Widget first, second;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth <
          240 * MediaQuery.textScalerOf(context).scale(1)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 8), second],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 12),
          Expanded(child: second),
        ],
      );
    },
  );
}

class _InlineAdvanced extends StatelessWidget {
  const _InlineAdvanced({
    required this.children,
    this.initiallyExpanded = false,
  });
  final List<Widget> children;
  final bool initiallyExpanded;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(
      tr(context, 'Advanced options'),
      style: Theme.of(context).textTheme.bodyMedium,
    ),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(top: 8),
    maintainState: true,
    initiallyExpanded: initiallyExpanded,
    children: children,
  );
}

class _InlineButtons extends StatelessWidget {
  const _InlineButtons({
    required this.busy,
    required this.saveLabel,
    this.onCancel,
    this.onSave,
  });
  final bool busy;
  final String saveLabel;
  final VoidCallback? onCancel, onSave;
  @override
  Widget build(BuildContext context) {
    final reset = OutlinedButton(
      style: PelinesControlStyles.button(PelinesButtonVariant.secondary),
      onPressed: busy ? null : onCancel,
      child: Text(tr(context, 'Reset changes'), textAlign: TextAlign.center),
    );
    final save = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: PelinesColors.brandPrimary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: PelinesColors.mutedSurface,
        disabledForegroundColor: PelinesColors.textSecondary,
        minimumSize: const Size(48, 48),
        shape: const StadiumBorder(),
      ),
      onPressed: busy ? null : onSave,
      child: Text(
        busy ? tr(context, 'Saving...') : saveLabel,
        textAlign: TextAlign.center,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >=
            240 * MediaQuery.textScalerOf(context).scale(1)) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: reset),
                const SizedBox(width: 12),
                Expanded(child: save),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [reset, const SizedBox(height: 8), save],
        );
      },
    );
  }
}
