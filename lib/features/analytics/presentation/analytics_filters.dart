import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../core/time/pelines_time.dart';
import '../../locations/presentation/pelines_location_selector.dart';
import '../../locations/providers/locations_providers.dart';
import '../models/analytics_date_range.dart';
import '../providers/analytics_providers.dart';

class AnalyticsFilters extends ConsumerWidget {
  const AnalyticsFilters({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsRangeProvider);
    final location = ref.watch(currentLocationProvider);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final date = DateFormat.yMMMd(locale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PelinesLocationSelector(
          locationName:
              location.value?.name ?? tr(context, 'Choose a location'),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const _LocationPicker(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in {
              AnalyticsDatePreset.today: 'Today',
              AnalyticsDatePreset.last7Days: '7 Days',
              AnalyticsDatePreset.last30Days: '30 Days',
              AnalyticsDatePreset.last90Days: '90 Days',
            }.entries)
              ChoiceChip(
                key: Key('analytics-${entry.key.name}'),
                label: Text(tr(context, entry.value)),
                selected: _same(range, AnalyticsDateRange.preset(entry.key)),
                onSelected: (_) => ref
                    .read(analyticsRangeProvider.notifier)
                    .selectPreset(entry.key),
              ),
            ActionChip(
              key: const Key('analytics-custom'),
              avatar: const Icon(Icons.date_range, size: 18),
              label: Text(tr(context, 'Custom')),
              onPressed: () async {
                final now = PelinesTime.now();
                final first = range.startDate.isBefore(DateTime.utc(2000))
                    ? range.startDate
                    : DateTime(2000);
                final last = DateTime(now.year, now.month, now.day);
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: first,
                  lastDate: range.endDate.isAfter(last) ? range.endDate : last,
                  initialDateRange: DateTimeRange(
                    start: range.startDate,
                    end: range.endDate,
                  ),
                );
                if (picked != null && context.mounted) {
                  ref
                      .read(analyticsRangeProvider.notifier)
                      .selectCustom(picked.start, picked.end);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${date.format(range.startDate)} – ${date.format(range.endDate)} · Pacific',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  bool _same(AnalyticsDateRange a, AnalyticsDateRange b) =>
      a.startDate == b.startDate && a.endDate == b.endDate;
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
