import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../models/order_models.dart';
import 'order_ui_helpers.dart';

/// Shared presentation only; providers own filtering, ordering and pagination.
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
    return DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .format(PelinesTime.inPacific(time));
  }

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('history-shared-surface'),
    color: PelinesColors.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(PelinesRadius.dialog),
      side: const BorderSide(color: PelinesColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (final (index, order) in orders.indexed) ...[
          if (index > 0) const Divider(height: 1, color: PelinesColors.border),
          _row(context, order),
        ],
      ],
    ),
  );

  Widget _row(BuildContext context, OrderSummary order) => InkWell(
    key: ValueKey('history-row-${order.id}'),
    onTap: () => context.push('/app/orders/${order.id}'),
    child: Padding(
      padding: const EdgeInsets.all(PelinesSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final stacked = constraints.maxWidth < 280 * scale;
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                order.orderNumber,
                key: ValueKey('history-number-${order.id}'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: PelinesSpacing.xxs),
              Text(order.contactName, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: PelinesSpacing.xxs),
              Text(
                '${_date(context, order)} · ${tr(context, orderTypeLabel(order.orderType))}',
                style: const TextStyle(color: PelinesColors.textSecondary),
              ),
            ],
          );
          final summary = SizedBox(
            width: stacked
                ? constraints.maxWidth
                : math.min(constraints.maxWidth * .42, 220 * scale),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(
                            money(order.totalCents),
                            key: ValueKey('history-amount-${order.id}'),
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: PelinesSpacing.xxs),
                      _status(context),
                    ],
                  ),
                ),
                const SizedBox(width: PelinesSpacing.xs),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: PelinesColors.textSecondary,
                  semanticLabel: tr(context, 'View'),
                ),
              ],
            ),
          );
          return stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    info,
                    const SizedBox(height: PelinesSpacing.xs),
                    summary,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: PelinesSpacing.sm),
                    summary,
                  ],
                );
        },
      ),
    ),
  );

  Widget _status(BuildContext context) => DefaultTextStyle.merge(
    style: TextStyle(
      color: completed
          ? PelinesColors.successForeground
          : PelinesColors.destructive,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          completed ? Icons.check_circle : Icons.cancel,
          size: 16,
          color: completed
              ? PelinesColors.successForeground
              : PelinesColors.destructive,
        ),
        const SizedBox(width: PelinesSpacing.xxs),
        Flexible(
          child: Text(tr(context, completed ? 'Completed' : 'Cancelled')),
        ),
      ],
    ),
  );
}
