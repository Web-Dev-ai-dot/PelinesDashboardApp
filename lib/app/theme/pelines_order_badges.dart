import 'package:flutter/material.dart';

import '../../features/orders/models/order_models.dart';
import 'pelines_components.dart';
import 'pelines_tokens.dart';

/// Presentation adapters only. Labels are supplied by the caller's localization
/// layer; backend enums and the pickup/delivery distinction remain unchanged.
abstract final class PelinesOrderBadges {
  static Widget status({required OrderStatus status, required String label}) {
    final (foreground, background) = switch (status) {
      OrderStatus.pending => (
        PelinesColors.amberForeground,
        PelinesColors.brandYellowSoft,
      ),
      OrderStatus.confirmed => (
        PelinesColors.successForeground,
        PelinesColors.successBackground,
      ),
      OrderStatus.preparing => (PelinesColors.card, PelinesColors.preparing),
      OrderStatus.ready => (PelinesColors.card, PelinesColors.statusReady),
      // Flutter's terminal state still means picked up OR delivered, not a new
      // web-only "completed" workflow step.
      OrderStatus.delivered => (PelinesColors.blue, const Color(0x261D74BA)),
      OrderStatus.cancelled => (
        PelinesColors.destructive,
        PelinesColors.brandPrimarySoft,
      ),
      OrderStatus.unknown => (
        PelinesColors.textSecondary,
        PelinesColors.mutedSurface,
      ),
    };
    return PelinesStateBadge(
      label: label,
      foreground: foreground,
      background: background,
      dot: true,
    );
  }

  static Widget type({required OrderType type, required String label}) =>
      PelinesStateBadge(
        label: label.toUpperCase(),
        foreground: switch (type) {
          OrderType.online => PelinesColors.blue,
          OrderType.catering => PelinesColors.amberForeground,
          OrderType.unknown => PelinesColors.textSecondary,
        },
        background: Colors.transparent,
        outlined: true,
      );

  static Widget fulfillment({
    required FulfillmentType fulfillment,
    required String label,
  }) => PelinesStateBadge(
    label: label,
    foreground: PelinesColors.textSecondary,
    background: PelinesColors.mutedSurface,
    icon: switch (fulfillment) {
      FulfillmentType.pickup => Icons.shopping_bag_outlined,
      FulfillmentType.delivery => Icons.local_shipping_outlined,
      FulfillmentType.unknown => Icons.help_outline,
    },
  );

  static Widget payment({
    required PaymentStatus payment,
    required String label,
  }) {
    final (foreground, background) = switch (payment) {
      PaymentStatus.paid => (
        PelinesColors.successForeground,
        PelinesColors.successBackground,
      ),
      PaymentStatus.refunded || PaymentStatus.failed => (
        PelinesColors.destructive,
        PelinesColors.brandPrimarySoft,
      ),
      PaymentStatus.unpaid || PaymentStatus.unknown => (
        PelinesColors.textSecondary,
        PelinesColors.mutedSurface,
      ),
    };
    return PelinesStateBadge(
      label: label,
      foreground: foreground,
      background: background,
      icon: Icons.payments_outlined,
    );
  }
}
