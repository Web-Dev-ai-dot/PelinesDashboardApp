import 'order_models.dart';

enum OrderStatusAction {
  cancelOrder(
    source: null,
    target: OrderStatus.cancelled,
    label: 'Cancel Order',
    progressLabel: 'Cancelling...',
    successMessage: 'Order cancelled',
  ),
  acceptOrder(
    source: OrderStatus.pending,
    target: OrderStatus.confirmed,
    label: 'Accept order',
    progressLabel: 'Accepting...',
    successMessage: 'Order accepted',
  ),
  startPreparing(
    source: OrderStatus.confirmed,
    target: OrderStatus.preparing,
    label: 'Start preparing',
    progressLabel: 'Starting...',
    successMessage: 'Order moved to preparing',
  ),
  markReady(
    source: OrderStatus.preparing,
    target: OrderStatus.ready,
    label: 'Mark ready',
    progressLabel: 'Marking ready...',
    successMessage: 'Order marked ready',
  ),
  completeOrder(
    source: OrderStatus.ready,
    target: OrderStatus.delivered,
    label: 'Mark delivered',
    progressLabel: 'Marking delivered...',
    successMessage: 'Order marked delivered',
  );

  const OrderStatusAction({
    required this.source,
    required this.target,
    required this.label,
    required this.progressLabel,
    required this.successMessage,
  });

  final OrderStatus? source;
  final OrderStatus target;
  final String label;
  final String progressLabel;
  final String successMessage;

  // Cancellation is deliberately not part of forStatus/forOrder progression.
  static bool canCancel(OrderDetail order) =>
      order.paymentStatus.isOperationallyPaid &&
      const <OrderStatus>{
        OrderStatus.pending,
        OrderStatus.confirmed,
        OrderStatus.preparing,
        OrderStatus.ready,
      }.contains(order.status);

  static OrderStatusAction? forStatus(OrderStatus status) => switch (status) {
    OrderStatus.pending => acceptOrder,
    OrderStatus.confirmed => startPreparing,
    OrderStatus.preparing => markReady,
    OrderStatus.ready ||
    OrderStatus.delivered ||
    OrderStatus.cancelled ||
    OrderStatus.unknown => null,
  };

  static OrderStatusAction? forOrder(
    OrderStatus status,
    FulfillmentType fulfillment,
  ) {
    if (status == OrderStatus.ready) {
      return fulfillment == FulfillmentType.pickup ||
              fulfillment == FulfillmentType.delivery
          ? completeOrder
          : null;
    }
    return forStatus(status);
  }

  static bool allows(
    OrderStatus source,
    OrderStatus target, {
    FulfillmentType? fulfillment,
  }) =>
      (source == OrderStatus.ready
              ? forOrder(source, fulfillment ?? FulfillmentType.unknown)
              : forStatus(source))
          ?.target ==
      target;

  String labelFor(FulfillmentType fulfillment) =>
      this == completeOrder && fulfillment == FulfillmentType.pickup
      ? 'Mark picked up'
      : label;

  String progressLabelFor(FulfillmentType fulfillment) =>
      this == completeOrder && fulfillment == FulfillmentType.pickup
      ? 'Marking picked up...'
      : progressLabel;

  String successMessageFor(FulfillmentType fulfillment) =>
      this == completeOrder && fulfillment == FulfillmentType.pickup
      ? 'Order marked picked up'
      : successMessage;
}
