import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../orders/models/order_models.dart';
import '../data/print_job_store.dart';
import '../data/printer_settings_store.dart';
import '../models/print_job.dart';
import 'auto_print_policy.dart';
import '../models/printer.dart';
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
    this.account,
    this.now = DateTime.now,
  });
  final PrintJobStore store;
  final PrinterSettingsStore settings;
  final PrintQueue queue;
  final TicketBuilder builder;
  final String? Function()? account;
  final DateTime Function() now;

  Future<PrintJob> queueInitialPrint(OrderDetail order) =>
      _queueInitial(order, automatic: false);

  Future<PrintJob> queueAutomaticPrint(OrderDetail order) =>
      _queueInitial(order, automatic: true);

  Future<PrintJob> _queueInitial(
    OrderDetail order, {
    required bool automatic,
  }) async {
    final owner = account?.call();
    final config = await settings.read(order.locationId);
    if (!PrintEligibility.initial(order, config)) {
      throw const PrintRequestException(
        'Order is not eligible for initial printing.',
      );
    }
    if (automatic && !AutoPrintPolicy.detail(order, config, owner, now())) {
      throw const PrintRequestException(
        'Order is not due for automatic printing.',
      );
    }
    return _enqueue(
      builder.build(order),
      config,
      PrintPurpose.initial,
      owner: owner,
      automatic: automatic,
    );
  }

  Future<PrintJob> queueReprint(OrderDetail order) async {
    final owner = account?.call();
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
      owner: owner,
    );
  }

  Future<PrintJob> queueTestPrint(
    String locationId, {
    String? locationName,
  }) async {
    final owner = account?.call();
    final config = await settings.read(locationId);
    if (!config.enabled) {
      throw const PrintRequestException(
        'Enable printing for this location first.',
      );
    }
    final id = _id();
    return _enqueue(
      builder.buildTest(
        id: 'test-$id',
        placedAt: DateTime.now(),
        locationName: locationName,
        printerLabel: config.displayName,
        simulated: config.transport == PrinterTransport.fake,
      ),
      config,
      PrintPurpose.test,
      owner: owner,
    );
  }

  Future<PrintJob> _enqueue(
    TicketDocument ticket,
    PrinterSettings config,
    PrintPurpose purpose, {
    String? originalJobId,
    required String? owner,
    bool automatic = false,
  }) async {
    await queue.initialize();
    if ((account != null && (owner == null || owner != account!())) ||
        (kReleaseMode && config.transport == PrinterTransport.fake) ||
        !config.isValid ||
        config.printerId != queue.adapter.printer.id ||
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
        accountId: owner,
        automatic: automatic,
      ),
    );
    if (!automatic) queue.kick();
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
