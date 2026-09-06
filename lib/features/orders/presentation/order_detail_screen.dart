import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/time/pelines_time.dart';
import '../models/order_models.dart';
import '../models/order_status_action.dart';
import '../providers/order_alerts_controller.dart';
import '../providers/orders_providers.dart';
import 'order_ui_helpers.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({required this.orderId, super.key});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(orderAlertsProvider.notifier).acknowledge(orderId);
    });
    final AsyncValue<OrderDetail> detail = ref.watch(
      orderDetailProvider(orderId),
    );
    final OrderNotesState notes = ref.watch(orderNotesProvider(orderId));

    Future<void> leave() async {
      if (notes.isDirty) {
        final bool discard = await _confirmDiscardNotes(context);
        if (!discard || !context.mounted) return;
        ref.read(orderNotesProvider(orderId).notifier).discardDraft();
        await WidgetsBinding.instance.endOfFrame;
      }
      if (context.mounted) await Navigator.of(context).maybePop();
    }

    return PopScope(
      canPop: !notes.isDirty,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) unawaited(leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: leave),
          title: Text(detail.value?.orderNumber ?? 'Order'),
        ),
        body: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stack) {
            final bool missing =
                error is ApiException && error.statusCode == 404;
            return _DetailError(
              message: missing ? 'Order no longer available' : error.toString(),
              onRetry: missing
                  ? null
                  : () => ref.invalidate(orderDetailProvider(orderId)),
            );
          },
          data: (OrderDetail order) => _DetailBody(initialOrder: order),
        ),
      ),
    );
  }

  Future<bool> _confirmDiscardNotes(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Discard unsaved notes?'),
            content: const Text('You have unsaved internal notes.'),
            actions: <Widget>[
              TextButton(
                key: const Key('unsaved-stay'),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Stay'),
              ),
              FilledButton(
                key: const Key('unsaved-discard'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Discard changes'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.initialOrder});
  final OrderDetail initialOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final OrderMutationState mutation = ref.watch(
      orderMutationProvider(initialOrder.id),
    );
    final OrderNotesState notes = ref.watch(
      orderNotesProvider(initialOrder.id),
    );
    final OrderDetail order = mutation.canonicalOrder ?? initialOrder;
    ref.listen<OrderMutationState>(orderMutationProvider(initialOrder.id), (
      OrderMutationState? previous,
      OrderMutationState next,
    ) {
      if (next.message == null ||
          next.phase == previous?.phase && next.message == previous?.message) {
        return;
      }
      if (next.phase == OrderMutationPhase.success ||
          next.phase == OrderMutationPhase.error) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.message!)));
      }
    });
    final OrderStatusAction? action = order.paymentStatus.isOperationallyPaid
        ? OrderStatusAction.forOrder(order.status, order.fulfillmentType)
        : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                order.orderNumber,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            StatusChip(
              status: order.status,
              fulfillment: order.fulfillmentType,
              rawStatus: order.rawStatus,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Placed ${PelinesTime.formatDateTime(order.createdAt)}'),
        if (!order.paymentStatus.isOperationallyPaid) ...<Widget>[
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Payment not completed',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'This order cannot be processed because its payment is not marked as paid.',
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _Section(
          title: 'Fulfillment',
          children: <Widget>[
            _Row('Requested time', requestedTime(order.scheduledFor)),
            _Row('Method', fulfillmentLabel(order.fulfillmentType)),
            _Row('Location', _locationName(order)),
            if (order.fulfillmentType == FulfillmentType.delivery)
              _Row('Delivery address', _address(order.deliveryAddress)),
          ],
        ),
        _Section(
          title: 'Customer',
          children: <Widget>[
            _Row('Name', order.contactName),
            _Row('Phone', order.contactPhone),
            _Row('Email', order.contactEmail),
          ],
        ),
        if (order.orderType == OrderType.catering)
          _Section(
            title: 'Event',
            children: <Widget>[
              _Row('Event name', _mapString(order.eventDetails, 'eventName')),
              _Row('Attendees', _mapValue(order.eventDetails, 'attendees')),
            ],
          ),
        if (order.notes?.trim().isNotEmpty == true)
          _Section(
            title: 'Customer Notes',
            children: <Widget>[Text(order.notes!)],
          ),
        _InternalNotesEditor(order: order),
        _Section(
          title: 'Items',
          children: order.items.isEmpty
              ? const <Widget>[Text('No items recorded')]
              : order.items
                    .map((OrderItem item) => _Item(order: item))
                    .toList(growable: false),
        ),
        _Section(
          title: 'Financial',
          children: <Widget>[
            _MoneyRow('Subtotal', order.subtotalCents),
            if (order.discountCents != 0)
              _MoneyRow(
                order.discountCode == null
                    ? 'Discount'
                    : 'Discount (${order.discountCode})',
                -order.discountCents,
              ),
            _MoneyRow('Service fee', order.serviceFeeCents),
            _MoneyRow('Delivery fee', order.deliveryFeeCents),
            _MoneyRow('Tax', order.taxCents),
            _MoneyRow('Tip', order.tipCents),
            const Divider(),
            _MoneyRow('Total', order.totalCents, emphasized: true),
          ],
        ),
        _Section(
          title: 'Payment',
          children: <Widget>[
            _Row('Status', order.paymentStatus.name),
            if (order.cardBrand != null && order.cardLast4 != null)
              _Row('Card', '${order.cardBrand} ending in ${order.cardLast4}'),
          ],
        ),
        if (order.printedAt != null || order.deliveredAt != null)
          _Section(
            title: 'Operational',
            children: <Widget>[
              if (order.printedAt != null)
                _Row('Printed', PelinesTime.formatDateTime(order.printedAt!)),
              if (order.deliveredAt != null)
                _Row(
                  'Completed',
                  PelinesTime.formatDateTime(order.deliveredAt!),
                ),
            ],
          ),
        if (action != null)
          _OrderActions(
            action: action,
            mutation: mutation,
            fulfillment: order.fulfillmentType,
            otherMutationBusy: notes.isBusy,
            onPressed: () => _performAction(context, ref, order, action),
          ),
      ],
    );
  }

  Future<void> _performAction(
    BuildContext context,
    WidgetRef ref,
    OrderDetail order,
    OrderStatusAction action,
  ) async {
    final OrderMutationController controller = ref.read(
      orderMutationProvider(order.id).notifier,
    );
    if (action == OrderStatusAction.completeOrder) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => _CompletionDialog(order: order),
      );
      if (confirmed != true || !context.mounted) return;

      // Re-read immediately before the terminal PATCH. Completion stamps the
      // order and triggers customer-facing backend side effects.
      final OrderDetail latest =
          ref.read(orderDetailProvider(order.id)).value ??
          ref.read(orderMutationProvider(order.id)).canonicalOrder ??
          order;
      if (!OrderStatusAction.allows(
        latest.status,
        OrderStatus.delivered,
        fulfillment: latest.fulfillmentType,
      )) {
        controller.adoptChangedOrder(latest);
        return;
      }
      await controller.markOrderCompleted(latest);
      return;
    }

    await switch (action) {
      OrderStatusAction.acceptOrder => controller.acceptOrder(order),
      OrderStatusAction.startPreparing => controller.startPreparing(order),
      OrderStatusAction.markReady => controller.markReady(order),
      OrderStatusAction.completeOrder => Future<void>.value(),
    };
  }

  String _locationName(OrderDetail order) =>
      _mapString(order.location, 'name') == '—'
      ? order.locationId
      : _mapString(order.location, 'name');
}

class _OrderActions extends StatelessWidget {
  const _OrderActions({
    required this.action,
    required this.mutation,
    required this.fulfillment,
    required this.otherMutationBusy,
    required this.onPressed,
  });

  final OrderStatusAction action;
  final OrderMutationState mutation;
  final FulfillmentType fulfillment;
  final bool otherMutationBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bool busy = mutation.isBusy || otherMutationBusy;
    final bool showButton =
        action != OrderStatusAction.completeOrder ||
        mutation.phase != OrderMutationPhase.error ||
        mutation.terminalRetryAllowed;
    return _Section(
      title: 'Order actions',
      children: <Widget>[
        if (mutation.phase == OrderMutationPhase.error &&
            mutation.message != null) ...<Widget>[
          Text(
            mutation.message!,
            key: const Key('order-mutation-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 12),
        ],
        if (showButton)
          FilledButton(
            key: const Key('order-primary-action'),
            onPressed: busy ? null : onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (busy) ...<Widget>[
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    busy
                        ? action.progressLabelFor(fulfillment)
                        : action.labelFor(fulfillment),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _InternalNotesEditor extends ConsumerStatefulWidget {
  const _InternalNotesEditor({required this.order});

  final OrderDetail order;

  @override
  ConsumerState<_InternalNotesEditor> createState() =>
      _InternalNotesEditorState();
}

class _InternalNotesEditorState extends ConsumerState<_InternalNotesEditor> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.order.internalNotes ?? '',
    );
    _syncAfterBuild();
  }

  @override
  void didUpdateWidget(covariant _InternalNotesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.internalNotes != widget.order.internalNotes) {
      _syncAfterBuild();
    }
  }

  void _syncAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(orderNotesProvider(widget.order.id).notifier)
          .syncFromCanonical(widget.order.internalNotes);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OrderNotesState notes = ref.watch(
      orderNotesProvider(widget.order.id),
    );
    final OrderMutationState statusMutation = ref.watch(
      orderMutationProvider(widget.order.id),
    );
    ref.listen<OrderNotesState>(orderNotesProvider(widget.order.id), (
      OrderNotesState? previous,
      OrderNotesState next,
    ) {
      if (_textController.text == next.draft) return;
      _textController.value = TextEditingValue(
        text: next.draft,
        selection: TextSelection.collapsed(offset: next.draft.length),
      );
    });
    final bool statusBusy = statusMutation.isBusy;
    final bool canSave = notes.canSave && !statusBusy;

    return _Section(
      title: 'Internal notes',
      children: <Widget>[
        const Text(
          'Private notes for administrators only.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('internal-notes-field'),
          controller: _textController,
          enabled: !notes.isBusy && !notes.orderMissing,
          minLines: 4,
          maxLines: 6,
          maxLength: OrderNotesController.maxLength,
          maxLengthEnforcement: MaxLengthEnforcement.none,
          onChanged: ref
              .read(orderNotesProvider(widget.order.id).notifier)
              .edit,
          decoration: InputDecoration(
            hintText: 'Add a private note about this order',
            errorText: notes.isValid
                ? null
                : 'Internal notes cannot exceed 5000 characters.',
            border: const OutlineInputBorder(),
          ),
        ),
        if (notes.hasRemoteConflict) ...<Widget>[
          const Text(
            'This note was updated elsewhere. Your draft has been preserved.',
            key: Key('notes-conflict-warning'),
            style: TextStyle(color: Colors.deepOrange),
          ),
          const SizedBox(height: 10),
        ],
        if (notes.errorMessage != null) ...<Widget>[
          Text(
            notes.errorMessage!,
            key: const Key('notes-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            if (notes.phase == OrderNotesPhase.saved) ...<Widget>[
              const Text('Saved', key: Key('notes-saved')),
              const SizedBox(width: 12),
            ],
            FilledButton(
              key: const Key('save-internal-notes'),
              onPressed: canSave ? _save : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (notes.isBusy) ...<Widget>[
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(notes.isBusy ? 'Saving...' : 'Save notes'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _save() async {
    final OrderNotesController controller = ref.read(
      orderNotesProvider(widget.order.id).notifier,
    );
    final OrderNotesState notes = ref.read(orderNotesProvider(widget.order.id));
    if (notes.hasRemoteConflict) {
      final bool overwrite =
          await showDialog<bool>(
            context: context,
            builder: (BuildContext context) => AlertDialog(
              title: const Text('Replace newer note?'),
              content: const Text(
                'This note was changed by another user. Saving will replace the newer server note with your current draft.',
              ),
              actions: <Widget>[
                TextButton(
                  key: const Key('notes-conflict-cancel'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const Key('notes-conflict-save'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Save anyway'),
                ),
              ],
            ),
          ) ??
          false;
      if (!overwrite || !mounted) return;
      await controller.save(overwriteConflict: true);
      return;
    }
    await controller.save();
  }
}

class _CompletionDialog extends StatelessWidget {
  const _CompletionDialog({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    final bool pickup = order.fulfillmentType == FulfillmentType.pickup;
    final String action = pickup ? 'Mark picked up' : 'Mark delivered';
    return AlertDialog(
      title: Text(pickup ? 'Confirm pickup?' : 'Confirm delivery?'),
      content: Text(
        pickup
            ? 'Confirm that the customer has picked up this order? It will be marked complete and removed from active orders.'
            : 'Confirm that this order has been delivered to the customer? It will be marked delivered and removed from active orders.',
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('completion-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep active'),
        ),
        FilledButton(
          key: const Key('completion-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow(this.label, this.cents, {this.emphasized = false});
  final String label;
  final int cents;
  final bool emphasized;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          label,
          style: emphasized
              ? const TextStyle(fontWeight: FontWeight.bold)
              : null,
        ),
        Text(
          money(cents),
          style: emphasized
              ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)
              : null,
        ),
      ],
    ),
  );
}

class _Item extends StatelessWidget {
  const _Item({required this.order});
  final OrderItem order;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${order.quantity}× ${order.productName}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(money(order.lineTotalCents)),
          ],
        ),
        for (final OrderModifier modifier in order.modifiers)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 3),
            child: Text(
              '${modifier.groupName}: ${modifier.optionName}${modifier.priceDeltaCents == 0 ? '' : ' (+${money(modifier.priceDeltaCents)})'}',
            ),
          ),
        if (order.notes?.trim().isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Text(
              'Note: ${order.notes}',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
      ],
    ),
  );
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          if (onRetry != null)
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Back to Today Orders'),
          ),
        ],
      ),
    ),
  );
}

String _mapString(Map<String, dynamic>? map, String key) =>
    map?[key] is String ? map![key] as String : '—';
String _mapValue(Map<String, dynamic>? map, String key) =>
    map?[key]?.toString() ?? '—';
String _address(Map<String, dynamic>? map) {
  if (map == null) return '—';
  final List<String> parts = <String>[
    for (final String key in <String>['line1', 'line2', 'city', 'state', 'zip'])
      if (map[key] is String && (map[key] as String).trim().isNotEmpty)
        map[key] as String,
  ];
  return parts.isEmpty ? '—' : parts.join(', ');
}
