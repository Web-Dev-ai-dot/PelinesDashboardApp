import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';

import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/time/pelines_time.dart';
import 'promotion_delete_flow.dart';

import '../../../app/navigation/admin_navigation.dart';
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
  bool _deleting = false;
  void _close() => context.go('/app/promotions');
  Future<void> _delete(Discount discount, Location location) async {
    if (_deleting || ref.read(promotionMutationProvider).isBusy) return;
    setState(() => _deleting = true);
    try {
      final deleted = await deletePromotionWithConfirmation(
        context: context,
        ref: ref,
        discount: discount,
        location: location,
        originalUpdatedAt: _openedUpdatedAt,
      );
      if (deleted && mounted) _close();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(promotionMutationProvider.notifier).reset(),
    );
  }

  @override
  void didUpdateWidget(covariant PromotionDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.discountId != widget.discountId) _openedUpdatedAt = null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(currentLocationProvider);
    final Location? location = selected.isLoading || selected.hasError
        ? null
        : selected.value;
    final AsyncValue<List<Discount>> source = ref.watch(promotionsProvider);
    return AdminPopScope<void>(
      canPop: false,
      onRequestLeave: () async => !_deleting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_deleting) _close();
      },
      child: Scaffold(
        appBar: AdminAppBar(
          leading: IconButton(
            key: const Key('promotion-details-back'),
            tooltip: tr(context, 'Back'),
            onPressed: _deleting ? null : _close,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            tr(context, 'Promotions'),
            style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
          ),
        ),
        body: source.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stack) => Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      tr(
                        context,
                        error is ApiException
                            ? error.message
                            : 'Promotions could not be loaded.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      style: PelinesControlStyles.button(
                        PelinesButtonVariant.primary,
                      ),
                      onPressed: ref.read(promotionsProvider.notifier).refresh,
                      child: Text(tr(context, 'Try again')),
                    ),
                  ],
                ),
              ),
            ),
          ),
          data: (List<Discount> values) {
            if (selected.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            final Discount? discount = _find(values);
            if (discount == null) {
              return Center(
                child: Text(tr(context, 'This promotion no longer exists.')),
              );
            }
            final bool applies =
                location != null &&
                (discount.locationId == null ||
                    discount.locationId == location.id);
            if (!applies) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    tr(
                      context,
                      'This promotion is not available for the selected location.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            _openedUpdatedAt ??= discount.updatedAt;
            return _Details(
              discount: discount,
              location: location,
              deleting: _deleting,
              onClose: _close,
              onDelete: () => _delete(discount, location),
              openedUpdatedAt: _openedUpdatedAt!,
              onReloadSnapshot: () => setState(() {
                _openedUpdatedAt = discount.updatedAt;
                ref.read(promotionMutationProvider.notifier).reset();
              }),
            );
          },
        ),
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
    required this.deleting,
    required this.onClose,
    required this.onDelete,
  });
  final Discount discount;
  final Location location;
  final DateTime openedUpdatedAt;
  final VoidCallback onReloadSnapshot;
  final bool deleting;
  final VoidCallback onClose;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PromotionMutationState operation = ref.watch(
      promotionMutationProvider,
    );
    final bool global = discount.locationId == null;
    final bool manageable = discount.locationId == location.id;
    final busy = deleting || operation.isBusy;
    final locale = Localizations.localeOf(context).toString();
    String money(int cents) => NumberFormat.currency(
      locale: locale,
      symbol: r'$',
      decimalDigits: 2,
    ).format(cents / 100);
    Widget value(String text) => Text(
      text,
      textAlign: TextAlign.end,
      style: Theme.of(context).textTheme.bodyLarge
          ?.copyWith(fontWeight: FontWeight.w600),
    );
    Widget row(String label, Widget content) =>
        _DetailRow(label: tr(context, label), child: content);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const Key('promotion-details-scroll'),
        padding: const EdgeInsets.all(PelinesSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: PelinesCard(
              key: const Key('promotion-details-card'),
              variant: PelinesCardVariant.raised,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              discount.code,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tr(context, 'Discount code details'),
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: PelinesColors.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('promotion-details-x'),
                        tooltip: tr(context, 'Close'),
                        onPressed: busy ? null : onClose,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Divider(height: 40),
                  row(
                    'Type',
                    value(
                      tr(
                        context,
                        discount.type == 'percent'
                            ? 'Percentage'
                            : 'Fixed amount',
                      ),
                    ),
                  ),
                  row(
                    'Value',
                    value(
                      discount.type == 'percent'
                          ? '${discount.value}%'
                          : money(discount.value),
                    ),
                  ),
                  row(
                    'Applies to',
                    value(tr(context, discount.appliesToLabel)),
                  ),
                  row('Minimum order', value(money(discount.minSubtotalCents))),
                  row(
                    'Start date',
                    value(
                      discount.startsAt == null
                          ? '—'
                          : PelinesTime.dayKey(discount.startsAt!),
                    ),
                  ),
                  row(
                    'End date',
                    value(
                      discount.endsAt == null
                          ? '—'
                          : PelinesTime.dayKey(discount.endsAt!),
                    ),
                  ),
                  row(
                    'Usage limit',
                    value(
                      discount.usageLimit == null
                          ? tr(context, 'Unlimited')
                          : tr(
                              context,
                              '{count} total',
                            ).replaceAll('{count}', '${discount.usageLimit}'),
                    ),
                  ),
                  row(
                    'Times redeemed',
                    value(
                      discount.usageLimit == null
                          ? '${discount.timesRedeemed}'
                          : '${discount.timesRedeemed} / ${discount.usageLimit}',
                    ),
                  ),
                  row(
                    'Location',
                    value(
                      global ? tr(context, 'All locations') : location.name,
                    ),
                  ),
                  row(
                    'Status',
                    PromotionStatusChip(
                      discount.effectiveStatus(DateTime.now()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr(
                      context,
                      'This count may include orders that were created but not completed.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: PelinesColors.textSecondary),
                  ),
                  if (global) ...[
                    const SizedBox(height: 12),
                    Text(
                      tr(context, 'This promotion applies to all locations.'),
                    ),
                  ],
                  const Divider(height: 32),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton(
                        key: const Key('promotion-details-close'),
                        style: PelinesControlStyles.button(
                          PelinesButtonVariant.secondary,
                        ),
                        onPressed: busy ? null : onClose,
                        child: Text(tr(context, 'Close')),
                      ),
                      if (manageable || global) ...[
                        TextButton(
                          key: const Key('promotion-details-delete'),
                          style: TextButton.styleFrom(
                            foregroundColor: PelinesColors.destructive,
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: busy ? null : onDelete,
                          child: Text(tr(context, 'Delete')),
                        ),
                        FilledButton(
                          key: const Key('edit-promotion'),
                          style: PelinesControlStyles.button(
                            PelinesButtonVariant.primary,
                          ),
                          onPressed: busy
                              ? null
                              : () => context.push(
                                  '/app/promotions/${discount.id}/edit',
                                ),
                          child: Text(tr(context, 'Edit')),
                        ),
                      ],
                    ],
                  ),
                  if (manageable) ...[
                    const SizedBox(height: 16),
                    OutlinedButton(
                      key: const Key('promotion-active-action'),
                      style: PelinesControlStyles.button(
                        PelinesButtonVariant.secondary,
                      ),
                      onPressed: busy
                          ? null
                          : () => _confirmAndSave(context, ref),
                      child: Text(
                        tr(
                          context,
                          discount.isActive
                              ? 'Deactivate promotion'
                              : 'Activate promotion',
                        ),
                      ),
                    ),
                  ],
                  if (operation.isBusy) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndSave(BuildContext context, WidgetRef ref) async {
    final bool activating = !discount.isActive;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(
              '${activating ? tr(context, 'Activate') : tr(context, 'Deactivate')} ${discount.code}?',
            ),
            content: Text(
              activating
                  ? tr(
                      context,
                      'The promotion will become eligible again if its dates, usage limit, location and order requirements are also satisfied.',
                    )
                  : tr(
                      context,
                      'Customers will no longer be able to apply this promotion to new orders.',
                    ),
            ),
            actions: <Widget>[
              TextButton(
                key: const Key('promotion-confirm-cancel'),
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  activating
                      ? tr(context, 'Cancel')
                      : tr(context, 'Keep active'),
                ),
              ),
              FilledButton(
                style: PelinesControlStyles.button(
                  PelinesButtonVariant.primary,
                ),
                key: const Key('promotion-confirm-submit'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  activating
                      ? tr(context, 'Activate')
                      : tr(context, 'Deactivate'),
                ),
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
              title: Text(tr(context, 'This promotion was changed elsewhere.')),
              content: Text(
                tr(
                  context,
                  'Reload before trying again to avoid overwriting the latest change.',
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(tr(context, 'Cancel')),
                ),
                FilledButton(
                  style: PelinesControlStyles.button(
                    PelinesButtonVariant.primary,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(tr(context, 'Reload')),
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('promotion-detail-row-$label'),
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: PelinesColors.border)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: PelinesColors.textSecondary),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Align(alignment: AlignmentDirectional.centerEnd, child: child),
        ),
      ],
    ),
  );
}
