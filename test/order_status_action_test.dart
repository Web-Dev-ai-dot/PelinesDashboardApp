import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/models/order_status_action.dart';

void main() {
  test('allows only the three Slice A forward transitions', () {
    expect(
      OrderStatusAction.allows(OrderStatus.pending, OrderStatus.confirmed),
      isTrue,
    );
    expect(
      OrderStatusAction.allows(OrderStatus.confirmed, OrderStatus.preparing),
      isTrue,
    );
    expect(
      OrderStatusAction.allows(OrderStatus.preparing, OrderStatus.ready),
      isTrue,
    );
  });

  test('blocks skips, backwards, terminal, unknown and same-state changes', () {
    const List<(OrderStatus, OrderStatus)> blocked =
        <(OrderStatus, OrderStatus)>[
          (OrderStatus.pending, OrderStatus.ready),
          (OrderStatus.confirmed, OrderStatus.pending),
          (OrderStatus.ready, OrderStatus.preparing),
          (OrderStatus.delivered, OrderStatus.pending),
          (OrderStatus.cancelled, OrderStatus.confirmed),
          (OrderStatus.unknown, OrderStatus.confirmed),
          (OrderStatus.pending, OrderStatus.pending),
          (OrderStatus.confirmed, OrderStatus.confirmed),
          (OrderStatus.preparing, OrderStatus.preparing),
          (OrderStatus.ready, OrderStatus.ready),
        ];
    for (final (OrderStatus source, OrderStatus target) in blocked) {
      expect(
        OrderStatusAction.allows(source, target),
        isFalse,
        reason: '${source.name} -> ${target.name}',
      );
    }
    expect(OrderStatusAction.forStatus(OrderStatus.ready), isNull);
    expect(OrderStatusAction.forStatus(OrderStatus.delivered), isNull);
    expect(OrderStatusAction.forStatus(OrderStatus.cancelled), isNull);
  });
}
