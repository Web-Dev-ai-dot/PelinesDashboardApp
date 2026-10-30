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
    this.showChannel = false,
    this.planning = false,
    this.primaryDetailsAction = false,
    this.compactPlanning = false,
    super.key,
  });
  final OrderSummary order;
  final bool statusBoard;
  final bool showChannel;
  final bool planning;
  final bool primaryDetailsAction;
  final bool compactPlanning;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final richLayout = statusBoard || planning;
    final pickedUpBoard =
        statusBoard &&
        !planning &&
        order.status == OrderStatus.delivered &&
        order.fulfillmentType == FulfillmentType.pickup;
    final detail = statusBoard || planning
        ? ref.watch(orderDetailProvider(order.id))
        : null;
    void view() {
      if (!planning) {
        ref.read(orderAlertsProvider.notifier).acknowledge(order.id);
      }
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
          side: BorderSide(
            color: PelinesColors.border,
            width: richLayout ? 1 : 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: view,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: richLayout ? 16 : 20,
              vertical: compactPlanning ? 12 : (richLayout ? 16 : 20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: compactPlanning
                  ? _monthContents(
                      context,
                      detail,
                      date,
                      view,
                      () => ref.invalidate(orderDetailProvider(order.id)),
                    )
                  : [
                      Text(
                        order.orderNumber,
                        style: TextStyle(
                          fontSize: richLayout ? 20 : 16,
                          fontWeight: richLayout
                              ? FontWeight.w700
                              : FontWeight.w600,
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
                          if (pickedUpBoard)
                            PelinesStateBadge(
                              label: tr(context, 'Picked up').toUpperCase(),
                              foreground: PelinesColors.textPrimary,
                              background: PelinesColors.border,
                            )
                          else
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
                          if (showChannel &&
                              const {
                                'web',
                                'ios',
                                'android',
                                'counter',
                              }.contains(detail?.value?.source))
                            PelinesStateBadge(
                              label: switch (detail!.value!.source) {
                                'ios' => 'iOS',
                                'android' => 'Android',
                                'counter' => tr(context, 'Counter'),
                                _ => 'Web',
                              },
                              foreground: PelinesColors.textSecondary,
                              background: PelinesColors.mutedSurface,
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
                      if (statusBoard || planning) ...[
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
                      ],
                      if (richLayout)
                        PelinesLabelValueRow(
                          alignValueEnd: true,
                          label: Text(
                            tr(context, 'Total'),
                            style: PelinesTypography.smallLabel,
                          ),
                          value: Text(
                            money(order.totalCents),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: PelinesColors.brandPrimary,
                            ),
                          ),
                        )
                      else
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
                      if (!planning)
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
                      if (statusBoard && !planning) ...[
                        TodoPrintAction(order: order),
                        const SizedBox(height: 8),
                      ],
                      PelinesButton(
                        label: tr(
                          context,
                          planning ? 'View Order Details' : 'View',
                        ),
                        variant: primaryDetailsAction
                            ? PelinesButtonVariant.primary
                            : PelinesButtonVariant.secondary,
                        onPressed: view,
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _monthContents(
    BuildContext context,
    AsyncValue<OrderDetail>? detail,
    String date,
    VoidCallback view,
    VoidCallback retry,
  ) {
    final source = detail?.value?.source;
    final heading = Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          order.orderNumber,
          key: ValueKey('month-order-number-${order.id}'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        Text(
          requestedTime(order.scheduledFor),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
    return [
      LayoutBuilder(
        builder: (context, c) {
          final dateText = Text(
            date,
            key: ValueKey('month-order-date-${order.id}'),
            style: const TextStyle(
              fontSize: 12,
              color: PelinesColors.textSecondary,
            ),
          );
          return c.maxWidth >= 300 * MediaQuery.textScalerOf(context).scale(1)
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 8),
                    dateText,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading,
                    Align(alignment: Alignment.centerRight, child: dateText),
                  ],
                );
        },
      ),
      const SizedBox(height: 8),
      Wrap(
        key: ValueKey('month-order-badges-${order.id}'),
        spacing: 6,
        runSpacing: 6,
        children: [
          PelinesStateBadge(
            label: tr(context, orderTypeLabel(order.orderType)).toUpperCase(),
            foreground: switch (order.orderType) {
              OrderType.catering => PelinesColors.amberForeground,
              OrderType.online => PelinesColors.blue,
              _ => PelinesColors.textSecondary,
            },
            background: switch (order.orderType) {
              OrderType.catering => PelinesColors.brandYellowSoft,
              OrderType.online => PelinesColors.blueSoft,
              _ => PelinesColors.mutedSurface,
            },
          ),
          if (showChannel &&
              const {'web', 'ios', 'android', 'counter'}.contains(source))
            PelinesStateBadge(
              label: switch (source) {
                'ios' => 'iOS',
                'android' => 'Android',
                'counter' => tr(context, 'Counter'),
                _ => 'Web',
              },
              foreground: PelinesColors.textSecondary,
              background: PelinesColors.mutedSurface,
            ),
          PelinesOrderBadges.fulfillment(
            fulfillment: order.fulfillmentType,
            label: tr(context, fulfillmentLabel(order.fulfillmentType)),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        order.contactName,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      if (order.eventName?.trim().isNotEmpty == true)
        Text(
          order.eventName!,
          style: const TextStyle(
            fontSize: 13,
            color: PelinesColors.textSecondary,
          ),
        ),
      const Divider(height: 16, color: PelinesColors.border, thickness: 1),
      Text(
        '${order.itemCount} ${tr(context, order.itemCount == 1 ? 'item' : 'items')}',
        style: PelinesTypography.smallLabel,
      ),
      const SizedBox(height: 6),
      if (detail?.hasError == true)
        TextButton(
          onPressed: retry,
          child: Text(tr(context, 'Refresh order status')),
        )
      else if (detail?.value == null)
        const LinearProgressIndicator()
      else
        for (final item in detail!.value!.items)
          OrderParityItem(item: item, compact: true, showAmounts: false),
      const SizedBox(height: 8),
      PelinesButton(label: tr(context, 'View Order Details'), onPressed: view),
    ];
  }
}
