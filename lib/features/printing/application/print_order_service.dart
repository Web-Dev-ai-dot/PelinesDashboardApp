import 'dart:math';

import '../../orders/models/order_models.dart';
import '../data/print_job_store.dart';
import '../data/printer_settings_store.dart';
import '../models/print_job.dart';
import '../models/printer_settings.dart';
import '../models/ticket_document.dart';
import 'print_eligibility.dart';
import 'print_queue.dart';
import 'ticket_builder.dart';

class PrintRequestException implements Exception {
  const PrintRequestException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PrintOrderService {
  PrintOrderService({
    required this.store,
    required this.settings,
    required this.queue,
    this.builder = const TicketBuilder(),
  });
  final PrintJobStore store;
  final PrinterSettingsStore settings;
  final PrintQueue queue;
  final TicketBuilder builder;

  Future<PrintJob> queueInitialPrint(OrderDetail order) async {
    final config = await settings.read(order.locationId);
    if (!PrintEligibility.initial(order, config)) {
      throw const PrintRequestException(
        'Order is not eligible for initial printing.',
      );
    }
    return _enqueue(builder.build(order), config, PrintPurpose.initial);
  }

  Future<PrintJob> queueReprint(OrderDetail order) async {
    final config = await settings.read(order.locationId);
    if (!PrintEligibility.reprint(order, config)) {
      throw const PrintRequestException(
        'Order is not eligible for reprinting.',
      );
    }
    final original = await store.findInitial(order.locationId, order.id);
    return _enqueue(
      builder.build(order),
      config,
      PrintPurpose.reprint,
      originalJobId: original?.id,
    );
  }

  Future<PrintJob> queueTestPrint(
    String locationId, {
    String? locationName,
  }) async {
    final config = await settings.read(locationId);
    if (!config.enabled) {
      throw const PrintRequestException(
        'Enable printing for this location first.',
      );
    }
    final id = _id();
    return _enqueue(
      TicketDocument(
        orderId: 'test-$id',
        orderNumber: 'TEST',
        orderType: OrderType.unknown,
        fulfillmentType: FulfillmentType.unknown,
        customerName: 'Printer test',
        phone: '',
        placedAt: DateTime.now().toUtc(),
        locationName: locationName,
        items: [],
        notes: 'Simulation only. No physical ticket.',
        payment: PaymentStatus.unknown,
        totals: const TicketTotals(
          subtotalCents: 0,
          serviceFeeCents: 0,
          tipCents: 0,
          deliveryFeeCents: 0,
          discountCents: 0,
          taxCents: 0,
          totalCents: 0,
        ),
      ),
      config,
      PrintPurpose.test,
    );
  }

  Future<PrintJob> _enqueue(
    TicketDocument ticket,
    PrinterSettings config,
    PrintPurpose purpose, {
    String? originalJobId,
  }) async {
    await queue.initialize();
    if (config.printerId != queue.adapter.printer.id ||
        config.transport != queue.adapter.printer.transport) {
      throw const PrintRequestException('Selected printer is not available.');
    }
    final now = DateTime.now().toUtc();
    final job = await store.insert(
      PrintJob(
        id: _id(),
        orderId: ticket.orderId,
        locationId: config.locationId,
        purpose: purpose,
        status: PrintJobStatus.queued,
        createdAt: now,
        updatedAt: now,
        printerId: config.printerId,
        ticket: ticket,
        originalJobId: originalJobId,
      ),
    );
    queue.kick();
    return job;
  }

  static String _id() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
