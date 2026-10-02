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
    super.key,
  });
  final String label, value;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          CircleAvatar(
            radius: 20,
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
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
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
  const OrderParityItem({required this.item, super.key});
  final OrderItem item;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                    '${modifier.groupName}: ${modifier.optionName}${modifier.priceDeltaCents == 0 ? '' : ' (+${money(modifier.priceDeltaCents)})'}',
                    style: const TextStyle(color: PelinesColors.textSecondary),
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
        Text(
          order.orderNumber,
          key: const Key('alert-order-number'),
          style: PelinesTypography.pageTitle(Theme.of(context).textTheme)
              ?.copyWith(fontSize: 36),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: PelinesOrderBadges.status(
            status: order.status,
            label: tr(
              context,
              statusLabel(order.status, order.fulfillmentType, order.rawStatus),
            ),
          ),
        ),
        const SizedBox(height: 20),
        PelinesCard(
          key: const Key('alert-customer-context'),
          child: Column(
            children: [
              OrderInfoField(
                label: tr(context, 'Client'),
                value: order.contactName,
                icon: Icons.person_outline,
              ),
              OrderInfoField(
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
                    : [
                        locationName,
                        if (locationAddress?.trim().isNotEmpty == true)
                          locationAddress!,
                      ].join(' · '),
                icon: Icons.location_on_outlined,
              ),
              OrderInfoField(
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
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AdminLocalizations.of(context)
                          .text('Order Type', key: 'alert.Order Type')
                          .toUpperCase(),
                      style: PelinesTypography.smallLabel,
                    ),
                    const SizedBox(height: 8),
                    PelinesOrderBadges.type(
                      type: order.orderType,
                      label: tr(context, orderTypeLabel(order.orderType)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (order.items.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            tr(context, 'Items'),
            style: PelinesTypography.sectionTitle(Theme.of(context).textTheme),
          ),
          const SizedBox(height: 12),
          for (final item in order.items) OrderParityItem(item: item),
        ],
        if (order.notes?.trim().isNotEmpty == true)
          OrderInfoField(
            label: tr(context, 'Note'),
            value: order.notes!,
            icon: Icons.notes_outlined,
          ),
        const SizedBox(height: 16),
        PelinesCard(
          key: const Key('alert-total'),
          child: PelinesLabelValueRow(
            alignValueEnd: true,
            label: Text(
              tr(context, 'Total Order Value'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            value: Text(
              money(order.totalCents),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: PelinesColors.brandPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
