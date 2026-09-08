import '../../orders/models/order_models.dart';
import '../models/ticket_document.dart';

class TicketBuilder {
  const TicketBuilder();
  TicketDocument build(OrderDetail order) => TicketDocument(
    orderId: order.id,
    orderNumber: order.orderNumber,
    orderType: order.orderType,
    locationName: order.location?['name'] as String?,
    fulfillmentType: order.fulfillmentType,
    customerName: order.contactName,
    phone: order.contactPhone,
    placedAt: order.createdAt.toUtc(),
    scheduledFor: order.scheduledFor?.toUtc(),
    notes: order.notes,
    payment: order.paymentStatus,
    discountCode: order.discountCode,
    cardBrand: order.cardBrand,
    cardLast4: order.cardLast4,
    deliveryAddress: order.deliveryAddress,
    eventDetails: order.eventDetails,
    items: order.items
        .map(
          (i) => TicketItem(
            quantity: i.quantity,
            name: i.productName,
            baseUnitPriceCents:
                i.unitPriceCents -
                i.modifiers.fold<int>(0, (sum, m) => sum + m.priceDeltaCents),
            lineTotalCents: i.lineTotalCents,
            instructions: i.notes,
            modifiers: i.modifiers
                .map(
                  (m) => TicketModifier(
                    groupName: m.groupName,
                    optionName: m.optionName,
                    priceAdjustmentCents: m.priceDeltaCents,
                  ),
                )
                .toList(),
          ),
        )
        .toList(),
    totals: TicketTotals(
      subtotalCents: order.subtotalCents,
      serviceFeeCents: order.serviceFeeCents,
      tipCents: order.tipCents,
      deliveryFeeCents: order.deliveryFeeCents,
      discountCents: order.discountCents,
      taxCents: order.taxCents,
      totalCents: order.totalCents,
      amountPaidCents: order.paymentStatus == PaymentStatus.paid
          ? order.totalCents
          : null,
    ),
  );
}
