import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_order_badges.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../models/order_models.dart';
import '../providers/order_alerts_controller.dart';
import '../providers/orders_providers.dart';
import 'order_parity_content.dart';
import 'todo_print_action.dart';
import 'order_preview_action.dart';
import 'order_ui_helpers.dart';

/// Operational preview only: shared detail/calendar/fullscreen visuals remain
/// independent. All mutations stay in OrderPreviewAction's existing controller.
class OrderPreviewCard extends ConsumerWidget {
  const OrderPreviewCard({
    required this.order,
    this.statusBoard = false,
    super.key,
  });
  final OrderSummary order;
  final bool statusBoard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = statusBoard
        ? ref.watch(orderDetailProvider(order.id))
        : null;
    void view() {
      ref.read(orderAlertsProvider.notifier).acknowledge(order.id);
      context.push('/app/orders/${order.id}');
    }

    final date = MaterialLocalizations.of(context)
        .formatShortDate(PelinesTime.inPacific(order.operationalAt));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: PelinesColors.card,
        elevation: 1,
        shadowColor: PelinesColors.border,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: PelinesColors.border, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: view,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  order.orderNumber,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  requestedTime(order.scheduledFor),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$date · ${tr(context, 'Pacific time')}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: PelinesColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    PelinesOrderBadges.status(
                      status: order.status,
                      label: tr(
                        context,
                        statusLabel(
                          order.status,
                          order.fulfillmentType,
                          order.rawStatus,
                        ),
                      ),
                    ),
                    PelinesOrderBadges.type(
                      type: order.orderType,
                      label: tr(context, orderTypeLabel(order.orderType)),
                    ),
                    PelinesOrderBadges.fulfillment(
                      fulfillment: order.fulfillmentType,
                      label: tr(
                        context,
                        fulfillmentLabel(order.fulfillmentType),
                      ),
                    ),
                    if (!order.paymentStatus.isOperationallyPaid)
                      PelinesOrderBadges.payment(
                        payment: order.paymentStatus,
                        label: tr(
                          context,
                          paymentStatusLabel(order.paymentStatus),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  order.contactName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (order.eventName?.isNotEmpty == true)
                  Text(
                    order.eventName!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      color: PelinesColors.textSecondary,
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  '${order.itemCount} ${tr(context, order.itemCount == 1 ? 'item' : 'items')}',
                  style: PelinesTypography.smallLabel,
                ),
                const SizedBox(height: 6),
                if (statusBoard) ...[
                  if (detail!.hasError)
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(orderDetailProvider(order.id)),
                      child: Text(tr(context, 'Refresh order status')),
                    )
                  else if (detail.value == null)
                    const LinearProgressIndicator()
                  else
                    for (final item in detail.value!.items)
                      OrderParityItem(item: item),
                  Text(
                    tr(context, 'Total'),
                    style: PelinesTypography.smallLabel,
                  ),
                ],
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    money(order.totalCents),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  // Consume taps on a disabled action instead of opening detail.
                  onTap: () {},
                  excludeFromSemantics: true,
                  child: OrderPreviewAction(
                    key: ValueKey(order.id),
                    order: order,
                    webStyle: true,
                    showNextStatus: statusBoard,
                  ),
                ),
                const SizedBox(height: 8),
                if (statusBoard) ...[
                  TodoPrintAction(order: order),
                  const SizedBox(height: 8),
                ],
                PelinesButton(
                  label: tr(context, 'View'),
                  variant: PelinesButtonVariant.secondary,
                  onPressed: view,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
