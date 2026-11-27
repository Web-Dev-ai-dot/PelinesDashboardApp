import '../../orders/models/order_models.dart';
import '../models/printer_settings.dart';
import 'print_eligibility.dart';

enum AutoPrintType {
  asap,
  scheduled,
  catering;

  bool requested(PrinterSettings config) => switch (this) {
    asap => config.autoPrintRegularAsap,
    scheduled => config.autoPrintScheduled,
    catering => config.autoPrintCatering,
  };

  DateTime? activation(PrinterSettings config, String? account) {
    if (account == null ||
        account != config.autoPrintAccount ||
        !requested(config)) {
      return null;
    }
    return switch (this) {
      asap => config.asapSince,
      scheduled => config.scheduledSince,
      catering => config.cateringSince,
    };
  }
}

enum AutoPrintDecision {
  eligible,
  printingDisabled,
  typeDisabled,
  activationPending,
  beforeActivation,
  unpaid,
  statusIneligible,
  outsideWindow,
  unsupported,
  initialJobExists,
  detailUnavailable,
  queued,
}

abstract final class AutoPrintPolicy {
  static const lead = Duration(minutes: 30);

  static bool summary(
    OrderSummary order,
    PrinterSettings config,
    String? account,
    DateTime now,
  ) =>
      summaryDecision(order, config, account, now) ==
      AutoPrintDecision.eligible;

  static bool detail(
    OrderDetail order,
    PrinterSettings config,
    String? account,
    DateTime now,
  ) =>
      detailDecision(order, config, account, now) == AutoPrintDecision.eligible;

  static AutoPrintDecision summaryDecision(
    OrderSummary order,
    PrinterSettings config,
    String? account,
    DateTime now,
  ) => _decision(
    location: order.locationId,
    type: order.orderType,
    fulfillment: order.fulfillmentType,
    status: order.status,
    payment: order.paymentStatus,
    created: order.createdAt,
    scheduled: order.scheduledFor,
    config: config,
    account: account,
    now: now,
  );

  static AutoPrintDecision detailDecision(
    OrderDetail order,
    PrinterSettings config,
    String? account,
    DateTime now,
  ) => _decision(
    location: order.locationId,
    type: order.orderType,
    fulfillment: order.fulfillmentType,
    status: order.status,
    payment: order.paymentStatus,
    created: order.createdAt,
    scheduled: order.scheduledFor,
    config: config,
    account: account,
    now: now,
  );

  static AutoPrintDecision _decision({
    required String location,
    required OrderType type,
    required FulfillmentType fulfillment,
    required OrderStatus status,
    required PaymentStatus payment,
    required DateTime created,
    required DateTime? scheduled,
    required PrinterSettings config,
    required String? account,
    required DateTime now,
  }) {
    if (!config.enabled) return AutoPrintDecision.printingDisabled;
    if (location != config.locationId ||
        fulfillment == FulfillmentType.unknown) {
      return AutoPrintDecision.unsupported;
    }
    final category = switch (type) {
      OrderType.online =>
        scheduled == null ? AutoPrintType.asap : AutoPrintType.scheduled,
      OrderType.catering => AutoPrintType.catering,
      OrderType.unknown => null,
    };
    if (category == null) return AutoPrintDecision.unsupported;
    if (!category.requested(config)) return AutoPrintDecision.typeDisabled;
    final since = category.activation(config, account);
    if (since == null) return AutoPrintDecision.activationPending;
    if (payment != PaymentStatus.paid) return AutoPrintDecision.unpaid;
    if (!PrintEligibility.activeStatus(status)) {
      return AutoPrintDecision.statusIneligible;
    }

    if (category != AutoPrintType.scheduled || scheduled == null) {
      return created.isBefore(since)
          ? AutoPrintDecision.beforeActivation
          : AutoPrintDecision.eligible;
    }
    if (!scheduled.isAfter(since)) return AutoPrintDecision.beforeActivation;
    return now.isBefore(scheduled.subtract(lead))
        ? AutoPrintDecision.outsideWindow
        : AutoPrintDecision.eligible;
  }
}
