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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (constraints.maxWidth >= 840 * scale) return _table(context);
      return Material(
        key: const Key('history-shared-surface'),
        color: PelinesColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: PelinesColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final (index, order) in orders.indexed) ...[
              if (index > 0) const Divider(height: 1),
              _compactRow(context, order),
            ],
          ],
        ),
      );
    },
  );

  Widget _table(BuildContext context) => PelinesAdaptiveTable<OrderSummary>(
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
    cardBuilder: _compactRow,
  );

  Widget _compactRow(BuildContext context, OrderSummary order) => InkWell(
    key: ValueKey('history-row-${order.id}'),
    onTap: () => context.push('/app/orders/${order.id}'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.orderNumber,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              _Customer(order: order),
              const SizedBox(height: 6),
              Text(
                '${_date(context, order)} · ${tr(context, orderTypeLabel(order.orderType))}',
                style: const TextStyle(color: PelinesColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                tr(
                  context,
                  completed
                      ? fulfillmentLabelForCompletion(order.fulfillmentType)
                      : fulfillmentLabel(order.fulfillmentType),
                ),
                style: const TextStyle(color: PelinesColors.textSecondary),
              ),
              const SizedBox(height: 6),
              _payment(context, order),
            ],
          );
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money(order.totalCents),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              _status(context, order),
              const SizedBox(height: 6),
              Icon(Icons.chevron_right, semanticLabel: tr(context, 'View')),
            ],
          );
          return constraints.maxWidth >= 280 * scale
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: 16),
                    summary,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    info,
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: summary,
                    ),
                  ],
                );
        },
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
  Widget _status(BuildContext c, OrderSummary o) => PelinesStateBadge(
    label: tr(c, completed ? 'Completed' : 'Cancelled'),
    foreground: completed
        ? PelinesColors.successForeground
        : PelinesColors.destructive,
    background: completed
        ? PelinesColors.successBackground
        : PelinesColors.brandPrimarySoft,
    icon: completed ? Icons.check_circle_outline : Icons.cancel_outlined,
  );
  Widget _payment(BuildContext c, OrderSummary o) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      PelinesOrderBadges.payment(
        payment: o.paymentStatus,
        label: tr(c, paymentStatusLabel(o.paymentStatus)),
      ),
      if (!completed && o.paymentStatus == PaymentStatus.paid) ...[
        const SizedBox(height: 6),
        SizedBox(
          width: 220,
          child: Text(
            tr(c, 'Payment remains paid; refund not confirmed.'),
            key: ValueKey('history-refund-warning-${o.id}'),
            style: const TextStyle(
              color: PelinesColors.destructive,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ],
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
