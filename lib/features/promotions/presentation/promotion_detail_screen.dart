import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../models/discount.dart';
import '../providers/promotions_providers.dart';
import 'promotions_screen.dart';

class PromotionDetailScreen extends ConsumerStatefulWidget {
  const PromotionDetailScreen({super.key, required this.discountId});
  final String discountId;

  @override
  ConsumerState<PromotionDetailScreen> createState() =>
      _PromotionDetailScreenState();
}

class _PromotionDetailScreenState extends ConsumerState<PromotionDetailScreen> {
  DateTime? _openedUpdatedAt;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(promotionMutationProvider.notifier).reset(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Location? location = ref.watch(currentLocationProvider).value;
    final AsyncValue<List<Discount>> source = ref.watch(promotionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Promotion Details')),
      body: source.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: ref.read(promotionsProvider.notifier).refresh,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (List<Discount> values) {
          final Discount? discount = _find(values);
          if (discount == null) {
            return const Center(
              child: Text('This promotion no longer exists.'),
            );
          }
          final bool applies =
              location != null &&
              (discount.locationId == null ||
                  discount.locationId == location.id);
          if (!applies) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This promotion is not available for the selected location.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          _openedUpdatedAt ??= discount.updatedAt;
          return _Details(
            discount: discount,
            location: location,
            openedUpdatedAt: _openedUpdatedAt!,
            onReloadSnapshot: () => setState(() {
              _openedUpdatedAt = discount.updatedAt;
              ref.read(promotionMutationProvider.notifier).reset();
            }),
          );
        },
      ),
    );
  }

  Discount? _find(List<Discount> discounts) {
    for (final Discount discount in discounts) {
      if (discount.id == widget.discountId) return discount;
    }
    return null;
  }
}

class _Details extends ConsumerWidget {
  const _Details({
    required this.discount,
    required this.location,
    required this.openedUpdatedAt,
    required this.onReloadSnapshot,
  });
  final Discount discount;
  final Location location;
  final DateTime openedUpdatedAt;
  final VoidCallback onReloadSnapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PromotionMutationState operation = ref.watch(
      promotionMutationProvider,
    );
    final bool global = discount.locationId == null;
    final bool manageable = discount.locationId == location.id;
    return ListView(
      padding: const EdgeInsets.all(PelinesSpacing.lg),
      children: <Widget>[
        PelinesStateBadge(
          label: global
              ? 'All locations · Read-only'
              : '${location.name} · Editable',
          foreground: global
              ? PelinesColors.textSecondary
              : PelinesColors.brandPrimary,
          background: global
              ? PelinesColors.mutedSurface
              : PelinesColors.brandPrimarySoft,
          icon: global ? Icons.lock_outline : Icons.edit_outlined,
        ),
        const SizedBox(height: PelinesSpacing.md),
        _Field('Code', discount.code),
        _StatusField(discount.effectiveStatus(DateTime.now())),
        _Field('Discount', discount.discountLabel),
        _Field('Applies to', discount.appliesToLabel),
        _Field('Scope', global ? 'All locations' : location.name),
        _Field('Minimum order subtotal', discount.minimumLabel),
        _Field('Starts', discount.startsLabel ?? 'No start date'),
        _Field('Ends', discount.endsLabel ?? 'No end date'),
        _Field('Usage claimed', discount.usageLabel),
        const Padding(
          padding: EdgeInsets.only(bottom: 20),
          child: Text(
            'This count may include orders that were created but not completed.',
          ),
        ),
        _Field('Active setting', discount.isActive ? 'On' : 'Off'),
        if (global)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(PelinesSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.lock_outline, color: PelinesColors.textSecondary),
                  SizedBox(width: PelinesSpacing.sm),
                  Expanded(
                    child: Text(
                      'This promotion applies to all locations and can only be managed from the desktop dashboard.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (manageable) ...<Widget>[
          OutlinedButton.icon(
            key: const Key('edit-promotion'),
            onPressed: operation.isBusy
                ? null
                : () => context.push('/app/promotions/${discount.id}/edit'),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit Promotion'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('promotion-active-action'),
            onPressed: operation.isBusy
                ? null
                : () => _confirmAndSave(context, ref),
            child: Text(
              operation.isBusy
                  ? 'Checking…'
                  : discount.isActive
                  ? 'Deactivate promotion'
                  : 'Activate promotion',
            ),
          ),
          if (operation.isBusy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
        ],
      ],
    );
  }

  Future<void> _confirmAndSave(BuildContext context, WidgetRef ref) async {
    final bool activating = !discount.isActive;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(
              '${activating ? 'Activate' : 'Deactivate'} ${discount.code}?',
            ),
            content: Text(
              activating
                  ? 'The promotion will become eligible again if its dates, usage limit, location and order requirements are also satisfied.'
                  : 'Customers will no longer be able to apply this promotion to new orders.',
            ),
            actions: <Widget>[
              TextButton(
                key: const Key('promotion-confirm-cancel'),
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(activating ? 'Cancel' : 'Keep active'),
              ),
              FilledButton(
                key: const Key('promotion-confirm-submit'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(activating ? 'Activate' : 'Deactivate'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    await ref
        .read(promotionMutationProvider.notifier)
        .setActive(
          discountId: discount.id,
          locationId: location.id,
          originalUpdatedAt: openedUpdatedAt,
          isActive: activating,
        );
    if (!context.mounted) return;
    final PromotionMutationState result = ref.read(promotionMutationProvider);
    if (result.phase == PromotionMutationPhase.success) {
      Navigator.pop(context);
      return;
    }
    if (result.phase == PromotionMutationPhase.conflict) {
      final bool reload =
          await showDialog<bool>(
            context: context,
            builder: (BuildContext dialogContext) => AlertDialog(
              title: const Text('This promotion was changed elsewhere.'),
              content: const Text(
                'Reload before trying again to avoid overwriting the latest change.',
              ),
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
      if (reload && context.mounted) onReloadSnapshot();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message ?? 'The promotion could not be updated.'),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: PelinesSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: PelinesColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: PelinesSpacing.xxs),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}

class _StatusField extends StatelessWidget {
  const _StatusField(this.status);
  final PromotionEffectiveStatus status;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: PelinesSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Status', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        PromotionStatusChip(status),
      ],
    ),
  );
}
