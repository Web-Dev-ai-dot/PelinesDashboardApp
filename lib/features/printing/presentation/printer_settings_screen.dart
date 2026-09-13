import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../../locations/providers/locations_providers.dart';
import '../models/print_job.dart';
import '../models/print_result.dart';
import '../models/printer.dart';
import '../models/printer_settings.dart';
import '../models/network_printer_endpoint.dart';
import '../providers/printer_controller.dart';
import '../providers/printing_providers.dart';

class PrinterSettingsScreen extends ConsumerWidget {
  const PrinterSettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(currentLocationProvider);
    return Scaffold(
      appBar: AdminAppBar(title: const Text('Printer Settings')),
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
  PrinterTransport? _type;
  bool _dirty = false;
  bool _fieldsLoaded = false;
  String? _connectionMessage;
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController();

  @override
  void dispose() {
    unawaited(_queueEvents?.cancel());
    _name.dispose();
    _host.dispose();
    _port.dispose();
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

  PrinterSettings? _networkConfig(PrinterSettings config) {
    try {
      final endpoint = NetworkPrinterEndpoint.parse(
        _host.text,
        int.tryParse(_port.text) ?? 0,
      );
      final result = config.copyWith(
        transport: PrinterTransport.network,
        printerId: endpoint.printerId(widget.locationId),
        host: endpoint.host,
        port: endpoint.port,
        displayName: _name.text.trim(),
      );
      return result.isValid ? result : null;
    } on FormatException {
      return null;
    }
  }

  void _edit(String _) => setState(() {
    _dirty = true;
    _connectionMessage = null;
  });

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
        if (!_fieldsLoaded) {
          _fieldsLoaded = true;
          _name.text = config.displayName;
          _host.text = config.host;
          _port.text = '${config.port}';
        }
        final network = (_type ?? config.transport) == PrinterTransport.network;
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
        return PelinesPageBody(
          child: ListView(
            padding: const EdgeInsets.all(PelinesSpacing.lg),
            children: [
              Text(
                widget.locationName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                network
                    ? 'Manual network printing. Check the physical ticket after sending.'
                    : 'Simulation only. No physical printer is connected.',
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
                value: config.enabled && !_dirty,
                onChanged: _busy || _dirty
                    ? null
                    : (v) => _save(config.copyWith(enabled: v)),
              ),
              DropdownButtonFormField<PrinterTransport>(
                isExpanded: true,
                isDense: true,
                alignment: AlignmentDirectional.centerStart,
                itemHeight: null,
                initialValue: _type ?? config.transport,
                decoration: _printerSelectorDecoration('Printer Type'),
                selectedItemBuilder: (_) => const [
                  _PrinterSelectedLabel('Fake Printer'),
                  _PrinterSelectedLabel('Network Epson / ESC-POS'),
                ],
                items: const [
                  DropdownMenuItem(
                    value: PrinterTransport.fake,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Fake Printer'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: PrinterTransport.network,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Network Epson / ESC-POS'),
                    ),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (type) async {
                        if (type == null) return;
                        setState(() {
                          _type = type;
                          _dirty = true;
                          _connectionMessage = null;
                        });
                        if (type == PrinterTransport.fake) {
                          await _act(() async {
                            await ref
                                .read(
                                  printerControllerProvider(widget.locationId)
                                      .notifier,
                                )
                                .save(
                                  config.copyWith(
                                    printerId: 'fake',
                                    transport: type,
                                    enabled: false,
                                  ),
                                );
                            if (mounted) setState(() => _dirty = false);
                          });
                        }
                      },
              ),
              if (network) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  enabled: !_busy,
                  onChanged: _edit,
                  decoration: const InputDecoration(labelText: 'Printer Name'),
                ),
                const SizedBox(height: PelinesSpacing.md),
                TextField(
                  controller: _host,
                  enabled: !_busy,
                  onChanged: _edit,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'IP address / hostname',
                    hintText: '192.168.1.50',
                  ),
                ),
                const SizedBox(height: PelinesSpacing.md),
                TextField(
                  controller: _port,
                  enabled: !_busy,
                  onChanged: _edit,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    helperText: 'Raw TCP printing; Epson default is 9100.',
                  ),
                ),
                const SizedBox(height: PelinesSpacing.sm),
                const Text(
                  '80 mm paper, conservative Font A layout. Save changes before enabling or printing.',
                ),
                if (_dirty) const Text('Unsaved printer settings'),
                const SizedBox(height: PelinesSpacing.sm),
                OutlinedButton(
                  onPressed: _busy || _networkConfig(config) == null
                      ? null
                      : () => _act(() async {
                          final draft = _networkConfig(config)!;
                          await ref
                              .read(
                                printerControllerProvider(widget.locationId)
                                    .notifier,
                              )
                              .save(
                                draft.copyWith(
                                  enabled:
                                      config.transport ==
                                          PrinterTransport.network &&
                                      config.enabled,
                                ),
                              );
                          if (mounted) {
                            setState(() {
                              _dirty = false;
                              _connectionMessage = null;
                            });
                          }
                        }),
                  child: const Text('Save Printer'),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                network
                    ? 'Connection status: ${_connectionMessage ?? 'Not tested'}'
                    : 'Status: ${status.name}',
              ),
              const SizedBox(height: PelinesSpacing.xs),
              PelinesActionBar(
                children: [
                  if (network)
                    FilledButton(
                      onPressed:
                          _busy ||
                              _networkConfig(config) == null ||
                              engine.queue.isSending
                          ? null
                          : () => _act(() async {
                              final result = await engine
                                  .createAdapter(_networkConfig(config)!)
                                  .connect();
                              if (mounted) {
                                setState(
                                  () => _connectionMessage = result.message,
                                );
                              }
                            }),
                      child: const Text('Test Connection'),
                    ),
                  if (!network)
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
                  if (!network)
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
                    onPressed:
                        _busy || _dirty || !config.enabled || !config.isValid
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
                onChanged: _busy || _dirty
                    ? null
                    : (v) => _save(config.copyWith(autoPrintRegularAsap: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-print Scheduled'),
                value: config.autoPrintScheduled,
                onChanged: _busy || _dirty
                    ? null
                    : (v) => _save(config.copyWith(autoPrintScheduled: v)),
              ),
              TextFormField(
                key: ValueKey(config.scheduledLeadMinutes),
                initialValue: '${config.scheduledLeadMinutes}',
                enabled: !_busy && !_dirty,
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
                  unawaited(_save(config.copyWith(scheduledLeadMinutes: lead)));
                },
              ),
              if (!network) ...[
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
                  isExpanded: true,
                  isDense: true,
                  alignment: AlignmentDirectional.centerStart,
                  itemHeight: null,
                  initialValue: adapter.outcome,
                  decoration: _printerSelectorDecoration(
                    'Next simulated result',
                  ),
                  selectedItemBuilder: (_) => PrintOutcome.values
                      .map((v) => _PrinterSelectedLabel(_outcomeLabel(v)))
                      .toList(),
                  items: PrintOutcome.values
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(_outcomeLabel(v)),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (v) {
                          if (v != null) setState(() => adapter.outcome = v);
                        },
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Print jobs',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'Submitted means sent, not physically confirmed. Fake Printer jobs are simulated.',
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
                                child: _PrintJobTile(
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
                                          onPressed:
                                              _busy ||
                                                  _dirty ||
                                                  job.printerId !=
                                                      engine
                                                          .selectedAdapter
                                                          .printer
                                                          .id
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
                                              : () =>
                                                    _reviewUnknown(engine, job),
                                          child: const Text('Review'),
                                        )
                                      : job.status == PrintJobStatus.queued
                                      ? TextButton(
                                          onPressed: _busy
                                              ? null
                                              : () => _act(
                                                  () => engine.queue.cancel(
                                                    job.id,
                                                  ),
                                                ),
                                          child: const Text('Cancel'),
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

InputDecoration _printerSelectorDecoration(String label) => InputDecoration(
  labelText: label,
  floatingLabelBehavior: FloatingLabelBehavior.always,
  contentPadding: const EdgeInsets.symmetric(
    horizontal: PelinesSpacing.lg,
    vertical: PelinesSpacing.sm,
  ),
  constraints: const BoxConstraints(minHeight: 64),
);

/// The closed field has one line; popup options retain their complete labels.
class _PrinterSelectedLabel extends StatelessWidget {
  const _PrinterSelectedLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

String _statusLabel(PrintJobStatus status) => switch (status) {
  PrintJobStatus.queued => 'Queued',
  PrintJobStatus.sending => 'Sending',
  PrintJobStatus.submitted => 'Submitted',
  PrintJobStatus.confirmed => 'Confirmed (simulated)',
  PrintJobStatus.failedBeforeSend => 'Failed before send',
  PrintJobStatus.unknown => 'Unknown',
  PrintJobStatus.cancelled => 'Cancelled',
};

/// Gives the job summary priority over secondary actions at narrow widths.
class _PrintJobTile extends StatelessWidget {
  const _PrintJobTile({
    required this.title,
    required this.subtitle,
    this.trailing,
  });
  final Widget title;
  final Widget subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(PelinesSpacing.md),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final summary = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.titleMedium,
              child: title,
            ),
            const SizedBox(height: PelinesSpacing.xs),
            DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: PelinesColors.textSecondary),
              child: subtitle,
            ),
          ],
        );
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < PelinesLayout.compactWidth * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              summary,
              if (trailing != null) ...[
                const SizedBox(height: PelinesSpacing.sm),
                trailing!,
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: summary),
            if (trailing != null) ...[
              const SizedBox(width: PelinesSpacing.sm),
              trailing!,
            ],
          ],
        );
      },
    ),
  );
}
