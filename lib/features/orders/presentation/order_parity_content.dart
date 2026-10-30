import 'package:flutter/material.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_order_badges.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../models/order_models.dart';
import 'order_ui_helpers.dart';

/// Visual adapters only: values are the canonical backend fields, never derived
/// prices, workflow state, or a second source of operational decisions.
class OrderParityBadges extends StatelessWidget {
  const OrderParityBadges({required this.order, super.key});
  final OrderDetail order;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      PelinesOrderBadges.status(
        status: order.status,
        label: tr(
          context,
          statusLabel(order.status, order.fulfillmentType, order.rawStatus),
        ),
      ),
      PelinesOrderBadges.fulfillment(
        fulfillment: order.fulfillmentType,
        label: tr(context, fulfillmentLabel(order.fulfillmentType)),
      ),
      PelinesOrderBadges.type(
        type: order.orderType,
        label: tr(context, orderTypeLabel(order.orderType)),
      ),
    ],
  );
}

class OrderInfoField extends StatelessWidget {
  const OrderInfoField({
    required this.label,
    required this.value,
    this.icon,
    this.compact = false,
    this.valueWidget,
    super.key,
  });
  final String label, value;
  final IconData? icon;
  final bool compact;
  final Widget? valueWidget;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: compact ? 4 : 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          CircleAvatar(
            radius: compact ? 16 : 20,
            backgroundColor: PelinesColors.brandPrimarySoft,
            child: Icon(icon, size: 20, color: PelinesColors.brandPrimary),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: PelinesTypography.smallLabel),
              SizedBox(height: compact ? 4 : 6),
              valueWidget ??
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: compact ? 16 : 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            ],
          ),
        ),
      ],
    ),
  );
}

String orderScheduledLabel(BuildContext context, OrderDetail order) =>
    order.scheduledFor == null
    ? tr(context, 'ASAP')
    : '${PelinesTime.formatDateTime(order.scheduledFor!)} · ${tr(context, 'Pacific time')}';

class OrderParityItem extends StatelessWidget {
  const OrderParityItem({
    required this.item,
    this.compact = false,
    this.inlineAmounts = false,
    this.showAmounts = true,
    super.key,
  });
  final OrderItem item;
  final bool compact;
  final bool inlineAmounts;
  final bool showAmounts;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: compact ? (showAmounts ? 12 : 6) : 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!showAmounts)
          Text(
            '${item.quantity}× ${item.productName}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          )
        else if (inlineAmounts)
          OrderInlineValueRow(
            label: Text(
              '${item.quantity}× ${item.productName}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            value: Text(
              money(item.lineTotalCents),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          )
        else
          PelinesLabelValueRow(
            alignValueEnd: true,
            label: Text(
              '${item.quantity}× ${item.productName}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            value: Text(
              money(item.lineTotalCents),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        if (item.modifiers.isNotEmpty || item.notes?.trim().isNotEmpty == true)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.only(left: 12),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: PelinesColors.brandPrimary, width: 2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final modifier in item.modifiers)
                  Text(
                    '${modifier.groupName}: ${modifier.optionName}${!showAmounts || modifier.priceDeltaCents == 0 ? '' : ' (+${money(modifier.priceDeltaCents)})'}',
                    style: TextStyle(
                      color: PelinesColors.textSecondary,
                      fontSize: showAmounts ? null : 13,
                    ),
                  ),
                if (item.notes?.trim().isNotEmpty == true)
                  Text(
                    '${tr(context, 'Note')}: ${item.notes}',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Used by Detail only: keep amounts at the right and let long labels wrap.
/// Long labels wrap within their column without moving the amount below them.
class OrderInlineValueRow extends StatelessWidget {
  const OrderInlineValueRow({
    required this.label,
    required this.value,
    super.key,
  });
  final Widget label, value;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Row(
      children: [
        Expanded(child: label),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: (constraints.maxWidth - 12) * .65,
          ),
          child: value,
        ),
      ],
    ),
  );
}

class NewOrderParityContent extends StatelessWidget {
  const NewOrderParityContent({
    required this.order,
    required this.locationName,
    this.locationAddress,
    super.key,
  });
  final OrderDetail order;
  final String locationName;
  final String? locationAddress;

  @override
  Widget build(BuildContext context) {
    final delivery = order.fulfillmentType == FulfillmentType.delivery;
    final pickup = order.fulfillmentType == FulfillmentType.pickup;
    final deliveryAddress = [
      for (final key in ['line1', 'line2', 'city', 'state', 'zip'])
        if (order.deliveryAddress?[key] is String &&
            (order.deliveryAddress![key] as String).trim().isNotEmpty)
          order.deliveryAddress![key],
    ].join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PelinesCard(
          key: const Key('alert-customer-context'),
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              OrderInfoField(
                compact: true,
                label: tr(context, 'Client'),
                value: order.contactName,
                icon: Icons.person_outline,
              ),
              OrderInfoField(
                compact: true,
                label: tr(
                  context,
                  delivery
                      ? 'Delivery Location'
                      : pickup
                      ? 'Pickup Location'
                      : 'Location',
                ),
                value: delivery
                    ? (deliveryAddress.isEmpty
                          ? tr(context, 'Not provided')
                          : deliveryAddress)
                    : locationName,
                icon: Icons.location_on_outlined,
              ),
              OrderInfoField(
                compact: true,
                label: tr(
                  context,
                  delivery
                      ? 'Delivery Time'
                      : pickup
                      ? 'Pickup Time'
                      : 'Requested time',
                ),
                value: orderScheduledLabel(context, order),
                icon: Icons.schedule,
              ),
              OrderInfoField(
                compact: true,
                label: AdminLocalizations.of(context)
                    .text('Order Type', key: 'alert.Order Type'),
                value: orderTypeLabel(order.orderType),
                icon: Icons.receipt_long_outlined,
                valueWidget: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: PelinesOrderBadges.type(
                    type: order.orderType,
                    label: tr(context, orderTypeLabel(order.orderType)),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (order.items.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            tr(context, 'Items'),
            style: PelinesTypography.sectionTitle(Theme.of(context).textTheme),
          ),
          const SizedBox(height: 8),
          for (final item in order.items)
            OrderParityItem(item: item, compact: true),
        ],
        if (order.notes?.trim().isNotEmpty == true)
          OrderInfoField(
            compact: true,
            label: tr(context, 'Note'),
            value: order.notes!,
            icon: Icons.notes_outlined,
          ),
        const SizedBox(height: 12),
        OverflowBar(
          key: const Key('alert-total'),
          alignment: MainAxisAlignment.spaceBetween,
          overflowAlignment: OverflowBarAlignment.end,
          spacing: 12,
          overflowSpacing: 4,
          children: [
            Text(
              tr(context, 'Total Order Value'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              money(order.totalCents),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: PelinesColors.brandPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
