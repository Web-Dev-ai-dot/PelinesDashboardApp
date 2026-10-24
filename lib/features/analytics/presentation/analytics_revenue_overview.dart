import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../orders/models/order_models.dart';
import '../models/analytics_result.dart';

class AnalyticsRevenueOverview extends StatelessWidget {
  const AnalyticsRevenueOverview({
    super.key,
    required this.result,
    required this.comparisonCovered,
  });
  final AnalyticsResult result;
  final bool comparisonCovered;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final money = NumberFormat.currency(
      locale: locale,
      name: 'USD',
      symbol: 'US\$',
    );
    final integer = NumberFormat.decimalPattern(locale);
    String amount(num? cents) =>
        cents == null ? '—' : money.format(cents / 100);
    String count(num? value) => value == null ? '—' : integer.format(value);
    final metrics = <String, (MetricComparison, IconData, bool)>{
      'Sales': (result.sales, Icons.attach_money, true),
      'Orders': (result.orders, Icons.receipt_long_outlined, false),
      'Average Order': (result.averageOrder, Icons.trending_up, true),
      'Items Sold': (result.itemsSold, Icons.restaurant_outlined, false),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns = constraints.maxWidth >= 1080 * scale ? 4 : 2;
            return _Grid(
              key: ValueKey('analytics-kpi-columns-$columns'),
              columns: columns,
              children: [
                for (final entry in metrics.entries)
                  _RevenueCard(
                    key: Key('analytics-kpi-${entry.key}'),
                    title: entry.key,
                    monetary: entry.value.$3,
                    icon: entry.value.$2,
                    value: entry.value.$3
                        ? amount(entry.value.$1.current)
                        : count(entry.value.$1.current),
                    previous: comparisonCovered
                        ? (entry.value.$3
                              ? amount(entry.value.$1.previous)
                              : count(entry.value.$1.previous))
                        : '—',
                    change: _Change(
                      metric: entry.value.$1,
                      covered: comparisonCovered,
                      revenue: entry.key == 'Sales',
                    ),
                  ),
              ],
            );
          },
        ),
        PelinesCard(
          key: const Key('analytics-revenue-comparison'),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(context, 'Current period'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              _SingleLineAmount(
                amount(result.sales.current),
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Divider(height: 24),
              Text('${tr(context, 'Previous period')}:'),
              _SingleLineAmount(
                comparisonCovered ? amount(result.sales.previous) : '—',
              ),
              _SingleLineAmount(
                comparisonCovered && result.sales.difference != null
                    ? '${result.sales.difference! > 0 ? '+' : ''}${amount(result.sales.difference)}'
                    : '—',
                key: const Key('analytics-revenue-difference'),
              ),
              _Change(
                metric: result.sales,
                covered: comparisonCovered,
                revenue: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Grid(
          columns: 2,
          children: [
            for (final type in [OrderType.online, OrderType.catering])
              Builder(
                builder: (context) {
                  final current = result.current.orderTypes[type]!;
                  final previous = result.previous.orderTypes[type]!;
                  return _RevenueCard(
                    key: ValueKey('analytics-revenue-${type.name}'),
                    title: type == OrderType.online
                        ? 'Regular Orders Revenue'
                        : 'Catering Orders Revenue',
                    icon: type == OrderType.online
                        ? Icons.restaurant_outlined
                        : Icons.groups_outlined,
                    value: amount(current.salesCents),
                    previous: comparisonCovered
                        ? amount(previous.salesCents)
                        : '—',
                    detail:
                        '${tr(context, 'Orders')}: ${count(current.orders)}',
                    previousDetail: comparisonCovered
                        ? '${tr(context, 'Orders')}: ${count(previous.orders)}'
                        : null,
                    change: _Change(
                      metric: MetricComparison(
                        current.salesCents,
                        previous.salesCents,
                      ),
                      covered: comparisonCovered,
                      revenue: true,
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({super.key, required this.columns, required this.children});
  final int columns;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var row = 0; row < children.length; row += columns)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (
                  var column = 0;
                  column < columns && row + column < children.length;
                  column++
                ) ...[
                  if (column > 0) const SizedBox(width: 12),
                  Expanded(child: children[row + column]),
                ],
              ],
            ),
          ),
        ),
    ],
  );
}

class _RevenueCard extends StatelessWidget {
  const _RevenueCard({
    super.key,
    required this.title,
    required this.icon,
    required this.value,
    required this.previous,
    required this.change,
    this.detail,
    this.previousDetail,
    this.monetary = true,
  });
  final String title, value, previous;
  final String? detail, previousDetail;
  final IconData icon;
  final Widget change;
  final bool monetary;
  @override
  Widget build(BuildContext context) => PelinesCard(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                tr(context, title),
                style: PelinesTypography.smallLabel,
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon, color: PelinesColors.brandPrimary, size: 20),
          ],
        ),
        const SizedBox(height: 16),
        if (monetary)
          _SingleLineAmount(
            value,
            style: PelinesTypography.pageTitle(Theme.of(context).textTheme)
                ?.copyWith(fontSize: 30),
          )
        else
          Text(
            value,
            softWrap: true,
            style: PelinesTypography.pageTitle(Theme.of(context).textTheme)
                ?.copyWith(fontSize: 30),
          ),
        if (detail != null) Text(detail!),
        const Divider(height: 24),
        if (monetary) ...[
          Text(
            '${tr(context, 'Previous period')}:',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          _SingleLineAmount(
            previous,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ] else
          Text(
            '${tr(context, 'Previous period')}: $previous',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (previousDetail != null)
          Text(previousDetail!, style: Theme.of(context).textTheme.bodySmall),
        change,
      ],
    ),
  );
}

/// Keep the full currency string and the preferred size whenever it fits.
/// Extreme amounts may scale below 14 px: the approved priority is full visibility.
class _SingleLineAmount extends StatelessWidget {
  const _SingleLineAmount(this.value, {super.key, this.style});
  final String value;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: AlignmentDirectional.centerStart,
    child: Text(value, style: style, maxLines: 1, softWrap: false),
  );
}

class _Change extends StatelessWidget {
  const _Change({
    required this.metric,
    required this.covered,
    required this.revenue,
  });
  final MetricComparison metric;
  final bool covered, revenue;
  @override
  Widget build(BuildContext context) {
    final percent = covered ? metric.percentChange : null;
    final value = percent == null
        ? '—'
        : '${percent > 0 ? '+' : ''}${NumberFormat('0.0', Localizations.localeOf(context).toLanguageTag()).format(percent)}%';
    // Direction alone is not a business judgment for volume, items or basket size.
    final color = !revenue || percent == null || percent == 0
        ? PelinesColors.textSecondary
        : percent > 0
        ? PelinesColors.successForeground
        : PelinesColors.destructive;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        '$value ${tr(context, 'vs previous period')}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}
