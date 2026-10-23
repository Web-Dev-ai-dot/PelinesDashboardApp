import '../../../app/theme/app_theme.dart';

import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../models/discount.dart';
import '../providers/promotions_providers.dart';

class PromotionsScreen extends ConsumerStatefulWidget {
  const PromotionsScreen({super.key});
  @override
  ConsumerState<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends ConsumerState<PromotionsScreen> {
  bool _confirming = false;
  Future<void> _delete(Discount discount, Location location) async {
    if (_confirming ||
        ref.read(promotionMutationProvider).isBusy ||
        (discount.locationId != null && discount.locationId != location.id)) {
      return;
    }
    setState(() => _confirming = true);
    try {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(
                tr(
                  context,
                  discount.locationId == null
                      ? 'Delete global promotion'
                      : 'Delete discount code?',
                ),
              ),
              content: Text(
                '${discount.code}\n\n${tr(context, discount.locationId == null ? 'This promotion will no longer be available for future use at all locations. This action cannot be undone.' : 'Customers will no longer be able to use this discount code.')}',
              ),
              actions: [
                TextButton(
                  key: const Key('promotion-delete-cancel'),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(tr(context, 'Cancel')),
                ),
                FilledButton(
                  key: const Key('promotion-delete-confirm'),
                  style: PelinesControlStyles.button(
                    PelinesButtonVariant.primary,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(tr(context, 'Delete')),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;
      await ref
          .read(promotionMutationProvider.notifier)
          .delete(
            discountId: discount.id,
            locationId: location.id,
            originalUpdatedAt: discount.updatedAt,
            global: discount.locationId == null,
          );
      if (!mounted) return;
      final result = ref.read(promotionMutationProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              result.message ??
                  (result.phase == PromotionMutationPhase.success
                      ? 'Promotion deleted.'
                      : 'The promotion could not be deleted.'),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(currentLocationProvider);
    final promotions = ref.watch(promotionsProvider);
    final busy = _confirming || ref.watch(promotionMutationProvider).isBusy;
    return AdminSectionScaffold(
      appBar: AdminAppBar(
        title: Text(
          tr(context, 'Promotions'),
          style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
        ),
        actions: [
          if (!location.isLoading &&
              !location.hasError &&
              location.value != null)
            AdminHeaderRefresh(
              onPressed: busy
                  ? null
                  : ref.read(promotionsProvider.notifier).refresh,
            ),
        ],
      ),
      body: location.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: SingleChildScrollView(
            child: _ErrorView(
              message: error.toString(),
              onRetry: () => ref.invalidate(currentLocationProvider),
            ),
          ),
        ),
        data: (selected) {
          if (selected == null) {
            return Center(
              child: Text(tr(context, 'Choose a location to continue.')),
            );
          }
          final values = promotions.value ?? const <Discount>[];
          final local = values
              .where((d) => d.locationId == selected.id)
              .toList();
          final global = values.where((d) => d.locationId == null).toList();
          return PelinesPageBody(
            child: SafeArea(
              top: false,
              child: RefreshIndicator(
                onRefresh: busy
                    ? () async {}
                    : ref.read(promotionsProvider.notifier).refresh,
                child: ListView(
                  key: const Key('promotions-list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(PelinesSpacing.lg),
                  children: [
                    Text(
                      tr(
                        context,
                        'Create and manage discount codes and promotional pricing.',
                      ),
                    ),
                    const SizedBox(height: 28),
                    _PromotionActions(enabled: !busy),
                    const SizedBox(height: 8),
                    Text(
                      tr(context, 'Generate code is not available yet (T05).'),
                      style: const TextStyle(
                        color: PelinesColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        PelinesSectionHeading(tr(context, 'Discount Codes')),
                        if (!promotions.isLoading && !promotions.hasError)
                          PelinesStateBadge(
                            key: const Key('promotions-count'),
                            label: tr(context, '{count} total').replaceAll(
                              '{count}',
                              '${local.length + global.length}',
                            ),
                            foreground: PelinesColors.textPrimary,
                            background: PelinesColors.mutedSurface,
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    promotions.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, _) => _ErrorView(
                        message: _errorMessage(error),
                        onRetry: ref.read(promotionsProvider.notifier).refresh,
                      ),
                      data: (_) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (local.isEmpty && global.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.local_offer_outlined,
                                    size: 52,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    tr(
                                      context,
                                      'No promotions available for this location.',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          for (final group in [local, global])
                            if (group.isNotEmpty) ...[
                              PelinesSectionHeading(
                                tr(
                                  context,
                                  group.first.locationId == null
                                      ? 'All locations'
                                      : 'This location',
                                ),
                              ),
                              const SizedBox(height: 12),
                              for (final discount in group)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 24),
                                  child: _PromotionCard(
                                    discount: discount,
                                    enabled: !busy,
                                    onDelete: () => _delete(discount, selected),
                                  ),
                                ),
                            ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PromotionActions extends StatelessWidget {
  const _PromotionActions({required this.enabled});
  final bool enabled;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final stacked = constraints.maxWidth < 640 * scale;
      final width = stacked
          ? constraints.maxWidth
          : (constraints.maxWidth - 16) / 2;
      return Wrap(
        spacing: 16,
        runSpacing: 12,
        children: [
          SizedBox(
            width: width,
            child: Tooltip(
              message: tr(context, 'Generate code is not available yet (T05).'),
              child: OutlinedButton.icon(
                key: const Key('generate-promotion-code'),
                style:
                    PelinesControlStyles.button(PelinesButtonVariant.secondary)
                        .copyWith(
                          side: const WidgetStatePropertyAll(
                            BorderSide(color: PelinesColors.brandPrimary),
                          ),
                        ),
                onPressed: null,
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: Text(
                  tr(context, 'Generate code'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          SizedBox(
            width: width,
            child: FilledButton.icon(
              key: const Key('add-promotion'),
              style: PelinesControlStyles.button(PelinesButtonVariant.primary),
              onPressed: enabled
                  ? () => context.push('/app/promotions/new')
                  : null,
              icon: const Icon(Icons.add),
              label: Text(
                tr(context, 'Create discount code'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    },
  );
}

String promotionValue(BuildContext context, Discount discount) =>
    discount.discountLabel.replaceFirst('off', tr(context, 'off'));
String promotionUsage(BuildContext context, Discount discount) => discount
    .usageLabel
    .replaceFirst('claimed', tr(context, 'claimed'))
    .replaceFirst('Unlimited', tr(context, 'Unlimited'));

class _PromotionCard extends StatelessWidget {
  const _PromotionCard({
    required this.discount,
    required this.enabled,
    required this.onDelete,
  });
  final Discount discount;
  final bool enabled;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    final d = discount;
    final global = d.locationId == null;
    Widget code() => Text(
      d.code,
      style: PelinesTypography.sectionTitle(Theme.of(context).textTheme)
          ?.copyWith(fontSize: 22),
    );
    Widget status() =>
        _StatusChip(d.effectiveStatus(DateTime.now()), dot: true);
    return PelinesCard(
      key: ValueKey('promotion-card-${d.id}'),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: enabled
                  ? () => context.push('/app/promotions/${d.id}')
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, c) =>
                        c.maxWidth >=
                            260 * MediaQuery.textScalerOf(context).scale(1)
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: code()),
                              const SizedBox(width: 12),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: c.maxWidth * .55,
                                ),
                                child: status(),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              code(),
                              const SizedBox(height: 8),
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: status(),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 24),
                  _PromotionFields(discount: d),
                  const SizedBox(height: 16),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: PelinesStateBadge(
                      label: tr(
                        context,
                        global ? 'All locations' : 'This location',
                      ),
                      foreground: global
                          ? PelinesColors.textSecondary
                          : PelinesColors.brandPrimary,
                      background: global
                          ? PelinesColors.mutedSurface
                          : PelinesColors.brandPrimarySoft,
                      icon: global ? Icons.public : Icons.storefront_outlined,
                    ),
                  ),
                  if (global) ...[
                    const SizedBox(height: 12),
                    Text(
                      tr(context, 'This promotion applies to all locations.'),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: PelinesColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 32),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 8,
              children: [
                PelinesViewAction(
                  key: Key('promotion-view-${d.id}'),
                  label: tr(context, 'View'),
                  onPressed: enabled
                      ? () => context.push('/app/promotions/${d.id}')
                      : null,
                ),
                _PromotionAction(
                  key: Key('promotion-edit-${d.id}'),
                  icon: Icons.edit_outlined,
                  label: global
                      ? '${tr(context, 'Edit')} · ${tr(context, 'All locations')}'
                      : tr(context, 'Edit'),
                  onPressed: enabled
                      ? () => context.push('/app/promotions/${d.id}/edit')
                      : null,
                ),
                _PromotionAction(
                  key: Key('promotion-delete-${d.id}'),
                  icon: Icons.delete_outline,
                  label: global
                      ? '${tr(context, 'Delete')} · ${tr(context, 'All locations')}'
                      : tr(context, 'Delete'),
                  onPressed: enabled ? onDelete : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PromotionFields extends StatelessWidget {
  const _PromotionFields({required this.discount});
  final Discount discount;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final fields = [
        _PromotionField(
          'Type',
          tr(
            context,
            discount.type == 'percent' ? 'Percentage' : 'Fixed amount',
          ),
        ),
        _PromotionField('Applies to', tr(context, discount.appliesToLabel)),
        _PromotionField(
          'Value',
          discount.discountLabel.replaceFirst(RegExp(r' off$'), ''),
          emphasis: true,
        ),
        _PromotionField(
          'Redemptions',
          discount.usageLimit == null
              ? '${discount.timesRedeemed} · ${tr(context, 'Unlimited')}'
              : '${discount.timesRedeemed} / ${discount.usageLimit}',
        ),
      ];
      final columns =
          c.maxWidth >= 280 * MediaQuery.textScalerOf(context).scale(1) ? 2 : 1;
      return Column(
        children: [
          for (var i = 0; i < fields.length; i += columns)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = 0; j < columns; j++) ...[
                    if (j > 0) const SizedBox(width: 20),
                    Expanded(child: fields[i + j]),
                  ],
                ],
              ),
            ),
        ],
      );
    },
  );
}

class _PromotionField extends StatelessWidget {
  const _PromotionField(this.label, this.value, {this.emphasis = false});
  final String label, value;
  final bool emphasis;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        tr(context, label).toUpperCase(),
        style: PelinesTypography.smallLabel,
      ),
      const SizedBox(height: 6),
      Text(
        value,
        style: emphasis
            ? Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)
            : Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _PromotionAction extends StatelessWidget {
  const _PromotionAction({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton.outlined(
    tooltip: label,
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    style: IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: const CircleBorder(),
      side: const BorderSide(color: PelinesColors.border),
      foregroundColor: PelinesColors.textPrimary,
      backgroundColor: PelinesColors.card,
    ),
  );
}

class PromotionStatusChip extends StatelessWidget {
  const PromotionStatusChip(this.status, {super.key});
  final PromotionEffectiveStatus status;

  @override
  Widget build(BuildContext context) => _StatusChip(status);
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status, {this.dot = false});
  final PromotionEffectiveStatus status;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final (Color foreground, Color background) = switch (status) {
      PromotionEffectiveStatus.active => (
        PelinesColors.successForeground,
        PelinesColors.successBackground,
      ),
      PromotionEffectiveStatus.scheduled => (
        PelinesColors.blue,
        PelinesColors.blueSoft,
      ),
      PromotionEffectiveStatus.inactive => (
        PelinesColors.textSecondary,
        PelinesColors.mutedSurface,
      ),
      PromotionEffectiveStatus.expired => (
        PelinesColors.destructive,
        PelinesColors.brandPrimarySoft,
      ),
      PromotionEffectiveStatus.usageLimitReached => (
        PelinesColors.destructive,
        PelinesColors.brandPrimarySoft,
      ),
    };
    return PelinesStateBadge(
      label: AdminLocalizations.of(context)
          .text(status.label, key: 'promotion.${status.label}'),
      dot: dot,
      foreground: foreground,
      background: background,
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 48),
        const SizedBox(height: 12),
        Text(tr(context, message), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(
          style: PelinesControlStyles.button(PelinesButtonVariant.primary),
          onPressed: onRetry,
          child: Text(tr(context, 'Try again')),
        ),
      ],
    ),
  );
}

String _errorMessage(Object error) {
  final value = error.toString();
  final separator = value.indexOf(': ');
  return separator < 0 ? value : value.substring(separator + 2);
}
