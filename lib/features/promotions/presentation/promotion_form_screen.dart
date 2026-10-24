import '../../locations/presentation/operations_parity_widgets.dart';
import '../../../app/theme/app_theme.dart';

import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../core/api/api_exception.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../models/discount.dart';
import '../models/promotion_code_generator.dart';
import '../models/promotion_write.dart';
import '../providers/promotions_providers.dart';

class PromotionFormScreen extends ConsumerWidget {
  const PromotionFormScreen({
    super.key,
    this.discountId,
    this.generateCode = false,
  });
  final bool generateCode;
  final String? discountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Location? location = ref.watch(currentLocationProvider).value;
    if (location == null) {
      return Scaffold(
        body: Center(
          child: Text(tr(context, 'Choose a location to continue.')),
        ),
      );
    }
    if (discountId == null) {
      return _PromotionForm(
        key: ValueKey('create-$generateCode'),
        location: location,
        generateCode: generateCode,
      );
    }
    return ref
        .watch(promotionsProvider)
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (Object error, StackTrace stack) => Scaffold(
            appBar: AdminAppBar(
              title: Text(
                tr(context, 'Edit Promotion'),
                style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
              ),
            ),
            body: Center(
              child: Text(
                tr(
                  context,
                  error is ApiException
                      ? error.message
                      : 'Promotions could not be loaded.',
                ),
              ),
            ),
          ),
          data: (List<Discount> values) {
            final Discount? discount = _find(values, discountId!);
            if (discount == null) {
              return Scaffold(
                body: Center(
                  child: Text(tr(context, 'This promotion no longer exists.')),
                ),
              );
            }
            if (discount.locationId != null &&
                discount.locationId != location.id) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      tr(
                        context,
                        'This promotion cannot be edited from mobile.',
                      ),
                    ),
                  ),
                ),
              );
            }
            return _PromotionForm(
              key: ValueKey('edit-${discount.id}'),
              location: location,
              initial: discount,
            );
          },
        );
  }

  Discount? _find(List<Discount> values, String id) {
    for (final Discount value in values) {
      if (value.id == id) return value;
    }
    return null;
  }
}

class _PromotionForm extends ConsumerStatefulWidget {
  const _PromotionForm({
    super.key,
    required this.location,
    this.initial,
    this.generateCode = false,
  });
  final bool generateCode;
  final Location location;
  final Discount? initial;

  @override
  ConsumerState<_PromotionForm> createState() => _PromotionFormState();
}

class _PromotionFormState extends ConsumerState<_PromotionForm> {
  late final TextEditingController _code;
  late final TextEditingController _value;
  late final TextEditingController _minimum;
  late final TextEditingController _usage;
  late String _type;
  late String _appliesTo;
  late bool _unlimited;
  late bool _active;
  DateTime? _startDate;
  DateTime? _endDate;
  late Discount? _snapshot;
  late final Location _openedLocation;
  bool _leaving = false;
  bool _createGlobal = false;
  bool get _busy =>
      _confirming || _leaving || ref.read(promotionFormMutationProvider).isBusy;
  bool _attempted = false;
  bool _confirming = false;
  bool get _global => _editing && _snapshot!.locationId == null;

  bool get _editing => _snapshot != null;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initial;
    _openedLocation = widget.location;
    final PromotionDraft initial = _snapshot == null
        ? PromotionDraft.create()
        : PromotionDraft.fromDiscount(_snapshot!);
    _code = TextEditingController(
      text: widget.generateCode ? generatePromotionCode() : initial.code,
    );
    _value = TextEditingController(text: initial.valueText);
    _minimum = TextEditingController(text: initial.minimumText);
    _usage = TextEditingController(text: initial.usageLimitText);
    _type = initial.type;
    _appliesTo = initial.appliesTo;
    _unlimited = initial.unlimited;
    _active = initial.isActive;
    _startDate = initial.startDate;
    _endDate = initial.endDate;
    for (final TextEditingController controller in <TextEditingController>[
      _code,
      _value,
      _minimum,
      _usage,
    ]) {
      controller.addListener(_changed);
    }
    Future<void>.microtask(
      () => ref.read(promotionFormMutationProvider.notifier).reset(),
    );
  }

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _minimum.dispose();
    _usage.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  PromotionDraft get _draft => PromotionDraft(
    code: _code.text,
    type: _type,
    valueText: _value.text,
    appliesTo: _appliesTo,
    minimumText: _minimum.text,
    startDate: _startDate,
    endDate: _endDate,
    usageLimitText: _usage.text,
    unlimited: _unlimited,
    isActive: _active,
  );

  PromotionWriteResult get _validation {
    final result = _draft.validate(_openedLocation.id);
    if (result.body == null) return result;
    if (!_editing) {
      return PromotionWriteResult.valid({
        ...result.body!,
        'locationId': _createGlobal ? null : _openedLocation.id,
      });
    }
    final initial = PromotionDraft.fromDiscount(_snapshot!);
    final body = {...result.body!};
    // Preserve original instants when their calendar fields were not changed.
    if (_startDate == initial.startDate) {
      body['startsAt'] = _snapshot!.startsAt?.toUtc().toIso8601String();
    }
    if (_endDate == initial.endDate) {
      body['endsAt'] = _snapshot!.endsAt?.toUtc().toIso8601String();
    }
    return PromotionWriteResult.valid(body);
  }

  bool get _dirty {
    final Map<String, dynamic>? desired = _validation.body;
    if (!_editing) {
      final PromotionDraft empty = PromotionDraft.create();
      return _code.text.isNotEmpty ||
          _value.text.isNotEmpty ||
          _minimum.text != empty.minimumText ||
          _type != empty.type ||
          _appliesTo != empty.appliesTo ||
          !_unlimited ||
          _usage.text.isNotEmpty ||
          _startDate != null ||
          _endDate != null ||
          !_active ||
          _createGlobal;
    }
    if (desired == null) {
      final initial = PromotionDraft.fromDiscount(_snapshot!);
      return _code.text != initial.code ||
          _value.text != initial.valueText ||
          _minimum.text != initial.minimumText ||
          _usage.text != initial.usageLimitText ||
          _type != initial.type ||
          _appliesTo != initial.appliesTo ||
          _unlimited != initial.unlimited ||
          _active != initial.isActive ||
          _startDate != initial.startDate ||
          _endDate != initial.endDate;
    }
    return partialPromotionPatch(
      discountEditableBody(_snapshot!),
      desired,
    ).isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final PromotionFormMutationState operation = ref.watch(
      promotionFormMutationProvider,
    );
    final PromotionWriteResult validation = _validation;
    return AdminPopScope<void>(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (bool didPop, void result) async {
        if (!didPop && !_busy) await _leave();
      },
      child: Scaffold(
        appBar: AdminAppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editing
                    ? tr(context, 'Edit Promotion')
                    : tr(context, 'Add Promotion'),
                style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
              ),
              if (_global)
                Text(
                  tr(context, 'All locations'),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
            ],
          ),
          leading: IconButton(
            onPressed: operation.isBusy ? null : _leave,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: _formBody(operation, validation),
      ),
    );
  }

  Widget _formBody(
    PromotionFormMutationState operation,
    PromotionWriteResult validation,
  ) {
    final busy = operation.isBusy || _confirming || _leaving;
    return SafeArea(
      top: false,
      child: OperationsFormList(
        padding: const EdgeInsets.all(PelinesSpacing.lg),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        context,
                        _editing
                            ? 'Edit discount code'
                            : 'Create discount code',
                      ),
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tr(
                        context,
                        'Configure the discount code customers can use at checkout.',
                      ),
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: PelinesColors.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('promotion-form-close'),
                tooltip: tr(context, 'Close'),
                onPressed: busy ? null : _leave,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Divider(height: 40),
          _editText(
            'Discount code',
            _code,
            'promotion-code',
            busy: busy,
            formatters: [LengthLimitingTextInputFormatter(40)],
            capitalization: TextCapitalization.characters,
          ),
          Text(
            tr(context, 'This is the code customers will enter at checkout.'),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: PelinesColors.textSecondary),
          ),
          if (!_editing) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('promotion-regenerate-code'),
                onPressed: busy ? null : _regenerate,
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: Text(tr(context, 'Generate another code')),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _pair(
            'promotion-type-value',
            _editSelect(
              'Discount type',
              _type,
              {'percent': 'Percentage', 'fixed': 'Fixed amount'},
              (v) => setState(() => _type = v),
              busy,
            ),
            _editText(
              'Value',
              _value,
              'promotion-value',
              busy: busy,
              number: true,
              prefix: _type == 'fixed' ? r'$' : null,
              suffix: _type == 'percent' ? '%' : null,
            ),
          ),
          _editSelect(
            'Applies to menu type',
            _appliesTo,
            {
              'regular': 'Regular orders',
              'catering': 'Catering orders',
              'both': 'Regular & Catering',
            },
            (v) => setState(() => _appliesTo = v),
            busy,
          ),
          const SizedBox(height: 20),
          if (_editing)
            PelinesReadOnlyField(
              label: tr(context, 'Location'),
              value: _global
                  ? tr(context, 'All locations')
                  : _openedLocation.name,
            )
          else ...[
            _editSelect(
              'Location',
              _createGlobal ? 'global' : 'local',
              {
                'local': _openedLocation.name,
                'global': tr(context, 'All locations'),
              },
              (value) => setState(() => _createGlobal = value == 'global'),
              busy,
            ),
            if (_createGlobal)
              Text(tr(context, 'This promotion applies to all locations.')),
          ],
          const SizedBox(height: 24),
          _editText(
            'Minimum order amount',
            _minimum,
            'promotion-minimum',
            busy: busy,
            number: true,
            prefix: r'$',
          ),
          _dateFields(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(context, 'Unlimited usage')),
            value: _unlimited,
            onChanged: busy ? null : (v) => setState(() => _unlimited = v),
          ),
          _editText(
            'Usage limit (total)',
            _usage,
            'promotion-usage',
            busy: busy || _unlimited,
            number: true,
          ),
          Text(
            tr(
              context,
              'Total number of times this code can be used. Enable unlimited usage for no limit.',
            ),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: PelinesColors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (_editing) ...[
            Text(
              tr(context, 'Usage claimed'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text(
              _snapshot!.usageLabel
                  .replaceFirst('claimed', tr(context, 'claimed'))
                  .replaceFirst('Unlimited', tr(context, 'Unlimited')),
            ),
            Text(
              tr(
                context,
                'Usage claimed may include orders that were created but not completed.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 24),
          PelinesCard(
            variant: PelinesCardVariant.compact,
            child: Material(
              type: MaterialType.transparency,
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tr(context, 'Active'),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  tr(
                    context,
                    'When active, customers can use this discount code at checkout during the valid date range.',
                  ),
                ),
                value: _active,
                onChanged: busy ? null : (v) => setState(() => _active = v),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if ((_attempted || _dirty) && validation.message != null)
            Text(
              tr(context, validation.message!),
              key: const Key('promotion-validation-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (operation.phase == PromotionFormPhase.error &&
              operation.message != null)
            Text(
              tr(context, operation.message!),
              key: const Key('promotion-save-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 16,
            runSpacing: 12,
            children: [
              OutlinedButton(
                key: const Key('promotion-form-cancel'),
                style: PelinesControlStyles.button(
                  PelinesButtonVariant.secondary,
                ),
                onPressed: busy ? null : _leave,
                child: Text(tr(context, 'Cancel')),
              ),
              FilledButton(
                key: const Key('promotion-form-save'),
                style: PelinesControlStyles.button(
                  PelinesButtonVariant.primary,
                ),
                onPressed: busy || !_dirty || !validation.isValid
                    ? null
                    : _save,
                child: Text(
                  tr(
                    context,
                    operation.isBusy ? 'Saving…' : 'Save discount code',
                  ),
                ),
              ),
            ],
          ),
          if (operation.isBusy) const LinearProgressIndicator(),
        ],
      ),
    );
  }

  Widget _pair(String id, Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) {
      final wide =
          constraints.maxWidth >=
          400 * MediaQuery.textScalerOf(context).scale(1);
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: wide
            ? Row(
                key: ValueKey('$id-row'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: first),
                  const SizedBox(width: 20),
                  Expanded(child: second),
                ],
              )
            : Column(
                key: ValueKey('$id-column'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [first, const SizedBox(height: 16), second],
              ),
      );
    },
  );

  Widget _label(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      tr(context, label),
      style: Theme.of(context).textTheme.bodyLarge
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
  Widget _editText(
    String label,
    TextEditingController controller,
    String id, {
    required bool busy,
    bool number = false,
    String? prefix,
    String? suffix,
    List<TextInputFormatter>? formatters,
    TextCapitalization capitalization = TextCapitalization.none,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(label),
        Semantics(
          label: tr(context, label),
          child: TextField(
            key: ValueKey(id),
            controller: controller,
            enabled: !busy,
            textCapitalization: capitalization,
            inputFormatters: formatters,
            keyboardType: number
                ? const TextInputType.numberWithOptions(decimal: true)
                : null,
            decoration: PelinesControlStyles.input().copyWith(
              prefixText: prefix,
              suffixText: suffix,
            ),
          ),
        ),
      ],
    ),
  );
  Widget _editSelect(
    String label,
    String selected,
    Map<String, String> options,
    ValueChanged<String> changed,
    bool busy,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _label(label),
      Semantics(
        label: tr(context, label),
        child: DropdownButtonFormField<String>(
          key: ValueKey('$label-$selected'),
          initialValue: selected,
          isExpanded: true,
          itemHeight: null,
          decoration: PelinesControlStyles.input(),
          items: options.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(tr(context, e.value)),
                ),
              )
              .toList(),
          onChanged: busy
              ? null
              : (value) {
                  if (value != null) changed(value);
                },
        ),
      ),
    ],
  );

  Future<void> _pickDate(
    DateTime? value,
    ValueChanged<DateTime?> changed,
  ) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: DateTime(
        value != null && value.year < now.year - 10
            ? value.year
            : now.year - 10,
      ),
      lastDate: DateTime(
        value != null && value.year > now.year + 20
            ? value.year + 1
            : now.year + 20,
      ),
    );
    if (selected != null && mounted) changed(selected);
  }

  String _dateText(DateTime? value) => value == null
      ? tr(context, 'No date')
      : DateFormat.yMMMd(Localizations.localeOf(context).toString())
            .format(value);

  Widget _dateFields() => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      key: const ValueKey('promotion-date-pair-column'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _editDate(
          'Start date',
          _startDate,
          (v) => setState(() => _startDate = v),
        ),
        const SizedBox(height: 16),
        _editDate('End date', _endDate, (v) => setState(() => _endDate = v)),
      ],
    ),
  );

  Widget _editDate(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> changed,
  ) => Column(
    key: ValueKey('promotion-date-field-$label'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _label(label),
      Semantics(
        label: tr(context, label),
        button: true,
        enabled: !_busy,
        child: InkWell(
          onTap: _busy ? null : () => _pickDate(value, changed),
          child: InputDecorator(
            key: ValueKey('promotion-date-input-$label'),
            decoration: PelinesControlStyles.input(),
            child: Row(
              children: [
                Expanded(child: Text(_dateText(value))),
                if (value != null)
                  IconButton(
                    tooltip: tr(context, 'Clear date'),
                    onPressed: _busy ? null : () => changed(null),
                    icon: const Icon(Icons.clear),
                  ),
                IconButton(
                  tooltip: tr(context, label),
                  onPressed: _busy ? null : () => _pickDate(value, changed),
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  void _regenerate() {
    if (_busy) return;
    _code.text = generatePromotionCode();
    ref.read(promotionFormMutationProvider.notifier).reset();
  }

  Future<void> _save() async {
    if (_confirming || ref.read(promotionFormMutationProvider).isBusy) return;
    setState(() => _attempted = true);
    final Map<String, dynamic>? body = _validation.body;
    if (body == null) return;
    final original = _snapshot;
    final global = _global;
    final contextLocation = _openedLocation.id;
    if (global) {
      setState(() => _confirming = true);
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr(ctx, 'Modify global promotion')),
              content: Text(
                '${_snapshot!.code}\n\n${tr(ctx, 'Changes will affect all locations where this promotion applies.')}',
              ),
              actions: [
                TextButton(
                  key: const Key('global-save-cancel'),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(tr(ctx, 'Cancel')),
                ),
                FilledButton(
                  key: const Key('global-save-confirm'),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(tr(ctx, 'Save Changes')),
                ),
              ],
            ),
          ) ??
          false;
      if (!mounted) return;
      setState(() => _confirming = false);
      if (!confirmed) return;
    }
    final PromotionFormMutationController controller = ref.read(
      promotionFormMutationProvider.notifier,
    );
    if (_editing) {
      await controller.edit(
        discountId: original!.id,
        locationId: contextLocation,
        originalUpdatedAt: original.updatedAt,
        global: global,
        desired: body,
      );
    } else {
      await controller.create(locationId: _openedLocation.id, body: body);
    }
    if (!mounted) return;
    final PromotionFormMutationState result = ref.read(
      promotionFormMutationProvider,
    );
    if (result.phase == PromotionFormPhase.success && result.resultId != null) {
      context.go(
        _editing ? '/app/promotions/${result.resultId}' : '/app/promotions',
      );
      return;
    }
    if (result.phase == PromotionFormPhase.conflict) {
      final bool reload =
          await showDialog<bool>(
            context: context,
            builder: (BuildContext dialogContext) => AlertDialog(
              title: Text(
                tr(dialogContext, 'This promotion was changed elsewhere.'),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(tr(dialogContext, 'Cancel')),
                ),
                FilledButton(
                  style: PelinesControlStyles.button(
                    PelinesButtonVariant.primary,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(tr(dialogContext, 'Reload')),
                ),
              ],
            ),
          ) ??
          false;
      if (reload && mounted) {
        final List<Discount>? values = ref.read(promotionsProvider).value;
        if (values != null) {
          for (final Discount value in values) {
            if (value.id == _snapshot!.id) {
              _loadCanonical(value);
              break;
            }
          }
        }
      }
    }
  }

  void _loadCanonical(Discount value) {
    final PromotionDraft draft = PromotionDraft.fromDiscount(value);
    setState(() {
      _snapshot = value;
      _code.text = draft.code;
      _value.text = draft.valueText;
      _minimum.text = draft.minimumText;
      _usage.text = draft.usageLimitText;
      _type = draft.type;
      _appliesTo = draft.appliesTo;
      _unlimited = draft.unlimited;
      _active = draft.isActive;
      _startDate = draft.startDate;
      _endDate = draft.endDate;
      _attempted = false;
      ref.read(promotionFormMutationProvider.notifier).reset();
    });
  }

  void _returnToPrevious() {
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
    } else {
      context.go('/app/promotions');
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (!_dirty) {
      _returnToPrevious();
      return;
    }
    setState(() => _leaving = true);
    try {
      final discard =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr(ctx, 'Discard changes?')),
              actions: [
                TextButton(
                  key: const Key('promotion-discard-cancel'),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(tr(ctx, 'Keep editing')),
                ),
                FilledButton(
                  key: const Key('promotion-discard-confirm'),
                  style: PelinesControlStyles.button(
                    PelinesButtonVariant.primary,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(tr(ctx, 'Discard')),
                ),
              ],
            ),
          ) ??
          false;
      if (discard && mounted) _returnToPrevious();
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }
}
