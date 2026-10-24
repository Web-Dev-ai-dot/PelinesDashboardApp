import '../../../app/theme/pelines_components.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../../auth/providers/auth_providers.dart';
import '../../locations/providers/locations_providers.dart';
import '../providers/analytics_providers.dart';
import '../application/analytics_visualization_data.dart';
import 'analytics_filters.dart';
import 'analytics_revenue_overview.dart';
import 'analytics_export_action.dart';
import 'analytics_visualizations.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataset = ref.watch(analyticsDatasetProvider);
    final result = ref.watch(analyticsResultProvider);
    final range = ref.watch(analyticsRangeProvider);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final integer = NumberFormat.decimalPattern(locale);
    Future<void> refresh() => ref.read(analyticsRefreshProvider)();
    Future<void> retry() async {
      if (ref.read(authControllerProvider).hasError) {
        await ref.read(authControllerProvider.notifier).retrySession();
      } else if (ref.read(currentLocationProvider).hasError) {
        ref.invalidate(locationsProvider);
        ref.invalidate(currentLocationProvider);
      } else {
        await refresh();
      }
    }

    final period = result.value?.current;
    final loaded = dataset.value;
    final analytics = result.value;
    final comparisonCovered =
        loaded != null &&
        analytics != null &&
        analyticsComparisonIsCovered(loaded.dataset, analytics);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AnalyticsHeader(
              onRefresh:
                  dataset.isLoading || loaded == null || loaded.isRefreshing
                  ? null
                  : refresh,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: refresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(PelinesSpacing.md),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: PelinesLayout.dashboardMaxWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (range.contains(PelinesTime.now()))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                tr(
                                  context,
                                  'This period is still in progress.',
                                ),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          const AnalyticsExportAction(),
                          const SizedBox(height: 12),
                          if (dataset.isLoading) ...[
                            const Center(child: CircularProgressIndicator()),
                            Text(
                              tr(context, 'Loading analytics...'),
                              textAlign: TextAlign.center,
                            ),
                          ] else if (dataset.hasError || result.hasError) ...[
                            Text(
                              tr(context, 'Analytics could not be loaded.'),
                              textAlign: TextAlign.center,
                            ),
                            Center(
                              child: TextButton(
                                onPressed: retry,
                                child: Text(tr(context, 'Retry')),
                              ),
                            ),
                          ] else if (loaded == null) ...[
                            Text(
                              tr(context, 'Choose a location to continue.'),
                              textAlign: TextAlign.center,
                            ),
                          ] else if (period != null) ...[
                            if (loaded.isRefreshing)
                              const LinearProgressIndicator(),
                            if (loaded.refreshError != null)
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: PelinesColors.brandPrimarySoft,
                                  border: Border.all(
                                    color: PelinesColors.brandPrimary,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    PelinesRadius.control,
                                  ),
                                ),
                                child: Text(
                                  tr(
                                    context,
                                    'Refresh failed. Showing previously loaded data.',
                                  ),
                                  key: const Key('analytics-refresh-error'),
                                ),
                              ),
                            if (loaded.dataset.possiblyTruncated)
                              Container(
                                key: const Key('analytics-truncation'),
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: PelinesColors.brandYellowSoft,
                                  borderRadius: BorderRadius.circular(
                                    PelinesRadius.control,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(tr(context, 'Data may be incomplete')),
                                    Text(
                                      '${tr(context, 'Loaded orders')}: ${integer.format(loaded.dataset.loadedCount)}',
                                    ),
                                    if (loaded.dataset.oldestLoadedCreatedAt !=
                                        null)
                                      Text(
                                        '${tr(context, 'Oldest loaded order')}: ${DateFormat.yMMMd(locale).format(PelinesTime.inPacific(loaded.dataset.oldestLoadedCreatedAt!))}',
                                      ),
                                  ],
                                ),
                              ),
                            PelinesSectionHeading(
                              tr(context, 'Sales Overview'),
                            ),
                            const SizedBox(height: 16),
                            AnalyticsRevenueOverview(
                              result: analytics!,
                              comparisonCovered: comparisonCovered,
                            ),
                            if (!comparisonCovered)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  tr(
                                    context,
                                    'Comparison unavailable: the loaded history may be incomplete.',
                                  ),
                                  key: const Key(
                                    'analytics-comparison-unavailable',
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                '${tr(context, 'Previous period')}: ${DateFormat.yMMMd(locale).format(range.previous.startDate)} – ${DateFormat.yMMMd(locale).format(range.previous.endDate)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            if (period.orders == 0)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                ),
                                child: Text(
                                  tr(
                                    context,
                                    'No eligible orders in this period.',
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            AnalyticsVisualizations(
                              dataset: loaded.dataset,
                              result: analytics,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
