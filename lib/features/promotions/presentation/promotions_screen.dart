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

class PromotionsScreen extends ConsumerWidget {
  const PromotionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Location?> location = ref.watch(currentLocationProvider);
    final AsyncValue<List<Discount>> promotions = ref.watch(promotionsProvider);
    return Scaffold(
      appBar: AdminAppBar(title: const Text('Promotions')),
      floatingActionButton: location.value == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('add-promotion'),
              onPressed: () => context.push('/app/promotions/new'),
              icon: const Icon(Icons.add),
              label: const Text('Add Promotion'),
            ),
      body: location.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => _ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(currentLocationProvider),
        ),
        data: (Location? selected) {
          if (selected == null) {
            return const Center(child: Text('Choose a location to continue.'));
          }
          return promotions.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object error, StackTrace stack) => _ErrorView(
              message: _errorMessage(error),
              onRetry: ref.read(promotionsProvider.notifier).refresh,
            ),
            data: (List<Discount> all) => _PromotionList(
              location: selected,
              discounts: all,
              onRefresh: ref.read(promotionsProvider.notifier).refresh,
            ),
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
          slivers: const [
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
                      'No promotions available for this location.',
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
            const _SectionTitle('This location'),
            for (final Discount discount in local)
              _PromotionCard(discount: discount, scope: 'This location'),
          ],
          if (global.isNotEmpty) ...<Widget>[
            if (local.isNotEmpty) const SizedBox(height: 18),
            const _SectionTitle('All locations'),
            for (final Discount discount in global)
              _PromotionCard(discount: discount, scope: 'All locations'),
          ],
        ],
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

class _PromotionCard extends StatelessWidget {
  const _PromotionCard({required this.discount, required this.scope});
  final Discount discount;
  final String scope;

  @override
  Widget build(BuildContext context) {
    final PromotionEffectiveStatus status = discount.effectiveStatus(
      DateTime.now(),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: PelinesSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(PelinesRadius.prominentCard),
        onTap: () => context.push('/app/promotions/${discount.id}'),
        child: Padding(
          padding: const EdgeInsets.all(PelinesSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      discount.code,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  _StatusChip(status),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                discount.discountLabel,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(discount.appliesToLabel),
              const SizedBox(height: PelinesSpacing.xs),
              PelinesStateBadge(
                label: scope,
                foreground: scope == 'All locations'
                    ? PelinesColors.textSecondary
                    : PelinesColors.brandPrimary,
                background: scope == 'All locations'
                    ? PelinesColors.mutedSurface
                    : PelinesColors.brandPrimarySoft,
                icon: scope == 'All locations'
                    ? Icons.lock_outline
                    : Icons.edit_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }
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
        PelinesColors.textPrimary,
        PelinesColors.brandYellowSoft,
      ),
      PromotionEffectiveStatus.usageLimitReached => (
        PelinesColors.destructive,
        PelinesColors.brandPrimarySoft,
      ),
    };
    return PelinesStateBadge(
      label: status.label,
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
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
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
