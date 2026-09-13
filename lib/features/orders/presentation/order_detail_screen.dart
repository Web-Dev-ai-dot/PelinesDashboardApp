import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/time/pelines_time.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../models/order_models.dart';
import '../models/order_status_action.dart';
import '../providers/order_alerts_controller.dart';
import '../providers/orders_providers.dart';
import 'order_ui_helpers.dart';
import 'cancel_order_action.dart';
import 'new_order_alert.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({required this.orderId, super.key});
  final String orderId;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  OrderDetail? _lastOrder;
  int? _lastResumeTick;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ref.read(fullscreenOrderAlertVisibleProvider)) return;
      ref.read(orderAlertsProvider.notifier).acknowledge(widget.orderId);
    });
    final AsyncValue<OrderDetail> detail = ref.watch(
      orderDetailProvider(widget.orderId),
    );
    if (detail.value != null && !identical(_lastOrder, detail.value)) {
      final OrderDetail refreshed = detail.value!;
      _lastOrder = refreshed;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(orderMutationProvider(widget.orderId).notifier)
            .adoptRefreshedOrder(refreshed);
      });
    }
    final int resumeTick = ref.watch(appResumeTickProvider);
    if (_lastResumeTick == null) {
      _lastResumeTick = resumeTick;
    } else if (_lastResumeTick != resumeTick) {
      _lastResumeTick = resumeTick;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.invalidate(orderDetailProvider(widget.orderId));
      });
    }
    final OrderNotesState notes = ref.watch(orderNotesProvider(widget.orderId));
    final OrderDetail? displayed = detail.value ?? _lastOrder;

    Future<void> leave() async {
      if (notes.isDirty) {
        final bool discard = await _confirmDiscardNotes(context);
        if (!discard || !context.mounted) return;
        ref.read(orderNotesProvider(widget.orderId).notifier).discardDraft();
        await WidgetsBinding.instance.endOfFrame;
      }
      if (context.mounted) await Navigator.of(context).maybePop();
    }

    return AdminPopScope(
      canPop: !notes.isDirty,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop) await leave();
      },
      child: Scaffold(
        appBar: AdminAppBar(
          leading: BackButton(onPressed: leave),
          title: Text(displayed?.orderNumber ?? 'Order'),
        ),
        body: displayed != null
            ? Column(
                children: <Widget>[
                  if (detail.hasError)
                    MaterialBanner(
                      key: const Key('detail-refresh-warning'),
                      content:  Text(
                        tr(context, 'The latest order status could not be loaded. Showing saved details.'),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => ref.invalidate(
                            orderDetailProvider(widget.orderId),
                          ),
                          child:  Text(tr(context, 'Retry')),
                        ),
                      ],
                    ),
                  Expanded(child: _DetailBody(initialOrder: displayed)),
                ],
              )
            : detail.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object error, StackTrace stack) {
                  final bool missing =
                      error is ApiException && error.statusCode == 404;
                  return _DetailError(
                    message: missing
                        ? tr(context, 'Order no longer available')
                        : error.toString(),
                    onRetry: missing
                        ? null
                        : () => ref.invalidate(
                            orderDetailProvider(widget.orderId),
                          ),
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
            title:  Text(tr(context, 'Discard unsaved notes?')),
            content:  Text(tr(context, 'You have unsaved internal notes.')),
            actions: <Widget>[
              TextButton(
                key: const Key('unsaved-stay'),
                onPressed: () => Navigator.of(context).pop(false),
                child:  Text(tr(context, 'Stay')),
              ),
              FilledButton(
                key: const Key('unsaved-discard'),
                onPressed: () => Navigator.of(context).pop(true),
                child:  Text(tr(context, 'Discard changes')),
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
    final AsyncValue<Location?> currentLocation = ref.watch(
      currentLocationProvider,
    );
    final OrderDetail order = mutation.canonicalOrder ?? initialOrder;
    final bool locationContextChanged =
        currentLocation.value?.id != order.locationId;
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
    final bool cancellationEnabled = ref.watch(
      orderCancellationEnabledProvider,
    );
    final bool canCancel =
        cancellationEnabled && OrderStatusAction.canCancel(order);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        PelinesSpacing.md,
        PelinesSpacing.xs,
        PelinesSpacing.md,
        PelinesSpacing.xxl,
      ),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                order.orderNumber,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontSize: 28),
              ),
            ),
            StatusChip(
              status: order.status,
              fulfillment: order.fulfillmentType,
              rawStatus: order.rawStatus,
            ),
          ],
        ),
        const SizedBox(height: PelinesSpacing.xxs),
        Text(
          'Placed ${PelinesTime.formatDateTime(order.createdAt)}',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: PelinesColors.textSecondary),
        ),
        if (!order.paymentStatus.isOperationallyPaid &&
            !(cancellationEnabled &&
                order.status == OrderStatus.cancelled)) ...<Widget>[
          const SizedBox(height: PelinesSpacing.md),
           _WarningCard(
            icon: Icons.warning_amber_rounded,
            title: tr(context, 'Payment not completed'),
            message: tr(context, 'This order cannot be processed because its payment is not marked as paid.'),
          ),
        ],
        if (locationContextChanged) ...<Widget>[
          const SizedBox(height: PelinesSpacing.md),
           _WarningCard(
            key: Key('location-context-warning'),
            icon: Icons.location_off_outlined,
            title: tr(context, 'Location context changed'),
            message:
                tr(context, 'This order is read-only until you return to its location.'),
          ),
        ],
        const SizedBox(height: PelinesSpacing.xxs),
        _Section(
          title: tr(context, 'Fulfillment'),
          children: <Widget>[
            _Row(tr(context, 'Requested time'), requestedTime(order.scheduledFor)),
            _Row(tr(context, 'Method'), fulfillmentLabel(order.fulfillmentType)),
            _Row(tr(context, 'Location'), _locationName(order)),
            if (order.fulfillmentType == FulfillmentType.delivery)
              _Row(tr(context, 'Delivery address'), _address(order.deliveryAddress)),
          ],
        ),
        _Section(
          title: tr(context, 'Customer'),
          children: <Widget>[
            _Row(tr(context, 'Name'), order.contactName),
            _Row(tr(context, 'Phone'), order.contactPhone),
            _Row(tr(context, 'Email'), order.contactEmail),
          ],
        ),
        if (order.orderType == OrderType.catering)
          _Section(
            title: tr(context, 'Event'),
            children: <Widget>[
              _Row(tr(context, 'Event name'), _mapString(order.eventDetails, 'eventName')),
              _Row(tr(context, 'Attendees'), _mapValue(order.eventDetails, 'attendees')),
            ],
          ),
        if (order.notes?.trim().isNotEmpty == true)
          _Section(
            title: tr(context, 'Customer Notes'),
            children: <Widget>[Text(order.notes!)],
          ),
        if (cancellationEnabled && order.status == OrderStatus.cancelled)
          _Section(
            title: tr(context, 'Internal notes'),
            children: <Widget>[
              Text(order.internalNotes ?? 'No internal notes'),
            ],
          )
        else
          _InternalNotesEditor(order: order),
        _Section(
          title: tr(context, 'Items'),
          children: order.items.isEmpty
              ?  <Widget>[Text(tr(context, 'No items recorded'))]
              : order.items
                    .map((OrderItem item) => _Item(order: item))
                    .toList(growable: false),
        ),
        _Section(
          title: tr(context, 'Totals'),
          children: <Widget>[
            _MoneyRow(tr(context, 'Subtotal'), order.subtotalCents),
            if (order.discountCents != 0)
              _MoneyRow(
                order.discountCode == null
                    ? tr(context, 'Discount')
                    : 'Discount (${order.discountCode})',
                -order.discountCents,
              ),
            _MoneyRow(tr(context, 'Service fee'), order.serviceFeeCents),
            _MoneyRow(tr(context, 'Delivery fee'), order.deliveryFeeCents),
            _MoneyRow(tr(context, 'Tax'), order.taxCents),
            _MoneyRow(tr(context, 'Tip'), order.tipCents),
            const Divider(),
            _MoneyRow(tr(context, 'Total'), order.totalCents, emphasized: true),
          ],
        ),
        _Section(
          title: tr(context, 'Payment'),
          children: <Widget>[
            _Row(
              tr(context, 'Status'),
              cancellationEnabled
                  ? order.rawPaymentStatus ?? order.paymentStatus.name
                  : order.paymentStatus.name,
            ),
            if (order.cardBrand != null && order.cardLast4 != null)
              _Row(tr(context, 'Card'), '${order.cardBrand} ending in ${order.cardLast4}'),
          ],
        ),
        if (order.printedAt != null || order.deliveredAt != null)
          _Section(
            title: tr(context, 'Operational'),
            children: <Widget>[
              if (order.printedAt != null)
                _Row(tr(context, 'Printed'), PelinesTime.formatDateTime(order.printedAt!)),
              if (order.deliveredAt != null)
                _Row(
                  tr(context, 'Completed'),
                  PelinesTime.formatDateTime(order.deliveredAt!),
                ),
            ],
          ),
        if (canCancel && !locationContextChanged)
          CancelOrderAction(
            order: order,
            busy: mutation.isBusy || notes.isBusy,
          ),
      ],
    );
  }

  String _locationName(OrderDetail order) =>
      _mapString(order.location, 'name') == '—'
      ? order.locationId
      : _mapString(order.location, 'name');
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
      title: tr(context, 'Internal notes'),
      children: <Widget>[
        Text(
          tr(context, 'Private notes for administrators only.'),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: PelinesColors.textSecondary),
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
            hintText: tr(context, 'Add a private note about this order'),
            errorText: notes.isValid
                ? null
                : tr(context, 'Internal notes cannot exceed 5000 characters.'),
            border: const OutlineInputBorder(),
          ),
        ),
        if (notes.hasRemoteConflict) ...<Widget>[
          Text(
            tr(context, 'This note was updated elsewhere. Your draft has been preserved.'),
            key: const Key('notes-conflict-warning'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: PelinesColors.destructive,
              fontWeight: FontWeight.w600,
            ),
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
        PelinesActionBar(
          children: <Widget>[
            if (notes.phase == OrderNotesPhase.saved) ...<Widget>[
               Text(tr(context, 'Saved'), key: Key('notes-saved')),
            ],
            FilledButton(
              key: const Key('save-internal-notes'),
              onPressed: canSave ? _save : null,
              child: PelinesButtonLabel(
                busy: notes.isBusy,
                label: notes.isBusy ? tr(context, 'Saving...') : tr(context, 'Save notes'),
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
              title:  Text(tr(context, 'Replace newer note?')),
              content:  Text(
                tr(context, 'This note was changed by another user. Saving will replace the newer server note with your current draft.'),
              ),
              actions: <Widget>[
                TextButton(
                  key: const Key('notes-conflict-cancel'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child:  Text(tr(context, 'Cancel')),
                ),
                FilledButton(
                  key: const Key('notes-conflict-save'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child:  Text(tr(context, 'Save anyway')),
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

class _WarningCard extends StatelessWidget {
  const _WarningCard({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: PelinesColors.brandPrimarySoft,
      border: Border.all(color: PelinesColors.destructive),
      borderRadius: BorderRadius.circular(PelinesRadius.card),
    ),
    padding: const EdgeInsets.all(PelinesSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: PelinesColors.destructive),
        const SizedBox(width: PelinesSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: PelinesColors.destructive,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: PelinesSpacing.xxs),
              Text(message),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: PelinesSpacing.sm),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(PelinesRadius.card),
      boxShadow: PelinesShadows.subtle,
    ),
    child: Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PelinesRadius.card),
        side: const BorderSide(color: PelinesColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(PelinesSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: PelinesColors.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: PelinesSpacing.sm),
            ...children,
          ],
        ),
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
    padding: const EdgeInsets.symmetric(vertical: PelinesSpacing.xxs),
    child: PelinesLabelValueRow(
      label: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: PelinesColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
      value: Text(value),
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
    padding: const EdgeInsets.symmetric(vertical: PelinesSpacing.xxs),
    child: PelinesLabelValueRow(
      alignValueEnd: true,
      label: Text(
        label,
        style: emphasized
            ? Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)
            : null,
      ),
      value: Text(
        money(cents),
        style: emphasized
            ? Theme.of(context).textTheme.titleLarge?.copyWith(
                color: PelinesColors.brandPrimary,
                fontFamily: PelinesTypography.bodyFamily,
                fontWeight: FontWeight.w700,
              )
            : null,
      ),
    ),
  );
}

class _Item extends StatelessWidget {
  const _Item({required this.order});
  final OrderItem order;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: PelinesSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${order.quantity}× ${order.productName}',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(money(order.lineTotalCents)),
          ],
        ),
        for (final OrderModifier modifier in order.modifiers)
          Padding(
            padding: const EdgeInsets.only(
              left: PelinesSpacing.md,
              top: PelinesSpacing.xxs,
            ),
            child: Text(
              '${modifier.groupName}: ${modifier.optionName}${modifier.priceDeltaCents == 0 ? '' : ' (+${money(modifier.priceDeltaCents)})'}',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: PelinesColors.textSecondary),
            ),
          ),
        if (order.notes?.trim().isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(
              left: PelinesSpacing.md,
              top: PelinesSpacing.xxs,
            ),
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
            FilledButton(onPressed: onRetry, child:  Text(tr(context, 'Try again'))),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child:  Text(tr(context, 'Back to Today Orders')),
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
