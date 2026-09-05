import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
      appBar: AppBar(title: const Text('Promotions')),
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
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const <Widget>[
            SizedBox(height: 180),
            Icon(Icons.local_offer_outlined, size: 52),
            SizedBox(height: 16),
            Center(child: Text('No promotions available for this location.')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: Text(label, style: Theme.of(context).textTheme.titleMedium),
  );
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
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/app/promotions/${discount.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
              Text(scope, style: Theme.of(context).textTheme.bodySmall),
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
    final Color color = switch (status) {
      PromotionEffectiveStatus.active => Colors.green.shade700,
      PromotionEffectiveStatus.scheduled => Colors.blue.shade700,
      PromotionEffectiveStatus.inactive => Colors.grey.shade700,
      PromotionEffectiveStatus.expired => Colors.orange.shade800,
      PromotionEffectiveStatus.usageLimitReached => Colors.red.shade700,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
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
