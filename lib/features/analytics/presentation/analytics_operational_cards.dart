import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../core/time/pelines_time.dart';
import '../application/analytics_operational_kpis.dart';
import '../application/analytics_visualization_data.dart';
import '../data/analytics_repository.dart';
import '../models/analytics_date_range.dart';

class AnalyticsOperationalCards extends StatelessWidget {
  const AnalyticsOperationalCards({
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
      PelinesKpiCard(
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
      PelinesKpiCard(
        key: const Key('analytics-busiest-day'),
        label: tr(context, 'Busiest Day'),
        value: ranking(
          values.weekdays,
          (day) => DateFormat.EEEE(locale).format(DateTime(2026, 1, 5 + day)),
        ),
        description: description(values.weekdays),
        icon: Icons.calendar_today,
      ),
      PelinesKpiCard(
        key: const Key('analytics-waiting'),
        label: tr(context, 'Waiting for Approval'),
        value: number.format(values.waiting),
        description: tr(
          context,
          'Current status of orders received in the selected period.',
        ),
        icon: Icons.pending_actions,
      ),
      PelinesKpiCard(
        key: const Key('analytics-ready'),
        label: AdminLocalizations.of(context)
            .text('Ready', key: 'analytics.Ready'),
        value: number.format(values.ready),
        description: tr(
          context,
          'Current status of orders received in the selected period.',
        ),
        icon: Icons.check_circle_outline,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PelinesSectionHeading(tr(context, 'Operational KPIs')),
        const SizedBox(height: 8),
        Text(tr(context, 'Eligible orders received in the selected period.')),
        if (range.contains(PelinesTime.now()))
          Text(tr(context, 'This period is still in progress.')),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns = constraints.maxWidth >= 1080 * scale
                ? 4
                : constraints.maxWidth >= 520 * scale
                ? 2
                : 1;
            final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final card in cards) SizedBox(width: width, child: card),
              ],
            );
          },
        ),
      ],
    );
  }
}
