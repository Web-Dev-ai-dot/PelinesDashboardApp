import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_settings_content.dart';

import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/time/pelines_time.dart';
import '../../locations/providers/locations_providers.dart';
import '../application/auto_print_policy.dart';
import '../models/auto_print_diagnostics.dart';
import '../models/print_job.dart';
import 'auto_print_status_panel.dart';
import '../models/print_result.dart';
import '../models/printer.dart';
import '../models/printer_settings.dart';
import '../models/network_printer_endpoint.dart';
import '../providers/printer_controller.dart';
import '../providers/printing_providers.dart';

/// The Fake Printer and its simulation controls exist for development and
/// tests only. Release (store) builds always show the network printer setup.
@visibleForTesting
bool debugShowPrinterSimulation = !kReleaseMode;

class PrinterSettingsScreen extends ConsumerWidget {
  const PrinterSettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(currentLocationProvider);
    return AdminSectionScaffold(
      appBar: AdminAppBar(
        title: Text(
          tr(context, 'Printer Settings'),
          style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
        ),
      ),
      body: location.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(tr(context, 'Current location could not be loaded.')),
        ),
        data: (value) => value == null
            ? Center(
                child: Text(
                  tr(context, 'Choose a location on the home screen.'),
                ),
              )
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

  Future<void> _save(
    PrinterSettings settings, {
    bool activateAutomatic = false,
  }) => _act(
    () => ref
        .read(printerControllerProvider(widget.locationId).notifier)
        .save(settings, activateAutomatic: activateAutomatic),
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
            Text(tr(context, 'Printing storage could not be opened.')),
            TextButton(
              onPressed: () =>
                  ref.invalidate(printerControllerProvider(widget.locationId)),
              child: Text(tr(context, 'Retry')),
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
        final showSimulation = !kReleaseMode && debugShowPrinterSimulation;
        final network =
            !showSimulation ||
            (_type ?? config.transport) == PrinterTransport.network;
        final canEnable =
            showSimulation || config.transport == PrinterTransport.network;
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
          width: PelinesPageWidth.dashboard,
          child: ListView(
            padding: const EdgeInsets.all(PelinesSpacing.lg),
            children: [
              Text(
                network
                    ? tr(
                        context,
                        'Submitted means data was sent. Check the physical ticket.',
                      )
                    : tr(
                        context,
                        'Simulation only. No physical printer is connected.',
                      ),
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
              _PrinterSection(
                key: const Key('printer-device-card'),
                title: tr(context, 'Device'),
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr(context, 'Enable Printing on This Tablet')),
                    subtitle: Text(
                      tr(
                        context,
                        'Enabling this location disables printing for other locations on this tablet.',
                      ),
                    ),
                    value: config.enabled && !_dirty,
                    onChanged:
                        _busy || _dirty || (!canEnable && !config.enabled)
                        ? null
                        : (v) => _save(config.copyWith(enabled: v)),
                  ),
                  if (showSimulation)
                    DropdownButtonFormField<PrinterTransport>(
                      isExpanded: true,
                      isDense: true,
                      alignment: AlignmentDirectional.centerStart,
                      itemHeight: null,
                      initialValue: _type ?? config.transport,
                      decoration: _printerSelectorDecoration(
                        tr(context, 'Printer Type'),
                      ),
                      selectedItemBuilder: (_) => [
                        _PrinterSelectedLabel(tr(context, 'Fake Printer')),
                        _PrinterSelectedLabel(
                          tr(context, 'Network Epson / ESC-POS'),
                        ),
                      ],
                      items: [
                        DropdownMenuItem(
                          value: PrinterTransport.fake,
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(tr(context, 'Fake Printer')),
                          ),
                        ),
                        DropdownMenuItem(
                          value: PrinterTransport.network,
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(tr(context, 'Network Epson / ESC-POS')),
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
                                        printerControllerProvider(
                                          widget.locationId,
                                        ).notifier,
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
                ],
              ),
              const SizedBox(height: 20),
              _PrinterSection(
                key: const Key('printer-connection-card'),
                title: tr(context, 'Connection'),
                children: [
                  if (network) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _name,
                      enabled: !_busy,
                      onChanged: _edit,
                      decoration: PelinesControlStyles.input(
                        label: tr(context, 'Printer Name'),
                      ),
                    ),
                    const SizedBox(height: PelinesSpacing.md),
                    TextField(
                      controller: _host,
                      enabled: !_busy,
                      onChanged: _edit,
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      decoration: PelinesControlStyles.input(
                        label: tr(context, 'IP address / hostname'),
                      ).copyWith(hintText: '192.168.1.50'),
                    ),
                    const SizedBox(height: PelinesSpacing.md),
                    TextField(
                      controller: _port,
                      enabled: !_busy,
                      onChanged: _edit,
                      keyboardType: TextInputType.number,
                      decoration:
                          PelinesControlStyles.input(label: tr(context, 'Port'))
                              .copyWith(
                                helperText: tr(
                                  context,
                                  'Raw TCP printing; Epson default is 9100.',
                                ),
                              ),
                    ),
                    const SizedBox(height: PelinesSpacing.sm),
                    Text(
                      tr(
                        context,
                        '80 mm paper, conservative Font A layout. Save changes before enabling or printing.',
                      ),
                    ),
                    if (_dirty) Text(tr(context, 'Unsaved printer settings')),
                    const SizedBox(height: PelinesSpacing.sm),
                    OutlinedButton(
                      style: PelinesControlStyles.button(
                        PelinesButtonVariant.secondary,
                      ),
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
                      child: Text(tr(context, 'Save Printer')),
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
                          style: PelinesControlStyles.button(
                            PelinesButtonVariant.primary,
                          ),
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
                          child: Text(tr(context, 'Test Connection')),
                        ),
                      if (!network)
                        FilledButton(
                          style: PelinesControlStyles.button(
                            PelinesButtonVariant.primary,
                          ),
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
                          child: Text(tr(context, 'Connect')),
                        ),
                      if (!network)
                        OutlinedButton(
                          style: PelinesControlStyles.button(
                            PelinesButtonVariant.secondary,
                          ),
                          onPressed:
                              _busy ||
                                  engine.queue.isSending ||
                                  status != PrinterStatus.connected
                              ? null
                              : () => _act(() async {
                                  await adapter.disconnect();
                                }),
                          child: Text(tr(context, 'Disconnect')),
                        ),
                      FilledButton.tonal(
                        style: PelinesControlStyles.button(
                          PelinesButtonVariant.primary,
                        ),
                        onPressed:
                            _busy ||
                                _dirty ||
                                !config.enabled ||
                                !config.isValid
                            ? null
                            : () => _act(() async {
                                await engine.service.queueTestPrint(
                                  widget.locationId,
                                  locationName: widget.locationName,
                                );
                              }),
                        child: Text(tr(context, 'Test Print')),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _PrinterSection(
                key: const Key('printer-preferences-card'),
                title: tr(context, 'Automatic printing preferences'),
                children: [
                  AutoPrintStatusPanel(
                    runtime: engine,
                    config: config,
                    jobs: jobs.value ?? const [],
                  ),
                  Text(
                    tr(
                      context,
                      'Paid and confirmed orders print automatically when enabled. ASAP and catering print immediately. Scheduled regular orders print 30 minutes before their scheduled time, or when confirmed within that window.',
                    ),
                  ),
                  Text(
                    tr(
                      context,
                      'Keep the app open and signed in. Use one auto-print device per location. Immediate orders placed before activation can be printed manually.',
                    ),
                  ),
                  Text(
                    tr(
                      context,
                      'Check the queue after an error. Retry failures before send manually. Check the paper for uncertain delivery.',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr(context, 'Auto-print Regular ASAP')),
                    value: config.autoPrintRegularAsap,
                    onChanged: _busy || _dirty
                        ? null
                        : (v) => _save(
                            config.copyWith(autoPrintRegularAsap: v),
                            activateAutomatic: config.enabled && v,
                          ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr(context, 'Auto-print Scheduled')),
                    value: config.autoPrintScheduled,
                    onChanged: _busy || _dirty
                        ? null
                        : (v) => _save(
                            config.copyWith(autoPrintScheduled: v),
                            activateAutomatic: config.enabled && v,
                          ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr(context, 'Auto-print Catering')),
                    value: config.autoPrintCatering,
                    onChanged: _busy || _dirty
                        ? null
                        : (v) => _save(
                            config.copyWith(autoPrintCatering: v),
                            activateAutomatic: config.enabled && v,
                          ),
                  ),
                  if (config.enabled &&
                      AutoPrintType.values.any(
                        (type) =>
                            engine.effectiveState(config, type).mode ==
                            AutoPrintMode.activationPending,
                      ))
                    OutlinedButton(
                      onPressed: _busy || _dirty
                          ? null
                          : () => _save(config, activateAutomatic: true),
                      child: Text(
                        tr(context, 'Activate auto-print for this account'),
                      ),
                    ),
                ],
              ),
              if (!network) ...[
                const SizedBox(height: 20),
                _PrinterSection(
                  title: tr(context, 'Simulation controls'),
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr(context, 'Simulate connection failure')),
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
                        tr(context, 'Next simulated result'),
                      ),
                      selectedItemBuilder: (_) => PrintOutcome.values
                          .map((v) => _PrinterSelectedLabel(_outcomeLabel(v)))
                          .toList(),
                      items: PrintOutcome.values
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(_outcomeLabel(v)),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (v) {
                              if (v != null) {
                                setState(() => adapter.outcome = v);
                              }
                            },
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Text(
                tr(context, 'Print jobs'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                tr(
                  context,
                  showSimulation
                      ? 'Submitted means sent, not physically confirmed. Fake Printer jobs are simulated.'
                      : 'Submitted means sent, not physically confirmed.',
                ),
              ),
              jobs.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => Text(tr(context, 'Jobs could not be loaded.')),
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(tr(context, 'No print jobs yet.')),
                      )
                    : PelinesAdaptiveTable<PrintJob>(
                        key: const Key('print-jobs-table'),
                        rows: list.reversed.toList(),
                        empty: const SizedBox.shrink(),
                        columns: [
                          PelinesTableColumn(
                            label: tr(context, 'Order'),
                            cell: (job) => Text(job.ticket.orderNumber),
                          ),
                          PelinesTableColumn(
                            label: tr(context, 'Purpose'),
                            cell: (job) => Text(job.purpose.name),
                          ),
                          PelinesTableColumn(
                            label: tr(context, 'Status'),
                            cell: (job) => _jobStatus(context, job),
                          ),
                          PelinesTableColumn(
                            label: tr(context, 'Created'),
                            cell: (job) =>
                                Text(PelinesTime.formatDateTime(job.createdAt)),
                          ),
                          PelinesTableColumn(
                            label: tr(context, 'Attempts'),
                            cell: (job) => Text('${job.attemptCount}'),
                          ),
                          PelinesTableColumn(
                            label: tr(context, 'Details'),
                            cell: (job) => SizedBox(
                              width: 220,
                              child: Text(job.lastError ?? '—'),
                            ),
                          ),
                          PelinesTableColumn(
                            label: tr(context, 'Actions'),
                            cell: (job) =>
                                _jobAction(engine, job) ??
                                const SizedBox.shrink(),
                          ),
                        ],
                        cardBuilder: (context, job) => PelinesSettingsCard(
                          key: ValueKey('print-job-${job.id}'),
                          children: [
                            _PrintJobTile(
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${job.ticket.orderNumber} · ${job.purpose.name}',
                                  ),
                                  const SizedBox(height: 8),
                                  _jobStatus(context, job),
                                ],
                              ),
                              subtitle: Text(
                                '${PelinesTime.formatDateTime(job.createdAt)} · ${tr(context, 'Attempts')}: ${job.attemptCount}${job.lastError == null ? '' : '\n${job.lastError}'}',
                              ),
                              trailing: _jobAction(engine, job),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget? _jobAction(PrintingRuntime engine, PrintJob job) =>
      job.status == PrintJobStatus.failedBeforeSend
      ? TextButton(
          onPressed:
              _busy ||
                  _dirty ||
                  job.printerId != engine.selectedAdapter.printer.id
              ? null
              : () => _act(() => engine.queue.retry(job.id)),
          child: Text(tr(context, 'Retry')),
        )
      : job.status == PrintJobStatus.unknown
      ? TextButton(
          onPressed: _busy ? null : () => _reviewUnknown(engine, job),
          child: Text(tr(context, 'Review')),
        )
      : job.status == PrintJobStatus.queued
      ? TextButton(
          onPressed: _busy
              ? null
              : () => _act(() => engine.queue.cancel(job.id)),
          child: Text(tr(context, 'Cancel')),
        )
      : null;

  Future<void> _reviewUnknown(PrintingRuntime runtime, PrintJob job) async {
    final cancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'Delivery is unknown')),
        content: Text(
          tr(
            context,
            'This job will not be resent. After reviewing it, you can close the job. An intentional reprint is a separate operation.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Keep for review')),
          ),
          FilledButton(
            style: PelinesControlStyles.button(PelinesButtonVariant.primary),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Close job')),
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

InputDecoration _printerSelectorDecoration(String label) =>
    PelinesControlStyles.input(
      variant: PelinesInputVariant.select,
      label: label,
    ).copyWith(
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

class _PrinterSection extends StatelessWidget {
  const _PrinterSection({
    required this.title,
    required this.children,
    super.key,
  });
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: PelinesSettingsCard(title: title, children: children),
    ),
  );
}

Widget _jobStatus(BuildContext context, PrintJob job) {
  final attention =
      job.status == PrintJobStatus.unknown ||
      job.status == PrintJobStatus.failedBeforeSend;
  return Align(
    alignment: AlignmentDirectional.centerStart,
    child: PelinesStateBadge(
      label: tr(context, _statusLabel(job.status)),
      foreground: attention
          ? PelinesColors.destructive
          : PelinesColors.textSecondary,
      background: attention
          ? PelinesColors.brandPrimarySoft
          : PelinesColors.mutedSurface,
    ),
  );
}
