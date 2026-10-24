import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_tokens.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import 'analytics_date_range_sheet.dart';
import '../../locations/presentation/pelines_location_context.dart';
import '../../locations/providers/locations_providers.dart';
import '../providers/analytics_providers.dart';

class AnalyticsFilters extends ConsumerWidget {
  const AnalyticsFilters({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsRangeProvider);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final date = DateFormat.yMMMd(locale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnalyticsDateRangeField(
          buttonKey: const Key('analytics-date-range'),
          label: tr(context, 'Date range'),
          dates:
              '${date.format(range.startDate)} – ${date.format(range.endDate)}',
          chevron: true,
          onPressed: () async {
            final picked = await showAnalyticsDateRange(context, range);
            if (picked == null || !context.mounted) return;
            final controller = ref.read(analyticsRangeProvider.notifier);
            if (picked.preset != null) {
              controller.selectPreset(picked.preset!);
            } else {
              controller.selectCustom(picked.startDate, picked.endDate);
            }
          },
        ),
        const SizedBox(height: 4),
        Text(
          tr(context, 'Pacific time'),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: PelinesColors.textSecondary),
        ),
      ],
    );
  }
}

class AnalyticsHeader extends ConsumerWidget {
  const AnalyticsHeader({super.key, required this.onRefresh});
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentLocationProvider);
    final location = current.isLoading || current.hasError
        ? null
        : current.value;
    return Material(
      key: const Key('persistent-section-header'),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(PelinesSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Semantics(
                    header: true,
                    child: Text(
                      tr(context, 'Analytics'),
                      key: const Key('analytics-title'),
                      style: PelinesTypography.pageTitle(
                        Theme.of(context).textTheme,
                        width: MediaQuery.sizeOf(context).width,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AdminHeaderRefresh(
                      key: const Key('analytics-refresh'),
                      onPressed: onRefresh,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (location != null)
              Semantics(
                button: true,
                child: InkWell(
                  key: const Key('location-selector'),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const _LocationPicker(),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: PelinesLocationContext(location: location),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const AnalyticsFilters(key: Key('analytics-filter-bar')),
          ],
        ),
      ),
    );
  }
}

class _LocationPicker extends ConsumerWidget {
  const _LocationPicker();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(locationsProvider);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .6,
        child: locations.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () => ref.read(locationsProvider.notifier).retry(),
              child: Text(tr(context, 'Retry')),
            ),
          ),
          data: (items) => items.isEmpty
              ? Center(child: Text(tr(context, 'No locations are available.')))
              : ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        tr(context, 'Choose a location'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    for (final location in items)
                      ListTile(
                        title: Text(location.name),
                        enabled: location.isActive,
                        selected:
                            ref.watch(currentLocationProvider).value?.id ==
                            location.id,
                        onTap: () async {
                          try {
                            await ref
                                .read(currentLocationProvider.notifier)
                                .select(location);
                            if (context.mounted) Navigator.pop(context);
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    tr(
                                      context,
                                      'Location could not be selected.',
                                    ),
                                  ),
                                ),
                              );
                            }
                          }
                        },
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
