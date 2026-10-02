import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pelines_tokens.dart';
import '../../../app/theme/app_theme.dart';
import '../models/order_models.dart';
import '../providers/orders_providers.dart';
import 'order_ui_helpers.dart';

class CancelOrderAction extends ConsumerStatefulWidget {
  const CancelOrderAction({
    required this.order,
    required this.busy,
    this.expanded = false,
    this.sheetStyle = false,
    this.onConfirmationOpened,
    this.onConfirmationClosed,
    super.key,
  });
  final OrderDetail order;
  final bool busy;
  final bool expanded;
  final bool sheetStyle;
  final VoidCallback? onConfirmationOpened;
  final ValueChanged<bool>? onConfirmationClosed;

  @override
  ConsumerState<CancelOrderAction> createState() => CancelOrderActionState();
}

class CancelOrderActionState extends ConsumerState<CancelOrderAction> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) => widget.expanded
      ? OutlinedButton(
          key: const Key('cancel-order-action'),
          style: widget.sheetStyle
              ? OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 56),
                  foregroundColor: PelinesColors.destructive,
                  side: const BorderSide(color: PelinesColors.destructive),
                )
              : PelinesControlStyles.button(PelinesButtonVariant.cancel)
                    .copyWith(
                      minimumSize: const WidgetStatePropertyAll(Size(48, 56)),
                    ),
          onPressed: widget.busy || _confirming ? null : _confirm,
          child: Text(
            tr(context, widget.sheetStyle ? 'Cancel order' : 'Cancel'),
            textAlign: TextAlign.center,
          ),
        )
      : Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('cancel-order-action'),
            style: TextButton.styleFrom(
              foregroundColor: PelinesColors.destructive,
            ),
            onPressed: widget.busy || _confirming ? null : _confirm,
            child: Text(tr(context, 'Cancel Order')),
          ),
        );

  Future<void> _confirm() async {
    if (_confirming || widget.busy) return;
    widget.onConfirmationOpened?.call();
    final OrderDetail order = widget.order;
    setState(() => _confirming = true);
    try {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(tr(context, 'Cancel Order?')),
          content: Text(
            'Cancel ${order.orderNumber} (${money(order.totalCents)})?\n'
            'Cancellation may initiate a refund if this order has already been paid.',
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('cancel-order-keep'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr(context, 'Keep Order')),
            ),
            FilledButton(
              key: const Key('cancel-order-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: PelinesColors.destructive,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr(context, 'Cancel Order')),
            ),
          ],
        ),
      );
      if (!mounted) return;
      widget.onConfirmationClosed?.call(confirmed == true);
      if (confirmed != true || !mounted) return;
      await ref
          .read(orderMutationProvider(order.id).notifier)
          .cancelOrder(order);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }
}
