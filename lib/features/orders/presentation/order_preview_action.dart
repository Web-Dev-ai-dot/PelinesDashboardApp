import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/app_theme.dart';
import '../../locations/providers/locations_providers.dart';
import '../models/order_models.dart';
import '../models/order_status_action.dart';
import '../providers/orders_providers.dart';

class OrderPreviewAction extends ConsumerStatefulWidget {
  const OrderPreviewAction({
    required this.order,
    this.webStyle = false,
    this.refreshOnSummaryChange = true,
    this.showNextStatus = false,
    this.useTargetStatusColor = false,
    super.key,
  });
  final OrderSummary order;
  final bool webStyle;
  final bool showNextStatus;
  final bool useTargetStatusColor;
  // Detail already owns the canonical GET; list summaries still need hydration.
  final bool refreshOnSummaryChange;
  @override
  ConsumerState<OrderPreviewAction> createState() => _OrderPreviewActionState();
}

class _OrderPreviewActionState extends ConsumerState<OrderPreviewAction> {
  OrderDetail? _seen;
  bool _confirming = false;
  @override
  void didUpdateWidget(covariant OrderPreviewAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshOnSummaryChange &&
        (oldWidget.order.status != widget.order.status ||
            oldWidget.order.paymentStatus != widget.order.paymentStatus)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(orderDetailProvider(widget.order.id));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.order;
    final mutation = ref.watch(orderMutationProvider(summary.id));
    if (!summary.paymentStatus.isOperationallyPaid ||
        OrderStatusAction.forOrder(summary.status, summary.fulfillmentType) ==
            null) {
      return const SizedBox.shrink();
    }
    final detail = ref.watch(orderDetailProvider(summary.id));
    final notes = ref.watch(orderNotesProvider(summary.id));
    final location = ref.watch(currentLocationProvider).value;
    if (!detail.isLoading &&
        !detail.hasError &&
        detail.value != null &&
        !identical(_seen, detail.value)) {
      _seen = detail.value;
      final canonical = detail.value!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final current = ref.read(orderMutationProvider(summary.id));
          final latest = ref.read(orderDetailProvider(summary.id));
          // A retained loading value or a superseded frame is not a new GET.
          if (latest.isLoading ||
              latest.hasError ||
              !identical(latest.value, canonical) ||
              !identical(current, mutation)) {
            return;
          }
          // The board's reconciliation GET must not immediately erase a failed
          // action message when the canonical status/payment are unchanged.
          if (widget.showNextStatus &&
              current.phase == OrderMutationPhase.error &&
              current.canonicalOrder?.status == canonical.status &&
              current.canonicalOrder?.paymentStatus ==
                  canonical.paymentStatus) {
            return;
          }
          ref
              .read(orderMutationProvider(summary.id).notifier)
              .adoptRefreshedOrder(canonical);
        }
      });
    }
    final order = mutation.canonicalOrder ?? detail.value;
    if (detail.hasError) {
      return TextButton.icon(
        onPressed: () => ref.invalidate(orderDetailProvider(summary.id)),
        icon: const Icon(Icons.refresh),
        label: Text(tr(context, 'Refresh order status')),
      );
    }
    if (order == null) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    final action = order.paymentStatus.isOperationallyPaid
        ? OrderStatusAction.forOrder(order.status, order.fulfillmentType)
        : null;
    if (action == null || location?.id != order.locationId) {
      return const SizedBox.shrink();
    }
    return _OrderActions(
      showNextStatus: widget.showNextStatus,
      useTargetStatusColor: widget.useTargetStatusColor,
      webStyle: widget.webStyle,
      action: action,
      mutation: mutation,
      fulfillment: order.fulfillmentType,
      otherMutationBusy: notes.isBusy || detail.isLoading,
      confirming: _confirming,
      onPressed: () async {
        if (_confirming || mutation.isBusy || notes.isBusy) return;
        setState(() => _confirming = true);
        try {
          await _performAction(context, ref, order, action);
        } finally {
          if (mounted) setState(() => _confirming = false);
        }
      },
    );
  }

  Future<void> _performAction(
    BuildContext context,
    WidgetRef ref,
    OrderDetail order,
    OrderStatusAction action,
  ) async {
    final OrderMutationController controller = ref.read(
      orderMutationProvider(order.id).notifier,
    );
    if (action == OrderStatusAction.completeOrder) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => _CompletionDialog(order: order),
      );
      if (confirmed != true || !context.mounted) return;

      // Re-read immediately before the terminal PATCH. Completion stamps the
      // order and triggers customer-facing backend side effects.
      final OrderDetail latest =
          ref.read(orderDetailProvider(order.id)).value ??
          ref.read(orderMutationProvider(order.id)).canonicalOrder ??
          order;
      if (!OrderStatusAction.allows(
        latest.status,
        OrderStatus.delivered,
        fulfillment: latest.fulfillmentType,
      )) {
        controller.adoptChangedOrder(latest);
        return;
      }
      await controller.markOrderCompleted(latest);
      return;
    }

    await switch (action) {
      OrderStatusAction.acceptOrder => controller.acceptOrder(order),
      OrderStatusAction.startPreparing => controller.startPreparing(order),
      OrderStatusAction.markReady => controller.markReady(order),
      OrderStatusAction.completeOrder ||
      OrderStatusAction.cancelOrder => Future<void>.value(),
    };
  }
}

class _OrderActions extends StatelessWidget {
  const _OrderActions({
    required this.action,
    required this.mutation,
    required this.fulfillment,
    required this.otherMutationBusy,
    required this.onPressed,
    this.confirming = false,
    this.webStyle = false,
    this.showNextStatus = false,
    this.useTargetStatusColor = false,
  });

  final OrderStatusAction action;
  final OrderMutationState mutation;
  final FulfillmentType fulfillment;
  final bool otherMutationBusy;
  final VoidCallback onPressed;
  final bool confirming;
  final bool webStyle;
  final bool showNextStatus;
  final bool useTargetStatusColor;

  @override
  Widget build(BuildContext context) {
    final bool busy = mutation.isBusy || otherMutationBusy;
    final bool showButton =
        action != OrderStatusAction.completeOrder ||
        mutation.phase != OrderMutationPhase.error ||
        mutation.terminalRetryAllowed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (mutation.phase == OrderMutationPhase.error &&
            mutation.message != null) ...<Widget>[
          Text(
            mutation.message!,
            key: const Key('order-mutation-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 12),
        ],
        if (showButton)
          FilledButton(
            key: const Key('order-primary-action'),
            style: webStyle
                ? PelinesControlStyles.button(switch (action) {
                    OrderStatusAction.acceptOrder =>
                      PelinesButtonVariant.accept,
                    OrderStatusAction.startPreparing =>
                      (showNextStatus || useTargetStatusColor)
                          ? PelinesButtonVariant.preparing
                          : PelinesButtonVariant.accept,
                    OrderStatusAction.markReady =>
                      (showNextStatus || useTargetStatusColor)
                          ? PelinesButtonVariant.ready
                          : PelinesButtonVariant.preparing,
                    OrderStatusAction.completeOrder =>
                      PelinesButtonVariant.complete,
                    OrderStatusAction.cancelOrder =>
                      PelinesButtonVariant.cancel,
                  })
                : null,
            onPressed: busy || confirming ? null : onPressed,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: webStyle ? 0 : 12),
              child: PelinesButtonLabel(
                busy: busy,
                label: webStyle
                    ? tr(
                        context,
                        busy
                            ? (mutation.action ?? action).progressLabelFor(
                                fulfillment,
                              )
                            : showNextStatus &&
                                  action != OrderStatusAction.completeOrder
                            ? switch (action.target) {
                                OrderStatus.confirmed => 'Confirmed',
                                OrderStatus.preparing => 'Preparing',
                                OrderStatus.ready => 'Ready',
                                _ => action.labelFor(fulfillment),
                              }
                            : action.labelFor(fulfillment),
                      )
                    : busy
                    ? (mutation.action ?? action).progressLabelFor(fulfillment)
                    : action.labelFor(fulfillment),
              ),
            ),
          ),
      ],
    );
  }
}

class _CompletionDialog extends StatelessWidget {
  const _CompletionDialog({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    final bool pickup = order.fulfillmentType == FulfillmentType.pickup;
    final String action = pickup
        ? tr(context, 'Mark picked up')
        : tr(context, 'Mark delivered');
    return AlertDialog(
      title: Text(
        pickup
            ? tr(context, 'Confirm pickup?')
            : tr(context, 'Confirm delivery?'),
      ),
      content: Text(
        pickup
            ? tr(
                context,
                'Confirm that the customer has picked up this order? It will be marked complete and removed from active orders.',
              )
            : tr(
                context,
                'Confirm that this order has been delivered to the customer? It will be marked delivered and removed from active orders.',
              ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('completion-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr(context, 'Keep active')),
        ),
        FilledButton(
          key: const Key('completion-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    );
  }
}
