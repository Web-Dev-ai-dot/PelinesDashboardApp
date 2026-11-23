import 'dart:async';

import '../../../core/api/api_exception.dart';
import '../../orders/data/orders_repository.dart';
import '../../orders/models/order_models.dart';
import '../application/auto_print_policy.dart';
import '../application/print_eligibility.dart';
import '../models/ticket_document.dart';

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
    this.sessionScoped = false,
    this.now = DateTime.now,
    FakePrinterAdapter? simulationAdapter,
  }) : adapter = simulationAdapter ?? FakePrinterAdapter() {
    jobs = PrintJobStore(database);
    settings = PrinterSettingsStore(database);
    queue = PrintQueue(
      store: jobs,
      adapter: selectedAdapter,
      refreshTicket: sessionScoped ? _refreshTicket : null,
      dispatchScope: sessionScoped ? _dispatchScope : null,
      canSend: (job) async {
        final config = await settings.read(job.locationId);
        return active &&
            !_configuring &&
            config.isValid &&
            (config.transport != PrinterTransport.fake ||
                adapter.simulationAvailable) &&
            config.enabled &&
            config.printerId == job.printerId &&
            config.transport == selectedAdapter.printer.transport &&
            (config.transport == PrinterTransport.network ||
                await selectedAdapter.getStatus() == PrinterStatus.connected);
      },
    );
    service = PrintOrderService(
      store: jobs,
      settings: settings,
      queue: queue,
      account: sessionScoped ? () => active ? _account : null : null,
      now: now,
    );
  }
  final bool sessionScoped;
  final DateTime Function() now;
  String? _account, _location;
  OrdersRepository? _orders;
  int _generation = 0;
  bool _evaluating = false;
  bool validationFailed = false;
  bool legacySimulationDisabled = false;

  bool ownsActivation(PrinterSettings config) =>
      config.autoPrintAccount != null && config.autoPrintAccount == _account;

  Object? _dispatchScope(PrintJob job) =>
      active &&
          !_configuring &&
          _account != null &&
          job.accountId == _account &&
          job.locationId == _location
      ? _generation
      : null;

  Future<TicketDocument?> _refreshTicket(PrintJob job) async {
    final scope = _dispatchScope(job);
    if (scope == null) return null;
    if (job.purpose == PrintPurpose.test) return job.ticket;
    try {
      final config = await settings.read(job.locationId);
      if (scope != _dispatchScope(job)) return null;
      final order = await _orders!.getOrderById(job.orderId);
      if (scope != _dispatchScope(job) ||
          order.id != job.orderId ||
          order.locationId != job.locationId) {
        return null;
      }
      if (order.status == OrderStatus.delivered ||
          order.status == OrderStatus.cancelled) {
        if (job.purpose == PrintPurpose.initial) {
          await queue.cancel(job.id);
          return null;
        }
      }
      final eligible = job.automatic
          ? AutoPrintPolicy.detail(order, config, _account, now())
          : job.purpose == PrintPurpose.reprint
          ? PrintEligibility.reprint(order, config)
          : PrintEligibility.initial(order, config);
      return eligible ? service.builder.build(order) : null;
    } on ApiException catch (error) {
      if (scope != _dispatchScope(job)) return null;
      if (error.statusCode == 404) {
        await queue.cancel(job.id);
      } else {
        validationFailed = true;
      }
      return null;
    } on Object {
      validationFailed = true;
      return null;
    }
  }

  Future<void> updateScope(
    String? account,
    String? location,
    OrdersRepository? orders, {
    required bool foreground,
  }) async {
    final enabled =
        foreground && account != null && location != null && orders != null;
    if (_account == account &&
        _location == location &&
        identical(_orders, orders) &&
        active == enabled) {
      return;
    }
    pause();
    _account = account;
    _location = location;
    _orders = orders;
    if (enabled) await activate();
  }

  Future<bool> hasAutomaticPrinting(String location) async {
    final config = await settings.read(location);
    return _autoPrintEnabled(config);
  }

  bool _autoPrintEnabled(PrinterSettings config) =>
      config.enabled && ownsActivation(config) && config.autoPrintRequested;

  Future<bool> evaluate(List<OrderSummary> orders, String location) async {
    if (!active || _evaluating || _location != location || _configuring) {
      return false;
    }
    final generation = _generation;
    bool current() => active && !_configuring && generation == _generation;
    _evaluating = true;
    validationFailed = false;
    try {
      final config = await settings.read(location);
      final coverageLimited = _autoPrintEnabled(config);
      for (final summary in orders) {
        if (!current()) break;
        if (!AutoPrintPolicy.summary(summary, config, _account, now())) {
          continue;
        }
        if (await jobs.findInitial(location, summary.id) != null ||
            !current()) {
          continue;
        }
        OrderDetail order;
        try {
          order = await _orders!.getOrderById(summary.id);
        } on ApiException catch (error) {
          if (error.statusCode == 401 || error.statusCode == 403) rethrow;
          if (error.statusCode != 404) validationFailed = true;
          continue;
        }
        if (!current()) break;
        if (order.id != summary.id ||
            !AutoPrintPolicy.detail(order, config, _account, now())) {
          continue;
        }
        await service.queueAutomaticPrint(order);
      }
      return coverageLimited;
    } finally {
      _evaluating = false;
      if (current()) queue.kick();
    }
  }

  final Database database;
  final PrinterSocketConnector connector;
  // Kept separately so simulation settings survive type changes.
  final FakePrinterAdapter adapter;
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
      _generation++;
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
      ? (adapter.simulationAvailable
            ? adapter
            : throw StateError('Printer simulation is disabled.'))
      : NetworkEscPosPrinterAdapter(settings: config, connector: connector);

  Future<void> _select(
    PrinterSettings config, {
    bool reconnectFake = false,
  }) async {
    if (!config.isValid ||
        (config.transport == PrinterTransport.fake &&
            !adapter.simulationAvailable)) {
      return;
    }
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

  Future<PrinterSettings> saveSettings(
    PrinterSettings config, {
    bool activateAutomatic = false,
  }) async {
    final owner = _account;
    late PrinterSettings saved;
    await _configure(() async {
      if (config.enabled &&
          config.transport == PrinterTransport.fake &&
          !adapter.simulationAvailable) {
        throw StateError('Printer simulation is disabled.');
      }
      if (sessionScoped &&
          (owner == null ||
              owner != _account ||
              config.locationId != _location)) {
        throw StateError('Printing account or location changed.');
      }
      final previous = await settings.read(config.locationId);
      final activationOwner = activateAutomatic
          ? owner
          : previous.autoPrintAccount;
      final sameOwner = activationOwner == previous.autoPrintAccount;
      if (sessionScoped &&
          (owner != _account || config.locationId != _location)) {
        throw StateError('Printing account or location changed.');
      }
      final since = now().toUtc();
      saved = config.copyWith(
        autoPrintAccount: activationOwner,
        resetActivation: true,
        asapSince:
            activationOwner != null &&
                config.enabled &&
                config.autoPrintRegularAsap
            ? (sameOwner ? previous.asapSince : null) ??
                  (activateAutomatic ? since : null)
            : null,
        scheduledSince:
            activationOwner != null &&
                config.enabled &&
                config.autoPrintScheduled
            ? (sameOwner ? previous.scheduledSince : null) ??
                  (activateAutomatic ? since : null)
            : null,
        cateringSince:
            activationOwner != null &&
                config.enabled &&
                config.autoPrintCatering
            ? (sameOwner ? previous.cateringSince : null) ??
                  (activateAutomatic ? since : null)
            : null,
      );
      await settings.save(saved);
      if (saved.enabled && saved.transport == PrinterTransport.network) {
        legacySimulationDisabled = false;
      }
      final enabled = (await settings.list()).where((s) => s.enabled);
      await _select(enabled.isEmpty ? saved : enabled.first);
    });
    return saved;
  }

  Future<void> start() async {
    if (!adapter.simulationAvailable) {
      for (final config in await settings.list()) {
        if (config.transport == PrinterTransport.fake && config.enabled) {
          legacySimulationDisabled = true;
          await settings.save(
            config.copyWith(enabled: false, resetActivation: true),
          );
        }
      }
    }
    await queue.initialize();
  }

  Future<void> activate() async {
    active = true;
    await _configure(() async {
      final configs = (await settings.list()).where(
        (s) =>
            s.enabled &&
            s.isValid &&
            (!sessionScoped || s.locationId == _location),
      );
      if (active && configs.isNotEmpty) {
        await _select(configs.first, reconnectFake: true);
      }
    });
  }

  void pause() {
    active = false;
    _generation++;
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
  final runtime = PrintingRuntime(
    await openPrintingDatabase(),
    sessionScoped: true,
  );
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
