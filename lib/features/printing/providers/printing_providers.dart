import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../application/print_order_service.dart';
import '../application/print_queue.dart';
import '../data/fake_printer_adapter.dart';
import '../data/print_job_store.dart';
import '../data/printer_settings_store.dart';
import '../data/printing_database.dart';
import '../models/print_job.dart';
import '../models/printer.dart';

class PrintingRuntime {
  PrintingRuntime(this.database) {
    jobs = PrintJobStore(database);
    settings = PrinterSettingsStore(database);
    queue = PrintQueue(
      store: jobs,
      adapter: adapter,
      canSend: (job) async {
        final config = await settings.read(job.locationId);
        return active &&
            config.enabled &&
            config.printerId == job.printerId &&
            config.transport == adapter.printer.transport &&
            await adapter.getStatus() == PrinterStatus.connected;
      },
    );
    service = PrintOrderService(store: jobs, settings: settings, queue: queue);
  }
  final Database database;
  final FakePrinterAdapter adapter = FakePrinterAdapter();
  late final PrintJobStore jobs;
  late final PrinterSettingsStore settings;
  late final PrintQueue queue;
  late final PrintOrderService service;
  bool active = false;
  Future<void> start() async {
    await queue.initialize();
  }

  Future<void> activate() async {
    active = true;
    final configs = await settings.list();
    if (active &&
        configs.any(
          (s) =>
              s.enabled &&
              s.transport == PrinterTransport.fake &&
              s.printerId == 'fake',
        )) {
      await adapter.connect();
      if (active) queue.kick();
    }
  }

  void pause() {
    active = false;
  }

  Future<void> dispose() async {
    pause();
    await queue.dispose();
    await adapter.disconnect();
    await jobs.dispose();
    await database.close();
  }
}

/// Application scoped: leaving Settings must not dispose an in-flight job.
final printingRuntimeProvider = FutureProvider<PrintingRuntime>((ref) async {
  final runtime = PrintingRuntime(await openPrintingDatabase());
  ref.onDispose(() => unawaited(runtime.dispose()));
  await runtime.start();
  return runtime;
});

final printJobsProvider = StreamProvider.autoDispose
    .family<List<PrintJob>, String>((ref, locationId) async* {
      final runtime = await ref.watch(printingRuntimeProvider.future);
      // Subscribe before reading to avoid losing updates between initial read and listen.
      final events = StreamController<void>();
      final subscription = runtime.jobs.changes.listen((_) => events.add(null));
      ref.onDispose(() {
        unawaited(subscription.cancel());
        unawaited(events.close());
      });
      events.add(null);
      await for (final _ in events.stream) {
        yield await runtime.jobs.list(locationId: locationId);
      }
    });
