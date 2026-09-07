import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/pelines_tokens.dart';
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

String paymentStatusLabel(PaymentStatus status) => switch (status) {
  PaymentStatus.unpaid => 'Unpaid',
  PaymentStatus.paid => 'Paid',
  PaymentStatus.refunded => 'Refunded',
  PaymentStatus.failed => 'Failed',
  PaymentStatus.unknown => 'Unknown payment',
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
    final PelinesStatusColors colors =
        Theme.of(context).extension<PelinesStatusColors>() ??
        const PelinesStatusColors.light();
    final (Color foreground, Color background) = switch (status) {
      OrderStatus.pending => (colors.pending, colors.pendingBackground),
      OrderStatus.confirmed => (colors.confirmed, colors.confirmedBackground),
      OrderStatus.preparing => (PelinesColors.card, colors.preparing),
      OrderStatus.ready => (PelinesColors.card, colors.ready),
      OrderStatus.delivered => (colors.completed, colors.completedBackground),
      OrderStatus.cancelled => (colors.cancelled, colors.cancelledBackground),
      OrderStatus.unknown => (
        PelinesColors.textSecondary,
        PelinesColors.mutedSurface,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PelinesSpacing.sm,
        vertical: PelinesSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PelinesRadius.pill),
      ),
      child: Text(
        statusLabel(status, fulfillment, rawStatus),
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
