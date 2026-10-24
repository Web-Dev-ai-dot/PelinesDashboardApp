import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_components.dart';
import '../models/analytics_result.dart';
import 'analytics_metric_cards.dart';
import '../../../core/time/pelines_time.dart';
import '../application/analytics_operational_kpis.dart';
import '../application/analytics_visualization_data.dart';
import '../data/analytics_repository.dart';
import '../models/analytics_date_range.dart';

class AnalyticsDemandCards extends StatelessWidget {
  const AnalyticsDemandCards({
    required this.dataset,
    required this.range,
    super.key,
  });
  final AnalyticsDataset dataset;
  final AnalyticsDateRange range;

  @override
  Widget build(BuildContext context) {
    final values = AnalyticsOperationalKpis(dataset, range);
    final covered = analyticsRangeIsCovered(dataset, range);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final number = NumberFormat.decimalPattern(locale);
    String ranking(List<int> counts, String Function(int) label) =>
        !covered || AnalyticsOperationalKpis.maximum(counts) == 0
        ? '—'
        : AnalyticsOperationalKpis.leaders(counts).map(label).join('\n');
    String description(List<int> counts) => !covered
        ? tr(context, 'Data may be incomplete')
        : '${AdminLocalizations.of(context).text('Orders', key: 'analytics.Orders')}: ${number.format(AnalyticsOperationalKpis.maximum(counts))}'
              '${AnalyticsOperationalKpis.leaders(counts).length > 1 ? ' · ${tr(context, 'Tied — orders per group')}' : ''}';
    final cards = [
      AnalyticsMetricCard(
        key: const Key('analytics-peak-hour'),
        label: tr(context, 'Peak Order Hour'),
        value: ranking(values.hours, (hour) {
          final start = DateTime(2026, 1, 1, hour);
          return '${DateFormat.j(locale).format(start)}–${DateFormat.j(locale).format(start.add(const Duration(hours: 1)))}';
        }),
        description:
            '${tr(context, 'Orders received · Pacific time')}\n${description(values.hours)}',
        icon: Icons.schedule,
      ),
      AnalyticsMetricCard(
        key: const Key('analytics-busiest-day'),
        label: tr(context, 'Busiest Day'),
        value: ranking(
          values.weekdays,
          (day) => DateFormat.EEEE(locale).format(DateTime(2026, 1, 5 + day)),
        ),
        description: description(values.weekdays),
        icon: Icons.calendar_today,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (range.contains(PelinesTime.now()))
          Text(tr(context, 'This period is still in progress.')),
        const SizedBox(height: 16),
        AnalyticsMetricGrid(children: cards),
      ],
    );
  }
}

class AnalyticsOperationalCards extends StatelessWidget {
  const AnalyticsOperationalCards({
    super.key,
    required this.dataset,
    required this.period,
  });
  final AnalyticsDataset dataset;
  final AnalyticsPeriodResult period;
  @override
  Widget build(BuildContext context) {
    final values = AnalyticsOperationalKpis(dataset, period.range);
    final number = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final percent = NumberFormat(
      '0.0',
      Localizations.localeOf(context).toLanguageTag(),
    );
    final unavailable = tr(
      context,
      'Unavailable: reliable source data is not provided.',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PelinesSectionHeading(tr(context, 'Operational KPIs')),
        const SizedBox(height: 8),
        Text(tr(context, 'Pickup performance for the selected location.')),
        Text(
          tr(
            context,
            'Available counts use eligible orders received in the selected period.',
          ),
        ),
        const SizedBox(height: 16),
        AnalyticsMetricGrid(
          children: [
            AnalyticsMetricCard(
              key: const Key('analytics-on-time'),
              label: tr(context, 'Ready on Time'),
              value: '—',
              description: unavailable,
              icon: Icons.schedule,
            ),
            AnalyticsMetricCard(
              key: const Key('analytics-operational-cancellation'),
              label: tr(context, 'Cancellation Rate'),
              value: period.cancellationRate == null
                  ? '—'
                  : '${percent.format(period.cancellationRate)}%',
              description: tr(
                context,
                'Cancelled eligible orders / all eligible orders.',
              ),
              icon: Icons.cancel_outlined,
            ),
            AnalyticsMetricCard(
              key: const Key('analytics-approval-rate'),
              label: tr(context, 'Approval Rate'),
              value: '—',
              description: unavailable,
              icon: Icons.percent,
            ),
            AnalyticsMetricCard(
              key: const Key('analytics-approval-time'),
              label: tr(context, 'Avg. Approval Time'),
              value: '—',
              description: unavailable,
              icon: Icons.timer_outlined,
            ),
            AnalyticsMetricCard(
              key: const Key('analytics-waiting'),
              label: tr(context, 'Waiting for Approval'),
              value: number.format(values.waiting),
              description: tr(
                context,
                'Current status of orders received in the selected period.',
              ),
              icon: Icons.pending_actions,
            ),
            AnalyticsMetricCard(
              key: const Key('analytics-ready'),
              label: tr(context, 'Marked Ready'),
              value: number.format(values.ready),
              description: tr(
                context,
                'Current status of orders received in the selected period.',
              ),
              icon: Icons.check_circle_outline,
            ),
            AnalyticsMetricCard(
              key: const Key('analytics-accuracy'),
              label: tr(context, 'Order Accuracy'),
              value: '—',
              description: unavailable,
              icon: Icons.analytics_outlined,
            ),
          ],
        ),
      ],
    );
  }
}
