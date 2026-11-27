import '../../orders/models/order_models.dart';
import '../models/printer_settings.dart';

abstract final class PrintEligibility {
  /// Staff-initiated print: a refunded order that is still active is settled
  /// and may be printed by hand.
  static bool initial(OrderDetail order, PrinterSettings settings) =>
      settings.enabled &&
      settings.locationId == order.locationId &&
      order.paymentStatus.isOperationallyPaid &&
      activeStatus(order.status) &&
      order.orderType != OrderType.unknown &&
      order.fulfillmentType != FulfillmentType.unknown;

  static bool activeStatus(OrderStatus status) =>
      status == OrderStatus.confirmed ||
      status == OrderStatus.preparing ||
      status == OrderStatus.ready;

  static bool regularAsap(OrderDetail order, PrinterSettings settings) =>
      initial(order, settings) &&
      // Automatic printing requires a strictly paid order, never refunded.
      order.paymentStatus.isPaid &&
      settings.autoPrintRegularAsap &&
      order.orderType == OrderType.online &&
      order.scheduledFor == null &&
      order.status == OrderStatus.confirmed;

  static bool reprint(OrderDetail order, PrinterSettings settings) =>
      initial(order, settings) ||
      (settings.enabled &&
          settings.locationId == order.locationId &&
          order.paymentStatus.isOperationallyPaid &&
          order.status == OrderStatus.delivered &&
          order.orderType != OrderType.unknown &&
          order.fulfillmentType != FulfillmentType.unknown);
}
