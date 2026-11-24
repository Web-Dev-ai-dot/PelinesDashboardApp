import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/printing/application/print_eligibility.dart';
import 'package:pelines_admin_app/features/printing/application/print_order_service.dart';
import 'package:pelines_admin_app/features/printing/application/print_queue.dart';
import 'package:pelines_admin_app/features/printing/application/ticket_builder.dart';
import 'package:pelines_admin_app/features/printing/data/fake_printer_adapter.dart';
import 'package:pelines_admin_app/features/printing/data/print_job_store.dart';
import 'package:pelines_admin_app/features/printing/data/printer_settings_store.dart';
import 'package:pelines_admin_app/features/printing/data/printing_database.dart';
import 'package:pelines_admin_app/features/printing/models/print_job.dart';
import 'package:pelines_admin_app/features/printing/models/print_result.dart';
import 'package:pelines_admin_app/features/printing/models/printer.dart';
import 'package:pelines_admin_app/features/printing/models/printer_settings.dart';
import 'package:pelines_admin_app/features/printing/models/ticket_document.dart';

import 'order_test_data.dart';

void main() {
  sqfliteFfiInit();
  const builder = TicketBuilder();
  const config = PrinterSettings(
    locationId: 'location-id',
    enabled: true,
    autoPrintRegularAsap: true,
  );

  group('TicketBuilder', () {
    for (final fulfillment in ['pickup', 'delivery']) {
      test(
        'Regular ASAP $fulfillment preserves canonical content and cents',
        () {
          final json = orderJson(status: 'confirmed', fulfillment: fulfillment)
            ..addAll({
              'location': {'name': 'Troutdale'},
              'notes': 'Utensils\nNo onions',
              'subtotalCents': 2400,
              'taxCents': 100,
              'serviceFeeCents': 50,
              'tipCents': 200,
              'deliveryFeeCents': 300,
              'discountCents': 150,
              'totalCents': 2900,
              'items': [
                {
                  'id': 'item',
                  'productName': 'Tacos',
                  'quantity': 2,
                  'unitPriceCents': 1200,
                  'lineTotalCents': 2400,
                  'notes': 'Sin sal',
                  'modifiers': [
                    {
                      'id': 'mod',
                      'groupName': 'Extras',
                      'optionName': 'Guacamole',
                      'priceDeltaCents': 200,
                    },
                  ],
                },
              ],
            });
          final ticket = builder.build(OrderDetail.fromJson(json));
          expect(ticket.isAsap, isTrue);
          expect(ticket.orderId, json['id']);
          expect(ticket.orderType, OrderType.online);
          expect(ticket.fulfillmentType.name, fulfillment);
          expect(ticket.locationName, 'Troutdale');
          expect(ticket.customerName, 'Customer');
          expect(ticket.phone, '555-0100');
          expect(ticket.items.single.quantity, 2);
          expect(ticket.items.single.baseUnitPriceCents, 1000);
          expect(ticket.items.single.lineTotalCents, 2400);
          expect(ticket.items.single.instructions, 'Sin sal');
          expect(ticket.items.single.modifiers.single.toJson(), {
            'groupName': 'Extras',
            'optionName': 'Guacamole',
            'priceAdjustmentCents': 200,
          });
          expect(ticket.notes, 'Utensils\nNo onions');
          expect(ticket.totals.toJson(), {
            'subtotalCents': 2400,
            'serviceFeeCents': 50,
            'tipCents': 200,
            'deliveryFeeCents': 300,
            'discountCents': 150,
            'taxCents': 100,
            'totalCents': 2900,
            'amountPaidCents': 2900,
          });
          expect(
            TicketDocument.fromJson(
              jsonDecode(jsonEncode(ticket.toJson())) as Map<String, dynamic>,
            ).toJson(),
            ticket.toJson(),
          );
        },
      );
    }
    test('Scheduled Catering retains time, event and delivery snapshot', () {
      final json = orderJson()
        ..addAll({
          'orderType': 'catering',
          'scheduledFor': '2026-11-01T09:30:00Z',
          'eventDetails': {
            'eventName': 'Party',
            'attendees': 20,
            'extra': ['a'],
          },
          'deliveryAddress': {'line1': 'Main Street'},
        });
      final ticket = builder.build(OrderDetail.fromJson(json));
      expect(ticket.orderType, OrderType.catering);
      expect(ticket.isAsap, isFalse);
      expect(ticket.scheduledFor, DateTime.utc(2026, 11, 1, 9, 30));
      expect(ticket.eventDetails?['eventName'], 'Party');
      expect(ticket.deliveryAddress?['line1'], 'Main Street');
      (json['eventDetails'] as Map)['eventName'] = 'Changed';
      expect(ticket.eventDetails?['eventName'], 'Party');
      expect(
        () => (ticket.eventDetails?['extra'] as List).add('b'),
        throwsUnsupportedError,
      );
      expect(ticket.locationName, isNull);
    });
    for (final payment in PaymentStatus.values) {
      test('preserves $payment without inventing amount paid', () {
        final ticket = builder.build(orderDetail(payment: payment));
        expect(ticket.payment, payment);
        expect(
          ticket.totals.amountPaidCents,
          payment == PaymentStatus.paid ? 1100 : null,
        );
      });
    }
  });
  group('Eligibility', () {
    for (final payment in PaymentStatus.values) {
      test('$payment manual eligibility requires a settled payment', () {
        final order = orderDetail(
          status: OrderStatus.confirmed,
          payment: payment,
        );
        expect(
          PrintEligibility.initial(order, config),
          payment == PaymentStatus.paid || payment == PaymentStatus.refunded,
        );
        // Automatic printing never fires for a refunded order.
        expect(
          PrintEligibility.regularAsap(
            order,
            config.copyWith(autoPrintRegularAsap: true),
          ),
          payment == PaymentStatus.paid,
        );
      });
    }
    test('location, enabled, known type and status required', () {
      expect(
        PrintEligibility.initial(
          orderDetail(status: OrderStatus.confirmed, locationId: 'elsewhere'),
          config,
        ),
        isFalse,
      );
      expect(
        PrintEligibility.initial(
          orderDetail(status: OrderStatus.confirmed),
          config.copyWith(enabled: false),
        ),
        isFalse,
      );
      for (final status in [
        OrderStatus.pending,
        OrderStatus.cancelled,
        OrderStatus.delivered,
        OrderStatus.unknown,
      ]) {
        expect(
          PrintEligibility.initial(orderDetail(status: status), config),
          isFalse,
        );
      }
      expect(
        PrintEligibility.initial(
          OrderDetail.fromJson(
            orderJson(status: 'confirmed')..['orderType'] = 'invalid',
          ),
          config,
        ),
        isFalse,
      );
    });
    test('ASAP contract requires confirmed Regular and toggle', () {
      expect(
        PrintEligibility.regularAsap(
          orderDetail(status: OrderStatus.confirmed),
          config,
        ),
        isTrue,
      );
      expect(
        PrintEligibility.regularAsap(
          orderDetail(status: OrderStatus.preparing),
          config,
        ),
        isFalse,
      );
      expect(
        PrintEligibility.regularAsap(
          orderDetail(status: OrderStatus.confirmed),
          config.copyWith(autoPrintRegularAsap: false),
        ),
        isFalse,
      );
      for (final patch in [
        {'orderType': 'catering'},
        {'scheduledFor': '2026-10-01T12:00:00Z'},
      ]) {
        expect(
          PrintEligibility.regularAsap(
            OrderDetail.fromJson(orderJson(status: 'confirmed')..addAll(patch)),
            config,
          ),
          isFalse,
        );
      }
    });
  });

  group('SQLite queue and service', () {
    late Directory directory;
    late Database db;
    late PrintJobStore store;
    late PrinterSettingsStore settings;
    late FakePrinterAdapter adapter;
    late PrintQueue queue;
    late PrintOrderService service;
    late String path;
    Future<void> open() async {
      db = await openPrintingDatabase(factory: databaseFactoryFfi, path: path);
      store = PrintJobStore(db);
      settings = PrinterSettingsStore(db);
      adapter = FakePrinterAdapter(delay: Duration.zero);
      queue = PrintQueue(
        store: store,
        adapter: adapter,
        canSend: (job) async =>
            (await settings.read(job.locationId)).enabled &&
            await adapter.getStatus() == PrinterStatus.connected,
      );
      service = PrintOrderService(
        store: store,
        settings: settings,
        queue: queue,
      );
    }

    Future<void> close() async {
      await queue.dispose();
      await store.dispose();
      await db.close();
    }

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('pelines-print-test-');
      path = '${directory.path}/printing.db';
      await open();
      await settings.save(config);
      await queue.initialize();
    });
    tearDown(() async {
      await close();
      await directory.delete(recursive: true);
    });

    test(
      'concurrent initial dedupe, explicit reprint and location scope',
      () async {
        final order = orderDetail(status: OrderStatus.confirmed);
        final jobs = await Future.wait(
          List.generate(10, (_) => service.queueInitialPrint(order)),
        );
        expect(jobs.map((j) => j.id).toSet(), hasLength(1));
        final reprint = await service.queueReprint(order);
        expect(reprint.id, isNot(jobs.first.id));
        expect(reprint.originalJobId, jobs.first.id);
        await settings.save(
          const PrinterSettings(locationId: 'other', enabled: true),
        );
        final other = await service.queueInitialPrint(
          orderDetail(status: OrderStatus.confirmed, locationId: 'other'),
        );
        expect(other.id, isNot(jobs.first.id));
        expect(await store.list(), hasLength(3));
      },
    );
    test('rejected request creates no job', () async {
      await expectLater(
        service.queueInitialPrint(orderDetail()),
        throwsA(isA<PrintRequestException>()),
      );
      expect(await store.list(), isEmpty);
    });
    test('queued is committed before sending, jobs serialize', () async {
      final jobs = await Future.wait(
        List.generate(5, (_) => service.queueTestPrint('location-id')),
      );
      await queue.idle;
      expect(
        (await store.list()).every((j) => j.status == PrintJobStatus.queued),
        isTrue,
      );
      adapter.delay = const Duration(milliseconds: 5);
      await adapter.connect();
      queue.kick();
      await queue.idle;
      expect(adapter.maxActiveCalls, 1);
      expect(adapter.printCalls, 5);
      for (final job in jobs) {
        final saved = (await store.get(job.id))!;
        expect(saved.status, PrintJobStatus.submitted);
        expect(saved.attemptCount, 1);
      }
    });
    for (final outcome in PrintOutcome.values) {
      test('persists $outcome and never automatically retries it', () async {
        adapter.outcome = outcome;
        await adapter.connect();
        final job = await service.queueTestPrint('location-id');
        await queue.idle;
        expect((await store.get(job.id))!.status.name, outcome.name);
        queue.kick();
        await queue.idle;
        expect(adapter.printCalls, 1);
        if (outcome == PrintOutcome.failedBeforeSend) {
          adapter.outcome = PrintOutcome.confirmed;
          await queue.retry(job.id);
          await queue.idle;
          expect((await store.get(job.id))!.status, PrintJobStatus.confirmed);
          expect((await store.get(job.id))!.attemptCount, 2);
        } else {
          await expectLater(queue.retry(job.id), throwsStateError);
        }
      });
    }
    test(
      'restart restores queued; sending becomes unknown and stays unsent',
      () async {
        final pending = await service.queueTestPrint('location-id');
        final interrupted = await service.queueTestPrint('location-id');
        await queue.idle;
        await store.update(
          interrupted.transition(PrintJobStatus.sending, attempt: true),
          expected: PrintJobStatus.queued,
        );
        await close();
        await open();
        await queue.initialize();
        expect(
          (await store.get(interrupted.id))!.status,
          PrintJobStatus.unknown,
        );
        await adapter.connect();
        queue.kick();
        await queue.idle;
        expect((await store.get(pending.id))!.status, PrintJobStatus.submitted);
        expect(adapter.printCalls, 1);
        await queue.initialize();
        queue.kick();
        await queue.idle;
        expect(adapter.printCalls, 1);
        await queue.cancel(interrupted.id);
        expect(
          (await store.get(interrupted.id))!.status,
          PrintJobStatus.cancelled,
        );
      },
    );
    test(
      'settings persist per device/location with one enabled location',
      () async {
        expect((await settings.read('new')).scheduledLeadMinutes, 20);
        await settings.save(
          config.copyWith(autoPrintScheduled: true, scheduledLeadMinutes: 35),
        );
        await settings.save(
          const PrinterSettings(locationId: 'other', enabled: true),
        );
        await close();
        await open();
        final restored = await settings.read('location-id');
        expect(restored.enabled, isFalse);
        expect(restored.autoPrintScheduled, isTrue);
        expect(restored.scheduledLeadMinutes, 35);
        expect((await settings.read('other')).enabled, isTrue);
        final secondDevice = await openPrintingDatabase(
          factory: databaseFactoryFfi,
          path: '${directory.path}/second.db',
        );
        expect(
          (await PrinterSettingsStore(secondDevice).read('other')).enabled,
          isFalse,
        );
        await secondDevice.close();
      },
    );
    for (final failAt in [PrintJobStatus.queued, PrintJobStatus.sending]) {
      test(
        'storage failure at $failAt does not cause duplicate delivery',
        () async {
          final job = await service.queueTestPrint('location-id');
          await queue.idle;
          await queue.dispose();
          final failing = _FailingStore(db, failAt);
          queue = PrintQueue(
            store: failing,
            adapter: adapter,
            canSend: (_) async => true,
          );
          await adapter.connect();
          queue.kick();
          await queue.idle;
          expect(queue.lastError, isNotNull);
          expect(adapter.printCalls, failAt == PrintJobStatus.queued ? 0 : 1);
          expect(
            (await store.get(job.id))!.status,
            failAt == PrintJobStatus.queued
                ? PrintJobStatus.queued
                : PrintJobStatus.sending,
          );
          queue.kick();
          await queue.idle;
          expect(adapter.printCalls, failAt == PrintJobStatus.queued ? 0 : 1);
          await failing.dispose();
        },
      );
    }
    test(
      'database unique index rejects bypassing initial insertion policy',
      () async {
        final job = await service.queueInitialPrint(
          orderDetail(status: OrderStatus.confirmed),
        );
        await queue.idle;
        final row = Map<String, Object?>.from((await db.query('jobs')).single)
          ..['id'] = 'another-id';
        await expectLater(
          db.insert('jobs', row),
          throwsA(isA<DatabaseException>()),
        );
        expect(
          (await store.findInitial(job.locationId, job.orderId))!.id,
          job.id,
        );
      },
    );
    test('transaction rollback prevents partial persistence', () async {
      await expectLater(
        db.transaction((tx) async {
          await tx.insert('settings', {
            'location_id': 'rollback',
            'document': jsonEncode(config.toJson()),
          });
          throw StateError('disk transaction aborted');
        }),
        throwsStateError,
      );
      expect(
        await db.query(
          'settings',
          where: 'location_id = ?',
          whereArgs: ['rollback'],
        ),
        isEmpty,
      );
    });
  });
  group('Fake adapter', () {
    test(
      'connection success, failure, disconnect and delayed connecting state',
      () async {
        final adapter = FakePrinterAdapter(
          delay: const Duration(milliseconds: 5),
        );
        final connect = adapter.connect();
        expect(adapter.printer.status, PrinterStatus.connecting);
        expect((await connect).status, PrinterStatus.connected);
        expect((await adapter.disconnect()).status, PrinterStatus.disconnected);
        adapter.connectionFails = true;
        expect((await adapter.connect()).status, PrinterStatus.error);
      },
    );
    test('disconnected fake fails before send', () async {
      final adapter = FakePrinterAdapter(delay: Duration.zero);
      final now = DateTime.now().toUtc();
      final job = PrintJob(
        id: 'job',
        orderId: 'order',
        locationId: 'location-id',
        purpose: PrintPurpose.test,
        status: PrintJobStatus.sending,
        createdAt: now,
        updatedAt: now,
        printerId: 'fake',
        ticket: builder.build(orderDetail()),
      );
      expect((await adapter.print(job)).outcome, PrintOutcome.failedBeforeSend);
      expect(adapter.printCalls, 0);
    });
  });
}

class _FailingStore extends PrintJobStore {
  _FailingStore(super.database, this.failAt);
  final PrintJobStatus failAt;
  @override
  Future<bool> update(PrintJob job, {required PrintJobStatus expected}) async {
    if (expected == failAt) throw StateError('Simulated storage failure');
    return super.update(job, expected: expected);
  }
}
