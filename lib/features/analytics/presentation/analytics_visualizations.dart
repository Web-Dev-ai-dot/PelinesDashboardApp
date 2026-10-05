import '../../../app/theme/pelines_components.dart';

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../orders/models/order_models.dart';
import '../application/analytics_visualization_data.dart';
import '../data/analytics_repository.dart';
import '../models/analytics_date_range.dart';
import '../models/analytics_result.dart';
import 'analytics_operational_cards.dart';

NumberFormat _money(BuildContext context) => NumberFormat.currency(
  locale: Localizations.localeOf(context).toLanguageTag(),
  name: 'USD',
  symbol: 'US\$',
);

class AnalyticsComparison extends StatelessWidget {
  const AnalyticsComparison({
    required this.metric,
    required this.covered,
    super.key,
  });
  final MetricComparison metric;
  final bool covered;
  @override
  Widget build(BuildContext context) {
    final percent = covered ? metric.percentChange : null;
    final value = percent == null
        ? '—'
        : '${percent > 0 ? '+' : ''}${NumberFormat('0.0', Localizations.localeOf(context).toLanguageTag()).format(percent)}%';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        '$value ${tr(context, 'vs previous period')}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class AnalyticsVisualizations extends StatelessWidget {
  const AnalyticsVisualizations({
    required this.dataset,
    required this.result,
    super.key,
  });
  final AnalyticsDataset dataset;
  final AnalyticsResult result;

  @override
  Widget build(BuildContext context) {
    final period = result.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        AnalyticsSalesChart(dataset: dataset, period: period),
        const SizedBox(height: 16),
        PelinesSectionHeading(tr(context, 'Order Volume')),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns = constraints.maxWidth >= 760 * scale ? 2 : 1;
            final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: width,
                  child: _Breakdown(
                    title: 'Order Type',
                    groups: {
                      'Regular': period.orderTypes[OrderType.online]!,
                      'Catering': period.orderTypes[OrderType.catering]!,
                      if (period.orderTypes[OrderType.unknown]!.orders > 0)
                        'Unknown': period.orderTypes[OrderType.unknown]!,
                    },
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _Breakdown(
                    title: 'Fulfillment',
                    groups: {
                      'Pickup':
                          period.fulfillmentTypes[FulfillmentType.pickup]!,
                      'Delivery':
                          period.fulfillmentTypes[FulfillmentType.delivery]!,
                      if (period
                              .fulfillmentTypes[FulfillmentType.unknown]!
                              .orders >
                          0)
                        'Unknown':
                            period.fulfillmentTypes[FulfillmentType.unknown]!,
                    },
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        PelinesSectionHeading(tr(context, 'Products')),
        const SizedBox(height: 16),
        AnalyticsTopProducts(products: period.products),
        const SizedBox(height: 24),
        PelinesSectionHeading(tr(context, 'Operations')),
        const SizedBox(height: 16),
        AnalyticsOperationalCards(dataset: dataset, range: period.range),
        const SizedBox(height: 16),
        _Section(
          title: 'Order Status',
          child: Padding(
            padding: const EdgeInsets.only(left: PelinesSpacing.xxs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in {
                  'Completed': period.completed,
                  'Cancelled': period.cancelled,
                  'In Progress': period.inProgress,
                  if (period.unknownStatusOrders > 0)
                    'Unknown': period.unknownStatusOrders,
                }.entries)
                  _ValueRow(
                    label: tr(context, entry.key),
                    value: NumberFormat.decimalPattern(
                      Localizations.localeOf(context).toLanguageTag(),
                    ).format(entry.value),
                  ),
                const Divider(),
                _ValueRow(
                  label: tr(context, 'Cancellation Rate'),
                  value: period.cancellationRate == null
                      ? '—'
                      : '${NumberFormat('0.0', Localizations.localeOf(context).toLanguageTag()).format(period.cancellationRate)}%',
                ),
                _CancellationComparison(
                  result: result,
                  covered: analyticsComparisonIsCovered(dataset, result),
                ),
                Text(
                  tr(
                    context,
                    'Cancelled eligible orders / all eligible orders.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AnalyticsSalesChart extends StatelessWidget {
  const AnalyticsSalesChart({
    required this.dataset,
    required this.period,
    super.key,
  });
  final AnalyticsDataset dataset;
  final AnalyticsPeriodResult period;

  @override
  Widget build(BuildContext context) {
    final points = analyticsSalesSeries(dataset, period);
    final hourly = period.range.preset == AnalyticsDatePreset.today;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final money = _money(context);
    final hasKnown = points.any((p) => p.salesCents != null);
    final hasSales = period.salesOrderCount > 0;
    final incomplete = !analyticsRangeIsCovered(dataset, period.range);
    String label(int i, {bool full = false}) {
      final date = points[i].start;
      return hourly
          ? '${DateFormat.Hm(locale).format(date)} ${date.timeZoneName}'
          : (full ? DateFormat.yMMMd(locale) : DateFormat.Md(locale)).format(
              date,
            );
    }

    return _Section(
      title: 'Sales over time',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${hourly ? tr(context, 'Hourly') : tr(context, 'Daily')} · USD · America/Los_Angeles',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (incomplete)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                tr(context, 'Uncertain dates are omitted, not shown as zero.'),
              ),
            ),
          if (!hasKnown || !hasSales)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                tr(
                  context,
                  !hasKnown
                      ? 'No reliable chart data for this period.'
                      : 'No sales in the loaded data for this period.',
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
                final maxLabels = math.max(
                  2,
                  (constraints.maxWidth / (100 * scale)).floor(),
                );
                final interval = math
                    .max(1, (points.length / maxLabels).ceil())
                    .toDouble();
                final peak =
                    points.fold<int>(
                      0,
                      (max, p) => math.max(max, p.salesCents ?? 0),
                    ) /
                    100;
                return Padding(
                  padding: const EdgeInsets.only(top: 20, right: 12),
                  child: SizedBox(
                    height: 250 + 35 * (scale - 1),
                    child: LineChart(
                      key: const Key('analytics-sales-chart'),
                      duration: Duration.zero,
                      LineChartData(
                        minX: 0,
                        maxX: math.max(1, points.length - 1).toDouble(),
                        minY: 0,
                        maxY: peak == 0 ? 1 : peak * 1.15,
                        gridData: FlGridData(
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => const FlLine(
                            color: PelinesColors.border,
                            strokeWidth: 1,
                            dashArray: [4, 4],
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 60 * scale,
                              getTitlesWidget: (value, meta) => Text(
                                NumberFormat.compactSimpleCurrency(
                                  locale: locale,
                                  name: 'USD',
                                ).format(value),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: interval,
                              reservedSize: 42 * scale,
                              minIncluded: false,
                              maxIncluded: false,
                              getTitlesWidget: (value, meta) {
                                final i = value.toInt();
                                if (i < 0 || i >= points.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    hourly
                                        ? DateFormat.Hm(locale)
                                              .format(points[i].start)
                                        : label(i),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            fitInsideHorizontally: true,
                            fitInsideVertically: true,
                            getTooltipItems: (spots) => spots
                                .map(
                                  (spot) => LineTooltipItem(
                                    '${label(spot.x.toInt(), full: true)}\n${money.format(spot.y)}',
                                    const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            color: PelinesColors.brandPrimary,
                            barWidth: 3,
                            belowBarData: BarAreaData(
                              show: true,
                              color: PelinesColors.brandPrimarySoft.withValues(
                                alpha: .45,
                              ),
                            ),
                            isCurved: false,
                            dotData: FlDotData(show: points.length <= 31),
                            spots: [
                              for (var i = 0; i < points.length; i++)
                                points[i].salesCents == null
                                    ? FlSpot.nullSpot
                                    : FlSpot(
                                        i.toDouble(),
                                        points[i].salesCents! / 100,
                                      ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          if (hasKnown && hasSales)
            Text(
              tr(context, 'Tap a point to see its date and Sales.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class AnalyticsTopProducts extends StatelessWidget {
  const AnalyticsTopProducts({required this.products, super.key});
  final List<ProductSales> products;
  @override
  Widget build(BuildContext context) => _Section(
    title: 'Top Products',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(
            context,
            'Product Sales uses item totals before order discounts; excludes tips and fees.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (products.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(tr(context, 'No products in the loaded sales.')),
          ),
        for (final (rank, product) in products.take(5).indexed)
          Padding(
            key: Key('analytics-product-${product.key}'),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PelinesStateBadge(
                  label: '#${rank + 1}',
                  foreground: PelinesColors.brandPrimary,
                  background: PelinesColors.brandPrimarySoft,
                ),
                const SizedBox(height: 8),
                Semantics(
                  label: tr(context, 'Product'),
                  child: Text(
                    product.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Wrap(
                  spacing: 24,
                  runSpacing: 4,
                  children: [
                    Text(
                      '${tr(context, 'Quantity')}: ${NumberFormat.decimalPattern(Localizations.localeOf(context).toLanguageTag()).format(product.quantity)}',
                    ),
                    Text(
                      '${tr(context, 'Product Sales')}: ${_money(context).format(product.lineSalesCents / 100)}',
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.title, required this.groups});
  final String title;
  final Map<String, AnalyticsBreakdown> groups;
  @override
  Widget build(BuildContext context) => _Section(
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in groups.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PelinesStateBadge(
                  label: tr(context, entry.key),
                  foreground: PelinesColors.brandPrimary,
                  background: PelinesColors.brandPrimarySoft,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 24,
                  runSpacing: 4,
                  children: [
                    Text(
                      '${tr(context, 'Orders')}: ${NumberFormat.decimalPattern(Localizations.localeOf(context).toLanguageTag()).format(entry.value.orders)}',
                    ),
                    Text(
                      '${tr(context, 'Sales')}: ${_money(context).format(entry.value.salesCents / 100)}',
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 4),
        Text(
          value,
          style: PelinesTypography.pageTitle(Theme.of(context).textTheme)
              ?.copyWith(fontSize: 24),
        ),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => PelinesCard(
    key: Key('analytics-section-$title'),
    variant: PelinesCardVariant.compact,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PelinesSectionHeading(tr(context, title)),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

class _CancellationComparison extends StatelessWidget {
  const _CancellationComparison({required this.result, required this.covered});
  final AnalyticsResult result;
  final bool covered;
  @override
  Widget build(BuildContext context) {
    final delta = covered ? result.cancellationRatePointChange : null;
    final text = delta == null
        ? '—'
        : '${delta > 0 ? '+' : ''}${NumberFormat('0.0', Localizations.localeOf(context).toLanguageTag()).format(delta)} ${tr(context, 'percentage points')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        '$text ${tr(context, 'vs previous period')}',
        key: const Key('analytics-cancellation-comparison'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
