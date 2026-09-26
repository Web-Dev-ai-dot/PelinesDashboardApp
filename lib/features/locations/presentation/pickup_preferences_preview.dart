import 'package:flutter/material.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/app_theme.dart';

/// Non-operational UX preview. Scalar seeds are read once; drafts never leave
/// this widget. No repository/provider access or save callback is permitted.
class PickupPreferencesPreview extends StatefulWidget {
  const PickupPreferencesPreview({
    required this.regular,
    required this.preferences,
    required this.autoAccept,
    super.key,
  });

  final bool regular;
  final Map<String, dynamic>? preferences;
  final Widget autoAccept;

  @override
  State<PickupPreferencesPreview> createState() =>
      _PickupPreferencesPreviewState();
}

class _PickupPreferencesPreviewState extends State<PickupPreferencesPreview> {
  late bool _accept;
  late final TextEditingController _minimum;
  late final TextEditingController _capacity;
  String get _kind => widget.regular ? 'regular' : 'catering';

  @override
  void initState() {
    super.initState();
    final suffix = widget.regular ? 'Regular' : 'Catering';
    final prefs = widget.preferences;
    final accept = prefs?['accept$suffix'];
    _accept = accept is bool ? accept : true;
    // Preserve present numeric text for local validation; never normalize JSON.
    _minimum = TextEditingController(
      text: (prefs?['min$suffix'] ?? (widget.regular ? 15 : 150)).toString(),
    );
    _capacity = TextEditingController(
      text: (prefs?['cap$suffix'] ?? (widget.regular ? 80 : 6)).toString(),
    );
  }

  @override
  void dispose() {
    _minimum.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Widget _preview(BuildContext context, List<Widget> children) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _input(BuildContext context, bool money) {
    final controller = money ? _minimum : _capacity;
    final valid = (money ? RegExp(r'^\d+(\.\d{1,2})?$') : RegExp(r'^\d+$'))
        .hasMatch(controller.text.trim());
    return TextField(
      key: Key('pickup-preview-$_kind-${money ? 'minimum' : 'capacity'}'),
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: money),
      onChanged: (_) => setState(() {}),
      decoration:
          PelinesControlStyles.input(
            label: tr(context, money ? 'Minimum purchase' : 'Daily capacity'),
          ).copyWith(
            prefixText: money ? '\$ ' : null,
            helperText: tr(context, 'Not enforced yet'),
            helperMaxLines: 3,
            errorMaxLines: 4,
            errorText: valid
                ? null
                : tr(
                    context,
                    money
                        ? 'Enter an amount of 0 or more with up to 2 decimals.'
                        : 'Enter a whole number of 0 or more.',
                  ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _preview(context, [
        Text(
          tr(
            context,
            'These settings are shown for interface review. They are not currently enforced when orders are placed.',
          ),
        ),
        SwitchListTile(
          key: Key('pickup-preview-$_kind-accept'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            tr(
              context,
              widget.regular
                  ? 'Accept regular orders'
                  : 'Accept catering orders',
            ),
          ),
          subtitle: Text(tr(context, 'Not enforced yet')),
          value: _accept,
          onChanged: (value) => setState(() => _accept = value),
        ),
      ]),
      const SizedBox(height: 16),
      widget.autoAccept,
      const SizedBox(height: 16),
      _preview(context, [
        _input(context, true),
        const SizedBox(height: 16),
        _input(context, false),
      ]),
    ],
  );
}
