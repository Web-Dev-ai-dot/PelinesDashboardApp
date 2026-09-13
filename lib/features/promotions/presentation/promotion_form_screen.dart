import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../models/discount.dart';
import '../models/promotion_write.dart';
import '../providers/promotions_providers.dart';

class PromotionFormScreen extends ConsumerWidget {
  const PromotionFormScreen({super.key, this.discountId});
  final String? discountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Location? location = ref.watch(currentLocationProvider).value;
    if (location == null) {
      return const Scaffold(
        body: Center(child: Text('Choose a location to continue.')),
      );
    }
    if (discountId == null) {
      return _PromotionForm(location: location);
    }
    return ref
        .watch(promotionsProvider)
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (Object error, StackTrace stack) => Scaffold(
            appBar: AdminAppBar(title: const Text('Edit Promotion')),
            body: Center(child: Text(error.toString())),
          ),
          data: (List<Discount> values) {
            final Discount? discount = _find(values, discountId!);
            if (discount == null) {
              return const Scaffold(
                body: Center(child: Text('This promotion no longer exists.')),
              );
            }
            if (discount.locationId != location.id) {
              return const Scaffold(
                body: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('This promotion cannot be edited from mobile.'),
                  ),
                ),
              );
            }
            return _PromotionForm(location: location, initial: discount);
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
  const _PromotionForm({required this.location, this.initial});
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
  bool _attempted = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final PromotionDraft initial = widget.initial == null
        ? PromotionDraft.create()
        : PromotionDraft.fromDiscount(widget.initial!);
    _code = TextEditingController(text: initial.code);
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

  PromotionWriteResult get _validation => _draft.validate(widget.location.id);

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
          !_active;
    }
    if (desired == null) return true;
    return partialPromotionPatch(
      discountEditableBody(widget.initial!),
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
      canPop: !_dirty || operation.isBusy,
      onPopInvokedWithResult: (bool didPop, void result) async {
        if (!didPop && !operation.isBusy) await _leave();
      },
      child: Scaffold(
        appBar: AdminAppBar(
          title: Text(_editing ? 'Edit Promotion' : 'Add Promotion'),
          leading: IconButton(
            onPressed: operation.isBusy ? null : _leave,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(PelinesSpacing.lg),
          children: <Widget>[
            PelinesReadOnlyField(
              label: 'Location',
              value: widget.location.name,
            ),
            const SizedBox(height: PelinesSpacing.lg),
            _textField(
              controller: _code,
              label: 'Code',
              capitalization: TextCapitalization.characters,
              formatters: <TextInputFormatter>[
                LengthLimitingTextInputFormatter(40),
              ],
            ),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Discount Type',
                border: OutlineInputBorder(),
              ),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'percent', child: Text('Percentage')),
                DropdownMenuItem(value: 'fixed', child: Text('Fixed amount')),
              ],
              onChanged: operation.isBusy
                  ? null
                  : (String? value) => setState(() => _type = value!),
            ),
            const SizedBox(height: 12),
            _textField(
              controller: _value,
              label: 'Discount',
              prefix: _type == 'fixed' ? r'$' : null,
              suffix: _type == 'percent' ? '%' : null,
              number: true,
            ),
            DropdownButtonFormField<String>(
              initialValue: _appliesTo,
              decoration: const InputDecoration(
                labelText: 'Applies To',
                border: OutlineInputBorder(),
              ),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(
                  value: 'regular',
                  child: Text('Regular orders'),
                ),
                DropdownMenuItem(
                  value: 'catering',
                  child: Text('Catering orders'),
                ),
                DropdownMenuItem(
                  value: 'both',
                  child: Text('Regular & Catering'),
                ),
              ],
              onChanged: operation.isBusy
                  ? null
                  : (String? value) => setState(() => _appliesTo = value!),
            ),
            const SizedBox(height: 12),
            _textField(
              controller: _minimum,
              label: 'Minimum Subtotal',
              prefix: r'$',
              number: true,
            ),
            _dateTile('Start Date', _startDate, (DateTime? value) {
              setState(() => _startDate = value);
            }),
            _dateTile('End Date', _endDate, (DateTime? value) {
              setState(() => _endDate = value);
            }),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Unlimited usage'),
              value: _unlimited,
              onChanged: operation.isBusy
                  ? null
                  : (bool value) => setState(() => _unlimited = value),
            ),
            if (!_unlimited)
              _textField(
                controller: _usage,
                label: 'Usage Limit',
                number: true,
              ),
            if (_editing) ...<Widget>[
              Text(
                'Usage claimed',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(widget.initial!.usageLabel),
              const SizedBox(height: 4),
              const Text(
                'Usage claimed may include orders that were created but not completed.',
              ),
              const SizedBox(height: 12),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              value: _active,
              onChanged: operation.isBusy
                  ? null
                  : (bool value) => setState(() => _active = value),
            ),
            if ((_attempted || _dirty) && validation.message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  validation.message!,
                  key: const Key('promotion-validation-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (operation.message != null &&
                operation.phase == PromotionFormPhase.error)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  operation.message!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              key: const Key('promotion-form-save'),
              onPressed: operation.isBusy || !_dirty || !validation.isValid
                  ? null
                  : _save,
              child: Text(
                operation.isBusy
                    ? 'Saving…'
                    : _editing
                    ? 'Save Changes'
                    : 'Create Promotion',
              ),
            ),
            if (operation.isBusy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? prefix,
    String? suffix,
    bool number = false,
    TextCapitalization capitalization = TextCapitalization.none,
    List<TextInputFormatter>? formatters,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      textCapitalization: capitalization,
      inputFormatters: formatters,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _dateTile(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> changed,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(
      value == null
          ? 'No ${label.toLowerCase()}'
          : DateFormat.yMMMd().format(value),
    ),
    trailing: value == null
        ? const Icon(Icons.calendar_month_outlined)
        : IconButton(
            tooltip: 'Clear $label',
            onPressed: () => changed(null),
            icon: const Icon(Icons.clear),
          ),
    onTap: () async {
      final DateTime now = DateTime.now();
      final DateTime? selected = await showDatePicker(
        context: context,
        initialDate: value ?? now,
        firstDate: DateTime(now.year - 10),
        lastDate: DateTime(now.year + 20),
      );
      if (selected != null && mounted) changed(selected);
    },
  );

  Future<void> _save() async {
    setState(() => _attempted = true);
    final Map<String, dynamic>? body = _validation.body;
    if (body == null) return;
    final PromotionFormMutationController controller = ref.read(
      promotionFormMutationProvider.notifier,
    );
    if (_editing) {
      await controller.edit(
        discountId: widget.initial!.id,
        locationId: widget.location.id,
        originalUpdatedAt: widget.initial!.updatedAt,
        desired: body,
      );
    } else {
      await controller.create(locationId: widget.location.id, body: body);
    }
    if (!mounted) return;
    final PromotionFormMutationState result = ref.read(
      promotionFormMutationProvider,
    );
    if (result.phase == PromotionFormPhase.success && result.resultId != null) {
      context.go('/app/promotions/${result.resultId}');
      return;
    }
    if (result.phase == PromotionFormPhase.conflict) {
      final bool reload =
          await showDialog<bool>(
            context: context,
            builder: (BuildContext dialogContext) => AlertDialog(
              title: const Text('This promotion was changed elsewhere.'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Reload'),
                ),
              ],
            ),
          ) ??
          false;
      if (reload && mounted) {
        final List<Discount>? values = ref.read(promotionsProvider).value;
        if (values != null) {
          for (final Discount value in values) {
            if (value.id == widget.initial!.id) {
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

  Future<void> _leave() async {
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final bool discard =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Discard changes?'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
    if (discard && mounted) Navigator.pop(context);
  }
}
