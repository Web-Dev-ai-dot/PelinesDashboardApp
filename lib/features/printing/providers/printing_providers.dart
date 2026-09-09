import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../application/print_order_service.dart';
import '../application/print_queue.dart';
import '../data/fake_printer_adapter.dart';
import '../data/network_esc_pos_printer_adapter.dart';
import '../data/printer_adapter.dart';
import '../data/printer_socket.dart';
import '../data/selected_printer_adapter.dart';
import '../data/print_job_store.dart';
import '../data/printer_settings_store.dart';
import '../data/printing_database.dart';
import '../models/print_job.dart';
import '../models/printer.dart';
import '../models/printer_settings.dart';

class PrintingRuntime {
  PrintingRuntime(
    this.database, {
    this.connector = const DartPrinterSocketConnector(),
  }) {
    jobs = PrintJobStore(database);
    settings = PrinterSettingsStore(database);
    queue = PrintQueue(
      store: jobs,
      adapter: selectedAdapter,
      canSend: (job) async {
        final config = await settings.read(job.locationId);
        return active &&
            !_configuring &&
            config.isValid &&
            config.enabled &&
            config.printerId == job.printerId &&
            config.transport == selectedAdapter.printer.transport &&
            (config.transport == PrinterTransport.network ||
                await selectedAdapter.getStatus() == PrinterStatus.connected);
      },
    );
    service = PrintOrderService(store: jobs, settings: settings, queue: queue);
  }
  final Database database;
  final PrinterSocketConnector connector;
  // Kept separately so simulation settings survive type changes.
  final FakePrinterAdapter adapter = FakePrinterAdapter();
  late final SelectedPrinterAdapter selectedAdapter = SelectedPrinterAdapter(
    adapter,
  );
  late final PrintJobStore jobs;
  late final PrinterSettingsStore settings;
  late final PrintQueue queue;
  late final PrintOrderService service;
  bool active = false;
  bool _configuring = false;
  Future<void> _configurationTask = Future.value();

  Future<void> _configure(Future<void> Function() action) {
    final task = _configurationTask.then((_) async {
      _configuring = true;
      try {
        await queue.idle;
        await action();
      } finally {
        _configuring = false;
        if (active) queue.kick();
      }
    });
    _configurationTask = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  PrinterAdapter createAdapter(PrinterSettings config) =>
      config.transport == PrinterTransport.fake
      ? adapter
      : NetworkEscPosPrinterAdapter(settings: config, connector: connector);

  Future<void> _select(
    PrinterSettings config, {
    bool reconnectFake = false,
  }) async {
    if (!config.isValid) return;
    if (selectedAdapter.printer.id != config.printerId) {
      await selectedAdapter.disconnect();
      selectedAdapter.current = createAdapter(config);
    }
    if (reconnectFake &&
        active &&
        config.enabled &&
        config.transport == PrinterTransport.fake) {
      await adapter.connect();
    }
  }

  Future<void> saveSettings(PrinterSettings config) => _configure(() async {
    await settings.save(config);
    final enabled = (await settings.list()).where((s) => s.enabled);
    await _select(enabled.isEmpty ? config : enabled.first);
  });
  Future<void> start() async {
    await queue.initialize();
  }

  Future<void> activate() async {
    active = true;
    await _configure(() async {
      final configs = (await settings.list()).where(
        (s) => s.enabled && s.isValid,
      );
      if (active && configs.isNotEmpty) {
        await _select(configs.first, reconnectFake: true);
      }
    });
  }

  void pause() {
    active = false;
  }

  Future<void> dispose() async {
    pause();
    await _configurationTask;
    await queue.dispose();
    await selectedAdapter.disconnect();
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
