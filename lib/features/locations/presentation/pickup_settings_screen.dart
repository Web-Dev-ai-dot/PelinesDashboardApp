part of 'store_operations_screen.dart';

class PickupSettingsScreen extends ConsumerStatefulWidget {
  const PickupSettingsScreen({super.key});
  @override
  ConsumerState<PickupSettingsScreen> createState() =>
      _PickupSettingsScreenState();
}

class _PickupSettingsScreenState extends ConsumerState<PickupSettingsScreen> {
  final _dirty = <String, bool>{};
  int _revision = 0;
  String? _locationId;
  bool get _hasChanges => _dirty.values.any((value) => value);
  void _draftChanged(String group, bool dirty) {
    if (mounted) setState(() => _dirty[group] = dirty);
  }

  Future<bool> _leave() async {
    if (ref.read(servicePreferencesWriteProvider) ||
        ref.read(storeOperationsProvider).isBusy) {
      return false;
    }
    if (!_hasChanges) return true;
    final discard =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(tr(context, 'Discard changes?')),
            content: Text(
              tr(context, 'Your unsaved pickup settings will be lost.'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(tr(context, 'Keep editing')),
              ),
              FilledButton(
                style: PelinesControlStyles.button(
                  PelinesButtonVariant.primary,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(tr(context, 'Discard')),
              ),
            ],
          ),
        ) ??
        false;
    if (!discard || !mounted) return false;
    setState(() {
      _dirty.clear();
      _revision++;
    });
    await WidgetsBinding.instance.endOfFrame;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentLocationProvider);
    final operation = ref.watch(storeOperationsProvider);
    final busy = operation.isBusy || ref.watch(servicePreferencesWriteProvider);
    ref.listen<StoreOperationState>(storeOperationsProvider, (previous, next) {
      if (next.message != null && next.message != previous?.message) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr(context, next.message!))));
      }
    });
    return AdminPopScope<void>(
      canPop: !_hasChanges && !busy,
      onRequestLeave: _leave,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _leave() && context.mounted) {
          Navigator.maybePop(context);
        }
      },
      child: AdminSectionScaffold(
        key: const Key('pickup-settings-screen'),
        appBar: AdminAppBar(
          title: Text(
            tr(context, 'Pickup Settings'),
            style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
          ),
        ),
        body: current.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr(context, error.toString()),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    style: PelinesControlStyles.button(
                      PelinesButtonVariant.secondary,
                    ),
                    onPressed: () {
                      ref.invalidate(locationsProvider);
                      ref.invalidate(currentLocationProvider);
                    },
                    child: Text(tr(context, 'Try again')),
                  ),
                ],
              ),
            ),
          ),
          data: (location) {
            if (location == null) {
              return Center(
                child: Text(tr(context, 'Choose a location to continue.')),
              );
            }
            if (_locationId != location.id) {
              _locationId = location.id;
              _dirty.clear();
            }
            return PelinesPageBody(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(PelinesSpacing.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          tr(
                            context,
                            'Turn ordering on or off and manage service preferences, including acceptance, automatic acceptance, minimum purchase, daily capacity and automatic cancellation for this location.',
                          ),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: PelinesColors.textSecondary),
                        ),
                        const SizedBox(height: PelinesSpacing.lg),
                        _PickupAvailabilityCard(
                          key: ValueKey(
                            '${location.id}-availability-$_revision',
                          ),
                          location: location,
                          operation: operation,
                          onDirtyChanged: (value) =>
                              _draftChanged('availability', value),
                        ),
                        const SizedBox(height: PelinesSpacing.xl),
                        Text(
                          tr(context, 'Service Preferences'),
                          style: PelinesTypography.pageTitle(
                            Theme.of(context).textTheme,
                          ),
                        ),
                        const SizedBox(height: PelinesSpacing.sm),
                        Text(
                          tr(
                            context,
                            'Control which orders are accepted and how they are processed for the active location.',
                          ),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: PelinesColors.textSecondary),
                        ),
                        const SizedBox(height: PelinesSpacing.lg),
                        for (final kind in PickupOrderKind.values) ...[
                          PickupServiceCard(
                            key: ValueKey(
                              '${location.id}-${kind.name}-$_revision',
                            ),
                            location: location,
                            kind: kind,
                            onDirtyChanged: (value) =>
                                _draftChanged(kind.name, value),
                          ),
                          const SizedBox(height: PelinesSpacing.lg),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PickupAvailabilityCard extends ConsumerStatefulWidget {
  const _PickupAvailabilityCard({
    required this.location,
    required this.operation,
    required this.onDirtyChanged,
    super.key,
  });
  final Location location;
  final StoreOperationState operation;
  final ValueChanged<bool> onDirtyChanged;
  @override
  ConsumerState<_PickupAvailabilityCard> createState() =>
      _PickupAvailabilityCardState();
}

class _PickupAvailabilityCardState
    extends ConsumerState<_PickupAvailabilityCard> {
  late bool _accepting;
  bool _confirming = false;
  @override
  void initState() {
    super.initState();
    _accepting = widget.location.isAcceptingOrders;
  }

  @override
  void didUpdateWidget(covariant _PickupAvailabilityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location.isAcceptingOrders == _accepting && !_confirming) {
      _accepting = widget.location.isAcceptingOrders;
    }
  }

  Widget _checkbox(
    String title,
    String description,
    bool value,
    ValueChanged<bool?>? change,
    String key,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: PelinesColors.mutedSurface,
      borderRadius: BorderRadius.circular(PelinesRadius.control),
      child: CheckboxListTile(
        key: Key(key),
        contentPadding: const EdgeInsets.all(12),
        controlAffinity: ListTileControlAffinity.trailing,
        title: Text(tr(context, title)),
        subtitle: Text(tr(context, description)),
        value: value,
        onChanged: change,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final busy =
        _confirming ||
        widget.operation.isBusy ||
        ref.watch(servicePreferencesWriteProvider);
    return PelinesSettingsCard(
      key: const Key('pickup-availability-card'),
      children: [
        Text(
          tr(context, 'ORDER AVAILABILITY'),
          style: PelinesTypography.smallLabel,
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            context,
            'Accepting orders — {location}',
          ).replaceAll('{location}', widget.location.name),
          style: PelinesTypography.sectionTitle(Theme.of(context).textTheme),
        ),
        const SizedBox(height: 8),
        Text(tr(context, 'Turn online ordering on or off for this location.')),
        const SizedBox(height: 20),
        _checkbox(
          'Accepting online orders',
          'When disabled, this location will stop accepting new online orders for both regular and catering orders. Existing orders are not cancelled.',
          _accepting,
          busy
              ? null
              : (value) {
                  setState(() => _accepting = value!);
                  widget.onDirtyChanged(
                    _accepting != widget.location.isAcceptingOrders,
                  );
                },
          'accepting-orders-switch',
        ),
        _checkbox(
          'Location active',
          'Read-only here. Manage location activation in the web admin.',
          widget.location.isActive,
          null,
          'pickup-location-active',
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            key: const Key('pickup-availability-save'),
            style: PelinesControlStyles.button(PelinesButtonVariant.primary),
            onPressed: busy || _accepting == widget.location.isAcceptingOrders
                ? null
                : _save,
            child: Text(
              tr(context, widget.operation.isBusy ? 'Saving…' : 'Save changes'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        if (widget.operation.isBusy) const LinearProgressIndicator(),
      ],
    );
  }

  Future<void> _save() async {
    if (_confirming || widget.operation.isBusy) return;
    setState(() => _confirming = true);
    try {
      await _OperationsContent(
        location: widget.location,
        operation: widget.operation,
        section: StoreOperationsSection.locations,
      )._confirmChange(context, ref, widget.location, _accepting);
      if (!mounted) return;
      final canonical = ref.read(currentLocationProvider).value;
      if (canonical?.id == widget.location.id) {
        widget.onDirtyChanged(_accepting != canonical!.isAcceptingOrders);
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }
}
