import 'order_models.dart';

enum OrderStatusAction {
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
  );

  const OrderStatusAction({
    required this.source,
    required this.target,
    required this.label,
    required this.progressLabel,
    required this.successMessage,
  });

  final OrderStatus source;
  final OrderStatus target;
  final String label;
  final String progressLabel;
  final String successMessage;

  static OrderStatusAction? forStatus(OrderStatus status) => switch (status) {
    OrderStatus.pending => acceptOrder,
    OrderStatus.confirmed => startPreparing,
    OrderStatus.preparing => markReady,
    OrderStatus.ready ||
    OrderStatus.delivered ||
    OrderStatus.cancelled ||
    OrderStatus.unknown => null,
  };

  static bool allows(OrderStatus source, OrderStatus target) =>
      forStatus(source)?.target == target;
}
