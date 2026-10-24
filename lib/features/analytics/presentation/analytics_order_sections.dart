import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../data/analytics_repository.dart';
import '../models/analytics_result.dart';
import '../../orders/models/order_models.dart';
import 'analytics_metric_cards.dart';
import 'analytics_operational_cards.dart';

class AnalyticsOrderVolume extends StatelessWidget {
  const AnalyticsOrderVolume({
    super.key,
    required this.dataset,
    required this.period,
  });
  final AnalyticsDataset dataset;
  final AnalyticsPeriodResult period;
  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final number = NumberFormat.decimalPattern(locale);
    final money = NumberFormat.currency(
      locale: locale,
      name: 'USD',
      symbol: 'US\$',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr(context, 'Order count trends and demand patterns.')),
        const SizedBox(height: 16),
        AnalyticsMetricGrid(
          children: [
            AnalyticsMetricCard(
              key: const Key('analytics-volume-total'),
              label: tr(context, 'Total Orders'),
              value: number.format(period.orders),
              icon: Icons.inventory_2_outlined,
            ),
            AnalyticsMetricCard(
              key: const Key('analytics-volume-regular'),
              label: tr(context, 'Regular Orders'),
              value: number.format(period.orderTypes[OrderType.online]!.orders),
              icon: Icons.restaurant_outlined,
            ),
            AnalyticsMetricCard(
              key: const Key('analytics-volume-catering'),
              label: tr(context, 'Catering Orders'),
              value: number.format(
                period.orderTypes[OrderType.catering]!.orders,
              ),
              icon: Icons.groups_outlined,
            ),
            AnalyticsMetricCard(
              key: const Key('analytics-volume-average'),
              label: tr(context, 'Average Ticket'),
              value: period.averageOrderCents == null
                  ? '—'
                  : money.format(period.averageOrderCents! / 100),
              icon: Icons.trending_up,
            ),
          ],
        ),
        AnalyticsDemandCards(dataset: dataset, range: period.range),
      ],
    );
  }
}

class AnalyticsStatusCards extends StatelessWidget {
  const AnalyticsStatusCards({
    super.key,
    required this.dataset,
    required this.period,
  });
  final AnalyticsDataset dataset;
  final AnalyticsPeriodResult period;
  @override
  Widget build(BuildContext context) {
    final orders = dataset.orders.where(
      (o) =>
          o.locationId == dataset.locationId &&
          o.isEligible &&
          period.range.contains(o.createdAt),
    );
    final number = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final counts = <OrderStatus, int>{};
    for (final order in orders) {
      counts.update(order.status, (count) => count + 1, ifAbsent: () => 1);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr(context, 'Order distribution by status.')),
        const SizedBox(height: 16),
        AnalyticsMetricCard(
          key: const Key('analytics-status-completed'),
          label: tr(context, 'Completed'),
          value: number.format(period.completed),
          icon: Icons.check_circle_outline,
          completed: true,
        ),
        const SizedBox(height: 12),
        AnalyticsMetricGrid(
          children: [
            for (final entry in {
              OrderStatus.pending: 'Waiting for Approval',
              OrderStatus.confirmed: 'Confirmed',
              OrderStatus.preparing: 'Preparing',
              OrderStatus.ready: 'Ready',
            }.entries)
              AnalyticsMetricCard(
                key: ValueKey('analytics-status-${entry.key.name}'),
                label: tr(context, entry.value),
                value: number.format(counts[entry.key] ?? 0),
                icon: Icons.receipt_long_outlined,
              ),
            for (final entry in {
              'Cancelled': period.cancelled,
              'In Progress': period.inProgress,
            }.entries)
              AnalyticsMetricCard(
                key: ValueKey(
                  entry.key == 'Cancelled'
                      ? 'analytics-status-cancelled'
                      : 'analytics-status-in-progress',
                ),
                label: tr(context, entry.key),
                value: number.format(entry.value),
                icon: entry.key == 'Cancelled'
                    ? Icons.cancel_outlined
                    : Icons.pending_actions,
              ),
          ],
        ),
      ],
    );
  }
}
