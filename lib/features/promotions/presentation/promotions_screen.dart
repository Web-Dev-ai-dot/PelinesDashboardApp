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
import '../../locations/presentation/pelines_location_context.dart';
import '../models/discount.dart';
import '../providers/promotions_providers.dart';

class PromotionsScreen extends ConsumerWidget {
  const PromotionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Location?> location = ref.watch(currentLocationProvider);
    final AsyncValue<List<Discount>> promotions = ref.watch(promotionsProvider);
    return Scaffold(
      appBar: AdminAppBar(
        title: Text(
          tr(context, 'Promotions'),
          style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
        ),
      ),
      body: location.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => _ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(currentLocationProvider),
        ),
        data: (Location? selected) {
          if (selected == null) {
            return Center(
              child: Text(tr(context, 'Choose a location to continue.')),
            );
          }
          return Column(
            children: [
              PelinesPageBody(
                width: PelinesPageWidth.dashboard,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionLocationContext(),
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          PelinesButton(
                            key: const Key('add-promotion'),
                            label: tr(context, 'Add Promotion'),
                            onPressed: () =>
                                context.push('/app/promotions/new'),
                          ),
                          IconButton(
                            tooltip: tr(context, 'Refresh'),
                            onPressed: ref
                                .read(promotionsProvider.notifier)
                                .refresh,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: promotions.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (Object error, StackTrace stack) => _ErrorView(
                    message: _errorMessage(error),
                    onRetry: ref.read(promotionsProvider.notifier).refresh,
                  ),
                  data: (List<Discount> all) => _PromotionList(
                    location: selected,
                    discounts: all,
                    onRefresh: ref.read(promotionsProvider.notifier).refresh,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PromotionList extends StatelessWidget {
  const _PromotionList({
    required this.location,
    required this.discounts,
    required this.onRefresh,
  });
  final Location location;
  final List<Discount> discounts;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final List<Discount> local = discounts
        .where((Discount item) => item.locationId == location.id)
        .toList(growable: false);
    final List<Discount> global = discounts
        .where((Discount item) => item.locationId == null)
        .toList(growable: false);
    if (local.isEmpty && global.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.all(PelinesSpacing.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.local_offer_outlined, size: 52),
                    SizedBox(height: PelinesSpacing.md),
                    Text(
                      tr(context, 'No promotions available for this location.'),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: PelinesPageBody(
        width: PelinesPageWidth.dashboard,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            PelinesSpacing.md,
            PelinesSpacing.sm,
            PelinesSpacing.md,
            PelinesSpacing.xxl,
          ),
          children: <Widget>[
            if (local.isNotEmpty) ...<Widget>[
              _SectionTitle(tr(context, 'This location')),
              _PromotionTable(
                discounts: local,
                scope: tr(context, 'This location'),
              ),
            ],
            if (global.isNotEmpty) ...<Widget>[
              if (local.isNotEmpty) const SizedBox(height: 18),
              _SectionTitle(tr(context, 'All locations')),
              _PromotionTable(
                discounts: global,
                scope: tr(context, 'All locations'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => PelinesSectionHeading(label);
}

String promotionValue(BuildContext context, Discount discount) =>
    discount.discountLabel.replaceFirst('off', tr(context, 'off'));
String promotionUsage(BuildContext context, Discount discount) => discount
    .usageLabel
    .replaceFirst('claimed', tr(context, 'claimed'))
    .replaceFirst('Unlimited', tr(context, 'Unlimited'));

class _PromotionTable extends StatelessWidget {
  const _PromotionTable({required this.discounts, required this.scope});
  final List<Discount> discounts;
  final String scope;
  @override
  Widget build(BuildContext context) => PelinesAdaptiveTable<Discount>(
    key: ValueKey('promotions-${discounts.first.locationId ?? 'global'}'),
    rows: discounts,
    empty: const SizedBox.shrink(),
    columns: [
      PelinesTableColumn(
        label: tr(context, 'Code'),
        cell: (d) => _code(context, d),
      ),
      PelinesTableColumn(
        label: tr(context, 'Discount Type'),
        cell: (d) => Text(
          tr(context, d.type == 'percent' ? 'Percentage' : 'Fixed amount'),
        ),
      ),
      PelinesTableColumn(
        label: tr(context, 'Discount'),
        cell: (d) => Text(promotionValue(context, d)),
      ),
      PelinesTableColumn(
        label: tr(context, 'Applies to'),
        cell: (d) => Text(tr(context, d.appliesToLabel)),
      ),
      PelinesTableColumn(label: tr(context, 'Scope'), cell: (_) => Text(scope)),
      PelinesTableColumn(
        label: tr(context, 'Usage claimed'),
        cell: (d) => Text(promotionUsage(context, d)),
      ),
      PelinesTableColumn(
        label: tr(context, 'Status'),
        cell: (d) => _StatusChip(d.effectiveStatus(DateTime.now())),
      ),
      PelinesTableColumn(
        label: tr(context, 'View'),
        cell: (d) => _view(context, d),
      ),
    ],
    cardBuilder: (context, d) => PelinesCard(
      key: ValueKey('promotion-card-${d.id}'),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => context.push('/app/promotions/${d.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _code(context, d),
                  _StatusChip(d.effectiveStatus(DateTime.now())),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                promotionValue(context, d),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(tr(context, d.appliesToLabel)),
              const SizedBox(height: 12),
              PelinesStateBadge(
                label: scope,
                foreground: d.locationId == null
                    ? PelinesColors.textSecondary
                    : PelinesColors.brandPrimary,
                background: d.locationId == null
                    ? PelinesColors.mutedSurface
                    : PelinesColors.brandPrimarySoft,
                icon: d.locationId == null
                    ? Icons.lock_outline
                    : Icons.storefront_outlined,
              ),
              const Divider(height: 28),
              PelinesLabelValueRow(
                label: Text(
                  '${tr(context, 'Usage claimed')}: ${promotionUsage(context, d)}',
                ),
                value: _view(context, d),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _code(BuildContext context, Discount d) => Text(
    d.code,
    style: PelinesTypography.sectionTitle(Theme.of(context).textTheme)
        ?.copyWith(fontSize: 22),
  );
  Widget _view(BuildContext context, Discount d) => PelinesViewAction(
    label: tr(context, 'View'),
    onPressed: () => context.push('/app/promotions/${d.id}'),
  );
}

class PromotionStatusChip extends StatelessWidget {
  const PromotionStatusChip(this.status, {super.key});
  final PromotionEffectiveStatus status;

  @override
  Widget build(BuildContext context) => _StatusChip(status);
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final PromotionEffectiveStatus status;

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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            style: PelinesControlStyles.button(PelinesButtonVariant.primary),
            onPressed: onRetry,
            child: Text(tr(context, 'Try again')),
          ),
        ],
      ),
    ),
  );
}

String _errorMessage(Object error) {
  final String value = error.toString();
  final int separator = value.indexOf(': ');
  return separator < 0 ? value : value.substring(separator + 2);
}
