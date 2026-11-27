import '../../orders/models/order_models.dart';
import '../models/ticket_document.dart';

class TicketBuilder {
  const TicketBuilder();

  TicketDocument buildTest({
    required String id,
    required DateTime placedAt,
    String? locationName,
    required String printerLabel,
    required bool simulated,
  }) => TicketDocument(
    orderId: id,
    orderNumber: 'TEST',
    orderType: OrderType.online,
    fulfillmentType: FulfillmentType.pickup,
    customerName: 'Lucía del Río',
    phone: '503-555-0147',
    placedAt: placedAt.toUtc(),
    locationName: locationName,
    isTest: true,
    notes:
        'Fictional sample. Verify alignment and cut.\nPrinter: $printerLabel'
        '${simulated ? '\nSimulation only. No physical ticket.' : ''}',
    // Exercise the paid layout with a simulated payment in Test Print.
    payment: PaymentStatus.paid,
    discountCode: 'SAMPLE',
    items: [
      TicketItem(
        quantity: 2,
        name: 'Tacos de champiñón',
        baseUnitPriceCents: 500,
        lineTotalCents: 1120,
        instructions: 'Sin cebolla, por favor.',
        modifiers: const [
          TicketModifier(
            groupName: 'Extras',
            optionName: 'Piña',
            priceAdjustmentCents: 60,
          ),
        ],
      ),
      TicketItem(
        quantity: 1,
        name: 'Agua de limón',
        baseUnitPriceCents: 300,
        lineTotalCents: 300,
        modifiers: const [],
      ),
    ],
    totals: const TicketTotals(
      subtotalCents: 1420,
      serviceFeeCents: 50,
      tipCents: 150,
      deliveryFeeCents: 0,
      discountCents: 200,
      taxCents: 0,
      totalCents: 1420,
      amountPaidCents: 1420,
    ),
  );
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
