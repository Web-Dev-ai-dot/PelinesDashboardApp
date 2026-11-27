import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/core/time/pelines_time.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/printing/application/auto_print_policy.dart';
import 'package:pelines_admin_app/features/printing/application/esc_pos_ticket_renderer.dart';
import 'package:pelines_admin_app/features/printing/data/fake_printer_adapter.dart';
import 'package:pelines_admin_app/features/printing/data/printing_database.dart';
import 'package:pelines_admin_app/features/printing/models/print_job.dart';
import 'package:pelines_admin_app/features/printing/models/print_result.dart';
import 'package:pelines_admin_app/features/printing/models/printer.dart';
import 'package:pelines_admin_app/features/printing/models/printer_settings.dart';
import 'package:pelines_admin_app/features/printing/providers/printing_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'order_test_data.dart';

const location = 'location-id';
const owner = 'account-a';
final activation = DateTime.utc(2026, 9, 4, 17);

Map<String, dynamic> record({
  String id = 'order',
  String status = 'confirmed',
  String payment = 'paid',
  String type = 'online',
  DateTime? scheduled,
  DateTime? placed,
}) => orderJson(id: id, status: status, payment: payment)
  ..addAll({
    'createdAt': (placed ?? DateTime.utc(2026, 9, 4, 18)).toIso8601String(),
    'scheduledFor': scheduled?.toIso8601String(),
    'orderType': type,
  });

class _Orders implements OrdersRepository {
  final records = <String, Map<String, dynamic>>{};
  Future<void> Function()? beforeDetail;
  List<OrderSummary> get snapshot =>
      records.values.map(OrderSummary.fromJson).toList();

  @override
  Future<OrderDetail> getOrderById(String id) async {
    await beforeDetail?.call();
    final json = records[id];
    if (json == null) {
      throw const ApiException(message: 'Missing', statusCode: 404);
    }
    return OrderDetail.fromJson(json);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();

  final config = PrinterSettings(
    locationId: location,
    enabled: true,
    autoPrintRegularAsap: true,
    autoPrintScheduled: true,
    autoPrintCatering: true,
    autoPrintAccount: owner,
    asapSince: activation,
    scheduledSince: activation,
    cateringSince: activation,
  );
  bool eligible(Map<String, dynamic> order, DateTime now) {
    final detail = AutoPrintPolicy.detail(
      OrderDetail.fromJson(order),
      config,
      owner,
      now,
    );
    expect(
      AutoPrintPolicy.summary(OrderSummary.fromJson(order), config, owner, now),
      detail,
    );
    return detail;
  }

  test(
    'ASAP requires payment, an active status, and placement since activation',
    () {
      for (final status in [
        'pending',
        'confirmed',
        'preparing',
        'ready',
        'delivered',
        'cancelled',
      ]) {
        for (final payment in ['paid', 'unpaid', 'refunded', 'failed']) {
          expect(
            eligible(record(status: status, payment: payment), activation),
            payment == 'paid' &&
                ['confirmed', 'preparing', 'ready'].contains(status),
          );
        }
      }
      expect(eligible(record(placed: activation), activation), isTrue);
      expect(
        eligible(
          record(placed: activation.subtract(const Duration(microseconds: 1))),
          activation,
        ),
        isFalse,
      );
    },
  );

  test('scheduled window includes exact boundary and late confirmation across Pacific DST', () {
    for (final event in [
      DateTime.parse('2026-11-01T01:15:00-08:00'),
      DateTime.parse('2027-03-14T03:15:00-07:00'),
    ]) {
      final start = event.subtract(const Duration(minutes: 30));
      final order = record(
        scheduled: event,
        placed: activation.subtract(const Duration(days: 1)),
      );
      expect(
        eligible(order, start.subtract(const Duration(microseconds: 1))),
        isFalse,
      );
      expect(eligible(order, start), isTrue);
      expect(
        eligible(record(scheduled: event, status: 'pending'), start),
        isFalse,
      );
      expect(eligible(order, start.add(const Duration(minutes: 10))), isTrue);
      expect(
        PelinesTime.inPacific(event).timeZoneOffset,
        Duration(hours: event.year == 2026 ? -8 : -7),
      );
      expect(
        PelinesTime.inPacific(start).timeZoneOffset,
        Duration(hours: event.year == 2026 ? -7 : -8),
      );
    }
    expect(eligible(record(scheduled: activation), activation), isFalse);
  });

  group('SQLite queue with simulated transport', () {
    late Directory folder;
    late PrintingRuntime runtime;
    late _Orders orders;
    late DateTime now;
    late bool closed;

    Future<void> open({bool simulation = true}) async {
      closed = false;
      runtime = PrintingRuntime(
        await openPrintingDatabase(
          factory: databaseFactoryFfiNoIsolate,
          path: '${folder.path}/queue.db',
        ),
        sessionScoped: true,
        now: () => now,
        simulationAdapter: FakePrinterAdapter(
          allowSimulation: simulation,
          delay: Duration.zero,
        ),
      );
      await runtime.start();
      await runtime.updateScope(owner, location, orders, foreground: true);
    }

    Future<void> scan() async {
      await runtime.evaluate(orders.snapshot, location);
      await runtime.queue.idle;
    }

    setUp(() async {
      folder = await Directory.systemTemp.createTemp('pelines-auto-print-');
      now = activation;
      orders = _Orders();
      await open();
      final saved = await runtime.saveSettings(config, activateAutomatic: true);
      expect(saved.asapSince, activation);
      expect(saved.autoPrintAccount, owner);
      await runtime.adapter.connect();
    });

    tearDown(() async {
      if (!closed) await runtime.dispose();
      await databaseFactoryFfiNoIsolate.deleteDatabase(
        '${folder.path}/queue.db',
      );
      await folder.delete();
    });

    test('explicit activation skips ASAP history and discovers a future existing schedule', () async {
      final event = now.add(const Duration(hours: 1));
      final yesterday = now.subtract(const Duration(days: 1));
      orders.records.addAll({
        'history': record(id: 'history', placed: yesterday),
        'future': record(id: 'future', placed: yesterday, scheduled: event),
      });
      await scan();
      expect(await runtime.jobs.list(), isEmpty);
      now = event.subtract(AutoPrintPolicy.lead);
      await scan();
      expect((await runtime.jobs.list()).single.orderId, 'future');
      expect(runtime.adapter.printCalls, 1);
    });

    test('legacy preferences require explicit activation', () async {
      const fresh = PrinterSettings(locationId: location);
      expect(fresh.autoPrintRequested, isFalse);
      final legacyJson = config.toJson()
        ..remove('autoPrintAccount')
        ..remove('asapSince')
        ..remove('scheduledSince')
        ..remove('cateringSince')
        ..remove('autoPrintCatering');
      final legacy = PrinterSettings.fromJson(legacyJson);
      expect(legacy.autoPrintRequested, isFalse);
      await runtime.settings.save(legacy);
      await runtime.saveSettings(legacy);
      now = now.add(const Duration(hours: 2));
      orders.records['order'] = record();
      await scan();
      expect(await runtime.jobs.list(), isEmpty);
      expect(runtime.adapter.printCalls, 0);
    });

    test('validation failure holds the job through reconnection', () async {
      now = now.add(const Duration(hours: 2));
      orders.records['order'] = record();
      final canonical = await orders.getOrderById('order');
      orders.beforeDetail = () async {
        throw const ApiException(message: 'Offline');
      };
      await runtime.service.queueInitialPrint(canonical);
      await runtime.queue.idle;
      expect(runtime.validationFailed, isTrue);
      expect((await runtime.jobs.list()).single.status, PrintJobStatus.queued);
      expect(runtime.adapter.printCalls, 0);
      orders.beforeDetail = null;
      await scan();
      expect(runtime.adapter.printCalls, 1);
    });

    test(
      'catering prints once and marks Pacific event time on paper',
      () async {
        final event = DateTime.utc(2026, 9, 4, 22);
        now = now.add(const Duration(hours: 2));
        orders.records['order'] = record(type: 'catering', scheduled: event);
        await scan();
        final job = (await runtime.jobs.list()).single;
        final paper = latin1.decode(
          const EscPosTicketRenderer().render(job.ticket),
        );
        expect(paper, contains('CATERING'));
        expect(paper, contains('Pickup / Event'));
        expect(paper, contains('2026-09-04 15:00 PDT'));
        now = event.subtract(AutoPrintPolicy.lead);
        await scan();
        expect(runtime.adapter.printCalls, 1);
      },
    );

    test(
      'manual and automatic requests share one initial row and send',
      () async {
        now = now.add(const Duration(hours: 2));
        orders.records['order'] = record();
        await Future.wait([
          runtime.evaluate(orders.snapshot, location),
          runtime.service.queueInitialPrint(await orders.getOrderById('order')),
        ]);
        await runtime.queue.idle;
        expect(
          (await runtime.jobs.list()).single.status,
          PrintJobStatus.submitted,
        );
        expect(runtime.adapter.printCalls, 1);
      },
    );

    for (final status in ['cancelled', 'delivered', 'rescheduled']) {
      test('fresh canonical validation before send handles $status', () async {
        now = now.add(const Duration(hours: 2));
        final firstTime = now.add(const Duration(minutes: 5));
        orders.records['order'] = record(scheduled: firstTime);
        await runtime.adapter.disconnect();
        await scan();
        expect(
          (await runtime.jobs.list()).single.status,
          PrintJobStatus.queued,
        );
        final newTime = now.add(const Duration(hours: 2));
        orders.records['order'] = status == 'rescheduled'
            ? record(scheduled: newTime)
            : record(status: status, scheduled: firstTime);
        await runtime.adapter.connect();
        await scan();
        expect(runtime.adapter.printCalls, 0);
        if (status == 'rescheduled') {
          now = newTime.subtract(AutoPrintPolicy.lead);
          await scan();
          expect(
            (await runtime.jobs.list()).single.ticket.scheduledFor,
            newTime,
          );
          expect(runtime.adapter.printCalls, 1);
        } else {
          expect(
            (await runtime.jobs.list()).single.status,
            PrintJobStatus.cancelled,
          );
        }
      });
    }

    test(
      'background and scope changes stop in-flight validation before dispatch',
      () async {
        now = now.add(const Duration(hours: 2));
        orders.records['order'] = record();
        final canonical = await orders.getOrderById('order');
        final entered = Completer<void>();
        final release = Completer<void>();
        orders.beforeDetail = () {
          if (!entered.isCompleted) entered.complete();
          return release.future;
        };
        await runtime.service.queueInitialPrint(canonical);
        await entered.future;
        await runtime.updateScope(owner, location, orders, foreground: false);
        release.complete();
        await runtime.queue.idle;
        expect(runtime.adapter.printCalls, 0);
        orders.beforeDetail = null;
        await runtime.updateScope(null, null, null, foreground: true);
        expect(runtime.active, isFalse);
        await runtime.updateScope(
          'other-account',
          location,
          orders,
          foreground: true,
        );
        await runtime.queue.idle;
        expect(runtime.adapter.printCalls, 0);
        await runtime.updateScope(
          owner,
          'other-location',
          orders,
          foreground: true,
        );
        await runtime.queue.idle;
        expect(runtime.adapter.printCalls, 0);
        await runtime.updateScope(owner, location, orders, foreground: true);
        await runtime.queue.idle;
        expect(runtime.adapter.printCalls, 1);
      },
    );

    test('restart recovers queued work and never resends submitted, confirmed or unknown', () async {
      now = now.add(const Duration(hours: 2));
      for (final outcome in [
        PrintOutcome.submitted,
        PrintOutcome.confirmed,
        PrintOutcome.unknown,
      ]) {
        final id = outcome.name;
        orders.records[id] = record(id: id);
        runtime.adapter.outcome = outcome;
        await scan();
      }
      await runtime.adapter.disconnect();
      orders.records['queued'] = record(id: 'queued');
      await scan();
      await runtime.dispose();
      closed = true;
      await open();
      final saved = await runtime.settings.read(location);
      expect(saved.autoPrintRequested, isTrue);
      expect(saved.autoPrintAccount, owner);
      expect(saved.asapSince, activation);
      await scan();
      expect(runtime.adapter.printCalls, 1);
      expect((await runtime.jobs.list()).map((job) => job.status), [
        PrintJobStatus.submitted,
        PrintJobStatus.confirmed,
        PrintJobStatus.unknown,
        PrintJobStatus.submitted,
      ]);
    });

    test(
      'blocked simulation disables inherited settings and refuses test jobs',
      () async {
        await runtime.dispose();
        closed = true;
        await open(simulation: false);
        expect(runtime.legacySimulationDisabled, isTrue);
        expect((await runtime.settings.read(location)).enabled, isFalse);
        expect((await runtime.adapter.connect()).status, PrinterStatus.error);
        await expectLater(runtime.saveSettings(config), throwsStateError);
        await expectLater(
          runtime.service.queueTestPrint(location),
          throwsException,
        );
        expect(runtime.adapter.printCalls, 0);
      },
    );
  });
}
