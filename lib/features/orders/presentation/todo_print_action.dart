import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../locations/providers/locations_providers.dart';
import '../../printing/models/print_job.dart';
import '../../printing/providers/printing_providers.dart';
import '../models/order_models.dart';
import '../providers/orders_providers.dart';

/// Initial printing is idempotent in the existing durable queue. Never silently
/// reprint an uncertain/submitted ticket; recovery stays in Printer Settings.
class TodoPrintAction extends ConsumerStatefulWidget {
  const TodoPrintAction({required this.order, super.key});
  final OrderSummary order;

  @override
  ConsumerState<TodoPrintAction> createState() => _TodoPrintActionState();
}

class _TodoPrintActionState extends ConsumerState<TodoPrintAction> {
  bool _busy = false;
  PrintJob? _job;
  String? _error;

  Future<void> _print() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final runtime = await ref.read(printingRuntimeProvider.future);
      final order = await ref
          .read(ordersRepositoryProvider)
          .getOrderById(widget.order.id);
      if (!mounted) return;
      if (ref.read(currentLocationProvider).value?.id != order.locationId) {
        return;
      }
      if (ref.read(orderMutationProvider(order.id)).isBusy) return;
      final job = await runtime.service.queueInitialPrint(order);
      if (mounted) setState(() => _job = job);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mutation = ref.watch(orderMutationProvider(widget.order.id));
    final jobs = _job == null
        ? null
        : ref.watch(printJobsProvider(widget.order.locationId));
    final job = jobs?.value?.where((j) => j.id == _job!.id).firstOrNull ?? _job;
    final eligible =
        widget.order.paymentStatus.isOperationallyPaid &&
        {
          OrderStatus.confirmed,
          OrderStatus.preparing,
          OrderStatus.ready,
        }.contains(widget.order.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: Key('todo-print-${widget.order.id}'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _busy || mutation.isBusy || !eligible || job != null
              ? null
              : _print,
          icon: const Icon(Icons.print_outlined),
          label: Text(tr(context, _busy ? 'Sending' : 'Print ticket')),
        ),
        if (_error != null)
          Text(
            tr(context, _error!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (job != null) ...[
          if (job.printerId == 'fake')
            Text(tr(context, 'Simulation only. No physical ticket.')),
          Text(
            tr(context, switch (job.status) {
              PrintJobStatus.queued => 'Queued',
              PrintJobStatus.sending => 'Sending',
              PrintJobStatus.submitted =>
                'Submitted (not physical confirmation)',
              PrintJobStatus.confirmed => 'Confirmed (simulated)',
              PrintJobStatus.failedBeforeSend => 'Failed before send',
              PrintJobStatus.unknown => 'Unknown',
              PrintJobStatus.cancelled => 'Cancelled',
            }),
          ),
          if (job.lastError != null) Text(tr(context, job.lastError!)),
          Text(tr(context, 'Review print jobs in Printer Settings.')),
        ],
        if (jobs?.hasError == true)
          Text(tr(context, 'Print result could not be recorded.')),
      ],
    );
  }
}
