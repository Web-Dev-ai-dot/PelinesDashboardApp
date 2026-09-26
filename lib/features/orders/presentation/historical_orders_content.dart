import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_order_badges.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../models/order_models.dart';
import 'order_ui_helpers.dart';

/// Shared presentation of loaded historical rows. Filtering and timestamp
/// selection remain owned by the historical screen/providers.
class HistoricalOrdersContent extends StatelessWidget {
  const HistoricalOrdersContent({
    required this.orders,
    required this.completed,
    super.key,
  });
  final List<OrderSummary> orders;
  final bool completed;

  String _date(BuildContext context, OrderSummary order) {
    final time = completed
        ? order.deliveredAt ?? order.operationalAt
        : order.operationalAt;
    final label = completed && order.deliveredAt != null
        ? fulfillmentLabelForCompletion(order.fulfillmentType)
        : order.scheduledFor != null
        ? 'Scheduled'
        : 'Placed';
    return '${tr(context, label)}: ${PelinesTime.formatDateTime(time)}';
  }

  @override
  Widget build(BuildContext context) => PelinesAdaptiveTable<OrderSummary>(
    key: const Key('historical-adaptive-table'),
    rows: orders,
    empty: const SizedBox.shrink(),
    columns: [
      PelinesTableColumn(
        label: tr(context, 'Order'),
        cell: (o) => Text(
          o.orderNumber,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      PelinesTableColumn(
        label: tr(context, 'Order type'),
        cell: (o) => _type(context, o),
      ),
      PelinesTableColumn(
        label: tr(context, 'Fulfillment'),
        cell: (o) => _fulfillment(context, o),
      ),
      PelinesTableColumn(
        label: tr(context, 'Customer / Event'),
        cell: (o) => SizedBox(width: 200, child: _Customer(order: o)),
      ),
      PelinesTableColumn(
        label: tr(context, 'Status'),
        cell: (o) => _status(context, o),
      ),
      PelinesTableColumn(
        label: tr(context, 'Amount'),
        numeric: true,
        cell: (o) => Text(
          money(o.totalCents),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      PelinesTableColumn(
        label: tr(
          context,
          completed ? 'Completion / operational date' : 'Operational date',
        ),
        cell: (o) => SizedBox(width: 190, child: Text(_date(context, o))),
      ),
      PelinesTableColumn(
        label: tr(context, 'Payment'),
        cell: (o) => _payment(context, o),
      ),
      PelinesTableColumn(
        label: tr(context, 'View'),
        cell: (o) => _view(context, o),
      ),
    ],
    cardBuilder: (context, order) => PelinesCard(
      key: ValueKey('history-card-${order.id}'),
      variant: PelinesCardVariant.compact,
      child: InkWell(
        onTap: () => context.push('/app/orders/${order.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              order.orderNumber,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _type(context, order),
                _fulfillment(context, order),
                _status(context, order),
                _payment(context, order),
              ],
            ),
            const SizedBox(height: 16),
            _Customer(order: order),
            const SizedBox(height: 12),
            Text(
              _date(context, order),
              style: const TextStyle(color: PelinesColors.textSecondary),
            ),
            const SizedBox(height: 12),
            PelinesLabelValueRow(
              alignValueEnd: true,
              label: Text(
                '${order.itemCount} ${tr(context, order.itemCount == 1 ? 'item' : 'items')}',
              ),
              value: Text(
                money(order.totalCents),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _view(context, order),
          ],
        ),
      ),
    ),
  );

  Widget _view(BuildContext context, OrderSummary order) => PelinesButton(
    key: ValueKey('history-view-${order.id}'),
    label: tr(context, 'View'),
    variant: PelinesButtonVariant.secondary,
    onPressed: () => context.push('/app/orders/${order.id}'),
  );
  Widget _type(BuildContext c, OrderSummary o) => PelinesOrderBadges.type(
    type: o.orderType,
    label: tr(c, orderTypeLabel(o.orderType)),
  );
  Widget _fulfillment(BuildContext c, OrderSummary o) =>
      PelinesOrderBadges.fulfillment(
        fulfillment: o.fulfillmentType,
        label: tr(c, fulfillmentLabel(o.fulfillmentType)),
      );
  Widget _status(BuildContext c, OrderSummary o) => PelinesOrderBadges.status(
    status: o.status,
    label: tr(c, statusLabel(o.status, o.fulfillmentType, o.rawStatus)),
  );
  Widget _payment(BuildContext c, OrderSummary o) => PelinesOrderBadges.payment(
    payment: o.paymentStatus,
    label: tr(c, paymentStatusLabel(o.paymentStatus)),
  );
}

String fulfillmentLabelForCompletion(FulfillmentType type) =>
    type == FulfillmentType.pickup ? 'Picked up' : 'Delivered';

class _Customer extends StatelessWidget {
  const _Customer({required this.order});
  final OrderSummary order;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        order.contactName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      if (order.eventName?.isNotEmpty == true)
        Text(
          order.eventName!,
          style: const TextStyle(
            fontStyle: FontStyle.italic,
            color: PelinesColors.textSecondary,
          ),
        ),
    ],
  );
}
