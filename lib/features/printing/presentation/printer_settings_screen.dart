import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../../locations/providers/locations_providers.dart';
import '../models/print_job.dart';
import '../models/print_result.dart';
import '../models/printer.dart';
import '../models/printer_settings.dart';
import '../providers/printer_controller.dart';
import '../providers/printing_providers.dart';

class PrinterSettingsScreen extends ConsumerWidget {
  const PrinterSettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(currentLocationProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Printer Settings')),
      body: location.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Current location could not be loaded.')),
        data: (value) => value == null
            ? const Center(child: Text('Choose a location on the home screen.'))
            : _SettingsBody(
                key: ValueKey(value.id),
                locationId: value.id,
                locationName: value.name,
              ),
      ),
    );
  }
}

class _SettingsBody extends ConsumerStatefulWidget {
  const _SettingsBody({
    required this.locationId,
    required this.locationName,
    super.key,
  });
  final String locationId, locationName;
  @override
  ConsumerState<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends ConsumerState<_SettingsBody> {
  bool _busy = false;
  String? _error;
  StreamSubscription<void>? _queueEvents;
  PrintingRuntime? _runtime;

  @override
  void dispose() {
    unawaited(_queueEvents?.cancel());
    super.dispose();
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Operation could not be completed. Check printing settings and storage.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(PrinterSettings settings) => _act(
    () => ref
        .read(printerControllerProvider(widget.locationId).notifier)
        .save(settings),
  );

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(printerControllerProvider(widget.locationId));
    final runtime = ref.watch(printingRuntimeProvider);
    return settings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Printing storage could not be opened.'),
            TextButton(
              onPressed: () =>
                  ref.invalidate(printerControllerProvider(widget.locationId)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (config) {
        final engine = runtime.value;
        if (engine == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_runtime != engine) {
          _runtime = engine;
          unawaited(_queueEvents?.cancel());
          _queueEvents = engine.queue.changes.listen((_) {
            if (mounted) setState(() {});
          });
        }
        final adapter = engine.adapter;
        final status = adapter.printer.status;
        final jobs = ref.watch(printJobsProvider(widget.locationId));
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(PelinesSpacing.lg),
              children: [
                Text(
                  widget.locationName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Simulation only. No physical printer is connected.',
                ),
                if (_error ?? engine.queue.lastError case final String message)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable Printing on This Tablet'),
                  subtitle: const Text(
                    'Enabling this location disables printing for other locations on this tablet.',
                  ),
                  value: config.enabled,
                  onChanged: _busy
                      ? null
                      : (v) => _save(config.copyWith(enabled: v)),
                ),
                DropdownButtonFormField<PrinterTransport>(
                  initialValue: config.transport,
                  decoration: const InputDecoration(labelText: 'Printer'),
                  items: const [
                    DropdownMenuItem(
                      value: PrinterTransport.fake,
                      child: Text('Fake Printer'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (_) => _save(
                          config.copyWith(
                            printerId: 'fake',
                            transport: PrinterTransport.fake,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                Text('Status: ${status.name}'),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton(
                      onPressed: _busy || status == PrinterStatus.connected
                          ? null
                          : () => _act(() async {
                              final connecting = adapter.connect();
                              setState(() {});
                              final result = await connecting;
                              if (result.message != null && mounted) {
                                setState(() => _error = result.message);
                              }
                              engine.queue.kick();
                            }),
                      child: const Text('Connect'),
                    ),
                    OutlinedButton(
                      onPressed:
                          _busy ||
                              engine.queue.isSending ||
                              status != PrinterStatus.connected
                          ? null
                          : () => _act(() async {
                              await adapter.disconnect();
                            }),
                      child: const Text('Disconnect'),
                    ),
                    FilledButton.tonal(
                      onPressed: _busy || !config.enabled
                          ? null
                          : () => _act(() async {
                              await engine.service.queueTestPrint(
                                widget.locationId,
                                locationName: widget.locationName,
                              );
                            }),
                      child: const Text('Test Print'),
                    ),
                  ],
                ),
                const Divider(height: 32),
                Text(
                  'Automatic printing preferences',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Saved for a future block. These switches do not start automatic printing.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-print Regular ASAP'),
                  value: config.autoPrintRegularAsap,
                  onChanged: _busy
                      ? null
                      : (v) => _save(config.copyWith(autoPrintRegularAsap: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-print Scheduled'),
                  value: config.autoPrintScheduled,
                  onChanged: _busy
                      ? null
                      : (v) => _save(config.copyWith(autoPrintScheduled: v)),
                ),
                TextFormField(
                  key: ValueKey(config.scheduledLeadMinutes),
                  initialValue: '${config.scheduledLeadMinutes}',
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Scheduled lead time (minutes)',
                    helperText: '0–1440 minutes. Press Done to save.',
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (value) {
                    final lead = int.tryParse(value);
                    if (lead == null || lead < 0 || lead > 1440) {
                      setState(
                        () => _error = 'Enter a whole number from 0 to 1440.',
                      );
                      return;
                    }
                    unawaited(
                      _save(config.copyWith(scheduledLeadMinutes: lead)),
                    );
                  },
                ),
                const Divider(height: 32),
                Text(
                  'Simulation controls',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Simulate connection failure'),
                  value: adapter.connectionFails,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => adapter.connectionFails = v),
                ),
                DropdownButtonFormField<PrintOutcome>(
                  initialValue: adapter.outcome,
                  decoration: const InputDecoration(
                    labelText: 'Next simulated result',
                  ),
                  items: PrintOutcome.values
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(_outcomeLabel(v)),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (v) {
                          if (v != null) setState(() => adapter.outcome = v);
                        },
                ),
                const SizedBox(height: 20),
                Text(
                  'Print jobs',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Submitted means sent, not physically confirmed. All results here are simulated.',
                ),
                jobs.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const Text('Jobs could not be loaded.'),
                  data: (list) => list.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('No print jobs yet.'),
                        )
                      : Column(
                          children: list.reversed
                              .map(
                                (job) => Card(
                                  child: ListTile(
                                    title: Text(
                                      '${job.ticket.orderNumber} · ${job.purpose.name} · ${_statusLabel(job.status)}',
                                    ),
                                    subtitle: Text(
                                      '${PelinesTime.formatDateTime(job.createdAt)} · Attempts: ${job.attemptCount}${job.lastError == null ? '' : '\n${job.lastError}'}',
                                    ),
                                    trailing:
                                        job.status ==
                                            PrintJobStatus.failedBeforeSend
                                        ? TextButton(
                                            onPressed: _busy
                                                ? null
                                                : () => _act(
                                                    () => engine.queue.retry(
                                                      job.id,
                                                    ),
                                                  ),
                                            child: const Text('Retry'),
                                          )
                                        : job.status == PrintJobStatus.unknown
                                        ? TextButton(
                                            onPressed: _busy
                                                ? null
                                                : () => _reviewUnknown(
                                                    engine,
                                                    job,
                                                  ),
                                            child: const Text('Review'),
                                          )
                                        : null,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _reviewUnknown(PrintingRuntime runtime, PrintJob job) async {
    final cancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delivery is unknown'),
        content: const Text(
          'This job will not be resent. After reviewing it, you can close the job. An intentional reprint is a separate operation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep for review'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close job'),
          ),
        ],
      ),
    );
    if (cancel == true && mounted) {
      await _act(() => runtime.queue.cancel(job.id));
    }
  }
}

String _outcomeLabel(PrintOutcome outcome) => switch (outcome) {
  PrintOutcome.submitted => 'Submitted (not physical confirmation)',
  PrintOutcome.confirmed => 'Confirmed (simulated)',
  PrintOutcome.failedBeforeSend => 'Failed before send',
  PrintOutcome.unknown => 'Unknown',
};
String _statusLabel(PrintJobStatus status) => switch (status) {
  PrintJobStatus.queued => 'Queued',
  PrintJobStatus.sending => 'Sending',
  PrintJobStatus.submitted => 'Submitted',
  PrintJobStatus.confirmed => 'Confirmed (simulated)',
  PrintJobStatus.failedBeforeSend => 'Failed before send',
  PrintJobStatus.unknown => 'Unknown',
  PrintJobStatus.cancelled => 'Cancelled',
};
