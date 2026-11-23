import '../../orders/models/order_models.dart';
import '../models/printer_settings.dart';
import 'print_eligibility.dart';

abstract final class AutoPrintPolicy {
  static const lead = Duration(minutes: 30);

  static bool summary(
    OrderSummary order,
    PrinterSettings config,
    String? account,
    DateTime now,
  ) =>
      order.locationId == config.locationId &&
      order.paymentStatus == PaymentStatus.paid &&
      PrintEligibility.activeStatus(order.status) &&
      order.fulfillmentType != FulfillmentType.unknown &&
      _due(
        order.orderType,
        order.createdAt,
        order.scheduledFor,
        config,
        account,
        now,
      );

  static bool detail(
    OrderDetail order,
    PrinterSettings config,
    String? account,
    DateTime now,
  ) =>
      PrintEligibility.initial(order, config) &&
      _due(
        order.orderType,
        order.createdAt,
        order.scheduledFor,
        config,
        account,
        now,
      );

  static bool _due(
    OrderType type,
    DateTime created,
    DateTime? scheduled,
    PrinterSettings config,
    String? account,
    DateTime now,
  ) {
    if (!config.enabled ||
        account == null ||
        account != config.autoPrintAccount) {
      return false;
    }
    final since = switch (type) {
      OrderType.online when scheduled != null =>
        config.autoPrintScheduled ? config.scheduledSince : null,
      OrderType.online => config.autoPrintRegularAsap ? config.asapSince : null,
      OrderType.catering =>
        config.autoPrintCatering ? config.cateringSince : null,
      OrderType.unknown => null,
    };
    if (since == null) return false;
    if (type != OrderType.online || scheduled == null) {
      return !created.isBefore(since);
    }
    return scheduled.isAfter(since) && !now.isBefore(scheduled.subtract(lead));
  }
}
