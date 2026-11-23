import '../../orders/models/order_models.dart';
import '../models/printer_settings.dart';

abstract final class PrintEligibility {
  static bool initial(OrderDetail order, PrinterSettings settings) =>
      settings.enabled &&
      settings.locationId == order.locationId &&
      order.paymentStatus == PaymentStatus.paid &&
      activeStatus(order.status) &&
      order.orderType != OrderType.unknown &&
      order.fulfillmentType != FulfillmentType.unknown;

  static bool activeStatus(OrderStatus status) =>
      status == OrderStatus.confirmed ||
      status == OrderStatus.preparing ||
      status == OrderStatus.ready;

  static bool regularAsap(OrderDetail order, PrinterSettings settings) =>
      initial(order, settings) &&
      settings.autoPrintRegularAsap &&
      order.orderType == OrderType.online &&
      order.scheduledFor == null &&
      order.status == OrderStatus.confirmed;

  static bool reprint(OrderDetail order, PrinterSettings settings) =>
      initial(order, settings) ||
      (settings.enabled &&
          settings.locationId == order.locationId &&
          order.paymentStatus == PaymentStatus.paid &&
          order.status == OrderStatus.delivered &&
          order.orderType != OrderType.unknown &&
          order.fulfillmentType != FulfillmentType.unknown);
}
