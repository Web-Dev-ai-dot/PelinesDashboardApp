import 'dart:async';

import '../data/print_job_store.dart';
import '../data/printer_adapter.dart';
import '../models/print_job.dart';
import '../models/print_result.dart';
import '../models/ticket_document.dart';

class PrintQueue {
  PrintQueue({
    required this.store,
    required this.adapter,
    required this.canSend,
    this.refreshTicket,
    this.dispatchScope,
  });
  final Future<TicketDocument?> Function(PrintJob)? refreshTicket;
  final Object? Function(PrintJob)? dispatchScope;
  final PrintJobStore store;
  final PrinterAdapter adapter;
  final Future<bool> Function(PrintJob) canSend;
  final _events = StreamController<void>.broadcast();
  Stream<void> get changes => _events.stream;
  String? lastError;
  Future<void>? _startup, _worker;
  bool _requested = false, _closed = false;
  bool _storageFault = false;
  bool get isSending => _worker != null;
  Future<void> initialize() => _startup ??= store.recover();

  void kick() {
    if (_closed || _storageFault) return;
    _requested = true;
    _worker ??= _run();
  }

  Future<void> get idle async {
    while (_worker != null) {
      await _worker;
    }
  }

  Future<void> _run() async {
    try {
      await initialize();
      lastError = null;
      do {
        _requested = false;
        for (final job in await store.list(status: PrintJobStatus.queued)) {
          if (_closed) return;
          final scope = dispatchScope?.call(job);
          if (dispatchScope != null && scope == null) continue;
          if (job.printerId != adapter.printer.id || !await canSend(job)) {
            continue;
          }
          final fresh = refreshTicket == null
              ? job.ticket
              : await refreshTicket!(job);
          if (_closed) return;
          if (fresh == null || scope != dispatchScope?.call(job)) continue;
          final sending = job.transition(
            PrintJobStatus.sending,
            attempt: true,
            freshTicket: fresh,
          );
          if (!await store.update(sending, expected: PrintJobStatus.queued)) {
            continue;
          }
          if (_closed || scope != dispatchScope?.call(job)) {
            await store.update(job, expected: PrintJobStatus.sending);
            continue;
          }
          PrintResult result;
          try {
            result = await adapter.print(sending);
          } on Object {
            result = const PrintResult(
              PrintOutcome.unknown,
              message:
                  'Adapter interrupted. Delivery is unknown; review manually.',
            );
          }
          // If persistence fails after send, leave sending on disk. Recovery
          // changes it to unknown; never resend to compensate for a DB failure.
          if (!await store.update(
            sending.transition(result.jobStatus, error: result.message),
            expected: PrintJobStatus.sending,
          )) {
            throw StateError('Print result could not be recorded.');
          }
        }
      } while (_requested && !_closed);
    } on Object {
      _storageFault = true;
      lastError = 'Printing storage is unavailable. Queue paused. Restart the app after resolving storage; delivery may need review.';
    } finally {
      _worker = null;
      if (!_events.isClosed) _events.add(null);
    }
  }

  Future<void> retry(String id) async {
    await initialize();
    final job = await store.get(id);
    if (job == null || job.status != PrintJobStatus.failedBeforeSend) {
      throw StateError('Only a failure before send can be retried.');
    }
    await store.update(
      job.transition(PrintJobStatus.queued),
      expected: PrintJobStatus.failedBeforeSend,
    );
    kick();
  }

  Future<void> cancel(String id) async {
    final job = await store.get(id);
    if (job == null ||
        !{
          PrintJobStatus.queued,
          PrintJobStatus.failedBeforeSend,
          PrintJobStatus.unknown,
        }.contains(job.status)) {
      return;
    }
    await store.update(
      job.transition(PrintJobStatus.cancelled, error: job.lastError),
      expected: job.status,
    );
  }

  Future<void> dispose() async {
    _closed = true;
    await idle;
    await _events.close();
  }
}
