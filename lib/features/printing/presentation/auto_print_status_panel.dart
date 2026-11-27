import 'package:flutter/material.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../core/time/pelines_time.dart';
import '../application/auto_print_policy.dart';
import '../models/auto_print_diagnostics.dart';
import '../models/print_job.dart';
import '../models/printer_settings.dart';
import '../providers/printing_providers.dart';

class AutoPrintStatusPanel extends StatelessWidget {
  const AutoPrintStatusPanel({
    required this.runtime,
    required this.config,
    required this.jobs,
    super.key,
  });

  final PrintingRuntime runtime;
  final PrinterSettings config;
  final List<PrintJob> jobs;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AutoPrintDiagnostics>(
        valueListenable: runtime.diagnostics,
        builder: (context, _, _) {
          final report = runtime.diagnosticsFor(config.locationId);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final type in AutoPrintType.values)
                _stateLine(context, type, runtime.effectiveState(config, type)),
              ExpansionTile(
                key: const Key('auto-print-diagnostics'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: Text(tr(context, 'Auto-print diagnostics')),
                children: [
                  _datedLine(
                    context,
                    'Last successful orders refresh',
                    report.lastRefresh,
                  ),
                  _datedLine(
                    context,
                    'Last orders refresh error',
                    report.lastRefreshError,
                    description: 'Orders could not be refreshed.',
                  ),
                  Text(
                    tr(context, switch (report.evaluation) {
                      AutoPrintEvaluation.waiting =>
                        'Waiting for an orders refresh.',
                      AutoPrintEvaluation.noCandidates =>
                        'No new candidates in the returned orders.',
                      AutoPrintEvaluation.evaluated =>
                        'Returned orders evaluated.',
                      AutoPrintEvaluation.ordersUnavailable =>
                        'Could not update orders. No evaluation ran.',
                      AutoPrintEvaluation.incomplete =>
                        'Some orders could not be verified.',
                    }),
                  ),
                  Text(
                    tr(
                      context,
                      'The server does not guarantee a complete order list.',
                    ),
                  ),
                  for (final item in report.observations)
                    _observation(context, item),
                ],
              ),
            ],
          );
        },
      );

  Widget _stateLine(
    BuildContext context,
    AutoPrintType type,
    EffectiveAutoPrint state,
  ) {
    final title = tr(context, switch (type) {
      AutoPrintType.asap => 'Auto-print Regular ASAP',
      AutoPrintType.scheduled => 'Auto-print Scheduled',
      AutoPrintType.catering => 'Auto-print Catering',
    });
    final status = tr(context, switch (state.mode) {
      AutoPrintMode.disabled => 'Off',
      AutoPrintMode.activationPending => 'Account activation pending',
      AutoPrintMode.active => 'Active',
      AutoPrintMode.paused => switch (state.pause) {
        AutoPrintPause.configuring =>
          'Paused while printer settings are being applied',
        AutoPrintPause.printerUnavailable =>
          'Paused because the selected printer is unavailable',
        AutoPrintPause.ordersUnavailable =>
          'Paused until orders can be refreshed',
        AutoPrintPause.queueUnavailable =>
          'Paused because the print queue is unavailable',
        _ => 'Paused until this location is active in the foreground',
      },
    });
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$title · $status'),
          if (state.activatedAt != null)
            _datedLine(context, 'Activated', state.activatedAt),
        ],
      ),
    );
  }

  Widget _datedLine(
    BuildContext context,
    String label,
    DateTime? date, {
    String? description,
  }) {
    final stamp = date == null
        ? '—'
        : '${PelinesTime.formatDateTime(date)} ${PelinesTime.inPacific(date).timeZoneName}';
    return Text(
      [
        tr(context, label),
        stamp,
        if (date != null && description != null) tr(context, description),
      ].join(' · '),
    );
  }

  Widget _observation(BuildContext context, AutoPrintObservation item) {
    final liveJob = item.jobId == null
        ? null
        : jobs.where((j) => j.id == item.jobId).firstOrNull;
    final status = liveJob?.status ?? item.jobStatus;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        [
          item.orderNumber,
          tr(context, switch (item.decision) {
            AutoPrintDecision.eligible => 'Eligible',
            AutoPrintDecision.printingDisabled =>
              'Printing disabled for this location',
            AutoPrintDecision.typeDisabled => 'Order type is off',
            AutoPrintDecision.activationPending => 'Account activation pending',
            AutoPrintDecision.beforeActivation => 'Before activation',
            AutoPrintDecision.unpaid => 'Payment not confirmed',
            AutoPrintDecision.statusIneligible =>
              'Order status is not eligible',
            AutoPrintDecision.outsideWindow => 'Outside the scheduled window',
            AutoPrintDecision.unsupported =>
              'Order type or location is unsupported',
            AutoPrintDecision.initialJobExists =>
              'Initial print job already exists',
            AutoPrintDecision.detailUnavailable =>
              'Order details could not be verified',
            AutoPrintDecision.queued => 'Queued by auto-print',
          }),
          if (status != null)
            tr(context, switch (status) {
              PrintJobStatus.queued => 'Queued',
              PrintJobStatus.sending => 'Sending',
              PrintJobStatus.submitted => 'Submitted',
              PrintJobStatus.confirmed => 'Confirmed',
              PrintJobStatus.failedBeforeSend => 'Failed before send',
              PrintJobStatus.unknown => 'Unknown',
              PrintJobStatus.cancelled => 'Cancelled',
            }),
          if (item.automatic case final bool automatic)
            tr(context, automatic ? 'Automatic' : 'Manual'),
        ].join(' · '),
      ),
    );
  }
}
