import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/time/pelines_time.dart';
import '../models/order_models.dart';

String money(int cents) =>
    NumberFormat.currency(symbol: r'$').format(cents / 100);

String orderTypeLabel(OrderType type) => switch (type) {
  OrderType.online => 'Regular',
  OrderType.catering => 'Catering',
  OrderType.unknown => 'Unknown type',
};

String fulfillmentLabel(FulfillmentType type) => switch (type) {
  FulfillmentType.pickup => 'Pickup',
  FulfillmentType.delivery => 'Delivery',
  FulfillmentType.unknown => 'Unknown fulfillment',
};

String statusLabel(
  OrderStatus status,
  FulfillmentType fulfillment,
  String raw,
) => switch (status) {
  OrderStatus.pending => 'Waiting',
  OrderStatus.confirmed => 'Confirmed',
  OrderStatus.preparing => 'Preparing',
  OrderStatus.ready => 'Ready',
  OrderStatus.delivered =>
    fulfillment == FulfillmentType.pickup ? 'Picked up' : 'Delivered',
  OrderStatus.cancelled => 'Cancelled',
  OrderStatus.unknown => 'Unknown ($raw)',
};

Color statusColor(OrderStatus status) => switch (status) {
  OrderStatus.pending => Colors.amber.shade800,
  OrderStatus.confirmed => Colors.green.shade700,
  OrderStatus.preparing => Colors.purple.shade600,
  OrderStatus.ready => Colors.red.shade700,
  OrderStatus.delivered => Colors.blue.shade700,
  OrderStatus.cancelled => Colors.red.shade900,
  OrderStatus.unknown => Colors.grey.shade700,
};

String requestedTime(DateTime? scheduledFor) =>
    scheduledFor == null ? 'ASAP' : PelinesTime.formatTime(scheduledFor);

class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.status,
    required this.fulfillment,
    required this.rawStatus,
    super.key,
  });
  final OrderStatus status;
  final FulfillmentType fulfillment;
  final String rawStatus;

  @override
  Widget build(BuildContext context) {
    final Color color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        statusLabel(status, fulfillment, rawStatus),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
