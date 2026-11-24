import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../app/theme/pelines_order_badges.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/time/pelines_time.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../models/order_models.dart';
import '../models/pickup_order_notes.dart';
import '../models/order_status_action.dart';
import '../providers/order_alerts_controller.dart';
import '../providers/orders_providers.dart';
import 'order_ui_helpers.dart';
import 'order_parity_content.dart';
import 'order_preview_action.dart';
import 'order_refunds.dart';
import '../../../app/theme/app_theme.dart';
import 'cancel_order_action.dart';
import 'todo_print_action.dart';
import 'pickup_instructions.dart';
import '../../locations/presentation/pelines_location_context.dart';
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
  bool _refundSyncStarted = false;

  /// Pulls refunds made in the Stripe dashboard once per opened detail.
  /// Silent: older APIs have no sync endpoint.
  Future<void> _syncRefunds() async {
    try {
      final repository = ref.read(orderRefundsRepositoryProvider);
      if (repository == null) return;
      await repository.syncRefunds(widget.orderId);
    } on Object {
      return;
    }
    if (mounted) ref.invalidate(orderDetailProvider(widget.orderId));
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ref.read(fullscreenOrderAlertVisibleProvider)) return;
      ref.read(orderAlertsProvider.notifier).acknowledge(widget.orderId);
    });
    final AsyncValue<OrderDetail> detail = ref.watch(
      orderDetailProvider(widget.orderId),
    );
    if (!detail.isLoading &&
        !detail.hasError &&
        detail.value != null &&
        !identical(_lastOrder, detail.value)) {
      final OrderDetail refreshed = detail.value!;
      final mutation = ref.read(orderMutationProvider(widget.orderId));
      _lastOrder = refreshed;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final latest = ref.read(orderDetailProvider(widget.orderId));
        if (latest.isLoading ||
            latest.hasError ||
            !identical(latest.value, refreshed) ||
            !identical(
              ref.read(orderMutationProvider(widget.orderId)),
              mutation,
            )) {
          return;
        }
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
    if (!_refundSyncStarted &&
        displayed != null &&
        displayed.supportsRefunds &&
        (displayed.paymentStatus == PaymentStatus.paid ||
            displayed.paymentStatus == PaymentStatus.refunded)) {
      _refundSyncStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncRefunds();
      });
    }

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
        body: SafeArea(
          child: displayed != null
              ? Column(
                  children: <Widget>[
                    if (detail.hasError)
                      MaterialBanner(
                        key: const Key('detail-refresh-warning'),
                        content: Text(
                          tr(
                            context,
                            'The latest order status could not be loaded. Showing saved details.',
                          ),
                        ),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => ref.invalidate(
                              orderDetailProvider(widget.orderId),
                            ),
                            child: Text(tr(context, 'Retry')),
                          ),
                        ],
                      ),
                    Expanded(
                      child: _DetailBody(
                        initialOrder: displayed,
                        onBack: leave,
                      ),
                    ),
                  ],
                )
              : detail.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
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
                  data: (OrderDetail order) =>
                      _DetailBody(initialOrder: order, onBack: leave),
                ),
        ),
      ),
    );
  }

  Future<bool> _confirmDiscardNotes(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text(tr(context, 'Discard unsaved notes?')),
            content: Text(tr(context, 'You have unsaved internal notes.')),
            actions: <Widget>[
              TextButton(
                key: const Key('unsaved-stay'),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(tr(context, 'Stay')),
              ),
              FilledButton(
                key: const Key('unsaved-discard'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(tr(context, 'Discard changes')),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.initialOrder, required this.onBack});
  final OrderDetail initialOrder;
  final VoidCallback onBack;

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
    final pickupNotes = PickupOrderNotes.fromOrder(order);
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 768),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const Key('detail-back'),
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: Text(tr(context, 'Back to orders')),
                  ),
                ),
                PelinesCard(
                  key: const Key('detail-header-card'),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        tr(context, 'Order').toUpperCase(),
                        style: PelinesTypography.smallLabel,
                      ),
                      Text(
                        order.orderNumber,
                        key: const Key('detail-order-number'),
                        style: PelinesTypography.pageTitle(
                          Theme.of(context).textTheme,
                        )?.copyWith(fontSize: 40),
                      ),
                      const SizedBox(height: 8),
                      _DetailHeaderLine(
                        icon: Icons.calendar_today_outlined,
                        text: PelinesTime.formatDateTime(order.createdAt),
                      ),
                      const SizedBox(height: 14),
                      _DetailHeaderLine(
                        icon: Icons.location_on_outlined,
                        text: _locationDescription(order),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          PelinesOrderBadges.fulfillment(
                            fulfillment: order.fulfillmentType,
                            label: tr(
                              context,
                              fulfillmentLabel(order.fulfillmentType),
                            ),
                          ),
                          PelinesOrderBadges.type(
                            type: order.orderType,
                            label: tr(context, orderTypeLabel(order.orderType)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButtonTheme(
                  data: OutlinedButtonThemeData(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: PelinesColors.card,
                      foregroundColor: PelinesColors.textPrimary,
                      disabledBackgroundColor: PelinesColors.card,
                      disabledForegroundColor: PelinesColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 18,
                      ),
                      textStyle: const TextStyle(
                        fontFamily: PelinesTypography.bodyFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: const StadiumBorder(),
                      side: const BorderSide(color: PelinesColors.border),
                    ),
                  ),
                  child: TodoPrintAction(
                    key: ValueKey('detail-print-${order.id}'),
                    order: _summary(order),
                  ),
                ),
                if (!order.paymentStatus.isOperationallyPaid &&
                    !(cancellationEnabled &&
                        order.status == OrderStatus.cancelled)) ...[
                  const SizedBox(height: 16),
                  _WarningCard(
                    icon: Icons.warning_amber_rounded,
                    title: tr(context, 'Payment not completed'),
                    message: tr(
                      context,
                      'This order cannot be processed because its payment is not marked as paid.',
                    ),
                  ),
                ],
                if (locationContextChanged) ...[
                  const SizedBox(height: 16),
                  _WarningCard(
                    key: const Key('location-context-warning'),
                    icon: Icons.location_off_outlined,
                    title: tr(context, 'Location context changed'),
                    message: tr(
                      context,
                      'This order is read-only until you return to its location.',
                    ),
                  ),
                ],
                _Section(
                  sectionKey: const Key('detail-progress'),
                  title: tr(context, 'Update Progress'),
                  trailing: KeyedSubtree(
                    key: const Key('detail-progress-status'),
                    child: PelinesOrderBadges.status(
                      status: order.status,
                      label: tr(
                        context,
                        statusLabel(
                          order.status,
                          order.fulfillmentType,
                          order.rawStatus,
                        ),
                      ),
                    ),
                  ),
                  children: [
                    if (mutation.isBusy) ...[
                      const LinearProgressIndicator(),
                      Text(tr(context, 'Verifying order update…')),
                    ],
                    OrderPreviewAction(
                      order: _summary(initialOrder),
                      webStyle: true,
                      refreshOnSummaryChange: false,
                      useTargetStatusColor: true,
                    ),
                    if (canCancel && !locationContextChanged) ...[
                      const SizedBox(height: 12),
                      CancelOrderAction(
                        order: order,
                        busy: mutation.isBusy || notes.isBusy,
                        expanded: true,
                      ),
                    ],
                  ],
                ),
                _Section(
                  sectionKey: const Key('detail-customer'),
                  title: tr(context, 'Customer'),
                  children: [
                    Text(
                      order.contactName,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_mapString(order.eventDetails, 'eventName') != '—')
                      Text(
                        _mapString(order.eventDetails, 'eventName'),
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final fields = [
                          OrderInfoField(
                            label: tr(context, 'Email'),
                            value: order.contactEmail,
                          ),
                          OrderInfoField(
                            label: tr(
                              context,
                              order.fulfillmentType == FulfillmentType.pickup
                                  ? 'Pickup Contact'
                                  : 'Contact',
                            ),
                            value: order.contactPhone,
                          ),
                        ];
                        return constraints.maxWidth >=
                                560 * MediaQuery.textScalerOf(context).scale(1)
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: fields[0]),
                                  const SizedBox(width: 24),
                                  Expanded(child: fields[1]),
                                ],
                              )
                            : Column(children: fields);
                      },
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: const Key('copy-order-phone'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: order.contactPhone.trim().isEmpty
                            ? null
                            : () async {
                                try {
                                  await Clipboard.setData(
                                    ClipboardData(text: order.contactPhone),
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Semantics(
                                        liveRegion: true,
                                        child: Text(
                                          tr(context, 'Phone copied'),
                                        ),
                                      ),
                                    ),
                                  );
                                } on Object {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        tr(context, 'Could not copy phone'),
                                      ),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.copy_outlined),
                        label: Text(tr(context, 'Copy phone')),
                      ),
                    ),
                  ],
                ),
                _Section(
                  sectionKey: const Key('detail-fulfillment'),
                  title: tr(
                    context,
                    order.fulfillmentType == FulfillmentType.delivery
                        ? 'Delivery Details'
                        : 'Pickup Details',
                  ),
                  children: [
                    OrderInfoField(
                      compact: true,
                      label: tr(
                        context,
                        order.fulfillmentType == FulfillmentType.delivery
                            ? 'Delivery Time'
                            : 'Pickup Time',
                      ),
                      value: orderScheduledLabel(context, order),
                      icon: Icons.schedule,
                    ),
                    if (order.fulfillmentType == FulfillmentType.pickup)
                      OrderInfoField(
                        compact: true,
                        label: tr(context, 'Pickup Location'),
                        value: _locationDescription(order),
                        icon: Icons.location_on_outlined,
                      ),
                    if (order.fulfillmentType == FulfillmentType.delivery)
                      OrderInfoField(
                        compact: true,
                        label: tr(context, 'Delivery address'),
                        value: _address(order.deliveryAddress),
                        icon: Icons.local_shipping_outlined,
                      ),
                    OrderInfoField(
                      compact: true,
                      label: tr(
                        context,
                        order.fulfillmentType == FulfillmentType.pickup
                            ? 'Pickup Contact'
                            : 'Contact',
                      ),
                      value: '${order.contactName}\n${order.contactPhone}',
                      icon: Icons.person_outline,
                    ),
                    if (order.orderType == OrderType.catering) ...[
                      if (_mapString(order.eventDetails, 'eventName') != '—')
                        OrderInfoField(
                          compact: true,
                          label: tr(context, 'Event name'),
                          value: _mapString(order.eventDetails, 'eventName'),
                        ),
                      if (order.eventDetails?['attendees'] is num)
                        OrderInfoField(
                          compact: true,
                          label: tr(context, 'Attendees'),
                          value: _mapValue(order.eventDetails, 'attendees'),
                        ),
                    ],
                    if (order.fulfillmentType == FulfillmentType.pickup)
                      Container(
                        key: const Key('detail-pickup-instructions'),
                        margin: const EdgeInsets.only(top: 8, bottom: 8),
                        padding: const EdgeInsets.only(left: 12),
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: PelinesColors.brandPrimary,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              tr(context, 'Pickup Instructions').toUpperCase(),
                              style: PelinesTypography.smallLabel,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '“${pickupInstructions(context, order.location?['name'] is String ? order.location!['name'] as String : null)}”',
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (pickupNotes.includeUtensils != null)
                      OrderInfoField(
                        compact: true,
                        key: const Key('detail-pickup-utensils'),
                        icon: Icons.restaurant_outlined,
                        label: tr(context, 'Include forks, napkins, etc.'),
                        value: tr(
                          context,
                          pickupNotes.includeUtensils! ? 'Yes' : 'No',
                        ),
                      ),
                  ],
                ),
                _Section(
                  sectionKey: const Key('detail-items-totals'),
                  title: tr(context, 'Items & Totals'),
                  children: [
                    if (order.items.isEmpty)
                      Text(tr(context, 'No items recorded')),
                    for (final item in order.items)
                      OrderParityItem(
                        item: item,
                        compact: true,
                        inlineAmounts: true,
                      ),
                    const Divider(height: 32),
                    _MoneyRow(tr(context, 'Subtotal'), order.subtotalCents),
                    if (order.discountCents != 0)
                      _MoneyRow(
                        order.discountCode == null
                            ? tr(context, 'Discount')
                            : '${tr(context, 'Discount')} (${order.discountCode})',
                        -order.discountCents,
                      ),
                    _MoneyRow(
                      tr(context, 'Pelines Service Fee'),
                      order.serviceFeeCents,
                    ),
                    if (order.fulfillmentType == FulfillmentType.delivery ||
                        order.deliveryFeeCents != 0)
                      _MoneyRow(
                        tr(context, 'Delivery fee'),
                        order.deliveryFeeCents,
                      ),
                    _MoneyRow(tr(context, 'Tax'), order.taxCents),
                    _MoneyRow(tr(context, 'Tip'), order.tipCents),
                    const Divider(
                      height: 32,
                      color: PelinesColors.brandPrimary,
                    ),
                    _MoneyRow(
                      tr(context, 'Total').toUpperCase(),
                      order.totalCents,
                      emphasized: true,
                    ),
                    const SizedBox(height: 12),
                    Column(
                      key: const Key('detail-payment'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!(order.paymentStatus.isPaid &&
                            order.cardBrand?.trim().isNotEmpty == true &&
                            order.cardLast4?.trim().isNotEmpty == true))
                          _Row(
                            tr(context, 'Payment'),
                            order.paymentStatus == PaymentStatus.unknown
                                ? order.rawPaymentStatus ??
                                      tr(context, 'Unknown payment')
                                : tr(
                                    context,
                                    paymentStatusLabel(order.paymentStatus),
                                  ),
                          ),
                        if (order.paymentStatus.isPaid &&
                            order.cardBrand?.trim().isNotEmpty == true &&
                            order.cardLast4?.trim().isNotEmpty == true)
                          Text(
                            '${tr(context, 'Paid with')} ${order.cardBrand} ${tr(context, 'ending in')} ${order.cardLast4}',
                            key: const Key('detail-paid-card'),
                          ),
                      ],
                    ),
                    OrderRefundSection(
                      order: order,
                      enabled:
                          !locationContextChanged &&
                          !mutation.isBusy &&
                          !notes.isBusy,
                    ),
                  ],
                ),
                _Section(
                  title: tr(context, 'Customer Notes'),
                  accent: pickupNotes.customerNotes?.trim().isNotEmpty == true,
                  sectionKey: const Key('detail-customer-notes'),
                  children: [
                    Text(
                      pickupNotes.customerNotes?.trim().isNotEmpty == true
                          ? pickupNotes.customerNotes!
                          : tr(context, 'No customer notes'),
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color:
                            pickupNotes.customerNotes?.trim().isNotEmpty == true
                            ? null
                            : PelinesColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                if (cancellationEnabled &&
                    order.status == OrderStatus.cancelled)
                  _Section(
                    title: tr(context, 'Internal Admin Notes'),
                    children: [
                      Text(
                        order.internalNotes ?? tr(context, 'No internal notes'),
                      ),
                    ],
                  )
                else
                  _InternalNotesEditor(order: order),
                if (order.printedAt != null || order.deliveredAt != null)
                  _Section(
                    title: tr(context, 'Operational'),
                    children: [
                      if (order.printedAt != null)
                        _Row(
                          tr(context, 'Printed'),
                          PelinesTime.formatDateTime(order.printedAt!),
                        ),
                      if (order.deliveredAt != null)
                        _Row(
                          tr(context, 'Completed'),
                          PelinesTime.formatDateTime(order.deliveredAt!),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _locationName(OrderDetail order) => _mapString(order.location, 'name');

  String _locationDescription(OrderDetail order) {
    final address =
        compactLocationStreet(_mapString(order.location, 'address'))?.trim() ??
        '';
    return address.isEmpty || address == '—'
        ? _locationName(order)
        : '${_locationName(order)} · $address';
  }
}

/// Matching metrics keep both header rows aligned, including wrapped text.
class _DetailHeaderLine extends StatelessWidget {
  const _DetailHeaderLine({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: PelinesColors.textPrimary),
      const SizedBox(width: 10),
      Expanded(child: Text(text)),
    ],
  );
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
      title: tr(context, 'Internal Admin Notes'),
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
          decoration: PelinesControlStyles.input(
            hint: tr(context, 'Add a private note about this order'),
            error: notes.isValid
                ? null
                : tr(context, 'Internal notes cannot exceed 5000 characters.'),
          ),
        ),
        if (notes.hasRemoteConflict) ...<Widget>[
          Text(
            tr(
              context,
              'This note was updated elsewhere. Your draft has been preserved.',
            ),
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
                label: notes.isBusy
                    ? tr(context, 'Saving...')
                    : tr(context, 'Save Note'),
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
              title: Text(tr(context, 'Replace newer note?')),
              content: Text(
                tr(
                  context,
                  'This note was changed by another user. Saving will replace the newer server note with your current draft.',
                ),
              ),
              actions: <Widget>[
                TextButton(
                  key: const Key('notes-conflict-cancel'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(tr(context, 'Cancel')),
                ),
                FilledButton(
                  key: const Key('notes-conflict-save'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(tr(context, 'Save anyway')),
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
  const _Section({
    required this.title,
    required this.children,
    this.accent = false,
    this.sectionKey,
    this.trailing,
  });
  final Widget? trailing;
  final String title;
  final List<Widget> children;
  final bool accent;
  final Key? sectionKey;
  @override
  Widget build(BuildContext context) => Padding(
    key: sectionKey,
    padding: const EdgeInsets.only(top: 16),
    child: PelinesCard(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: accent ? const EdgeInsets.only(left: 16) : EdgeInsets.zero,
        decoration: accent
            ? const BoxDecoration(
                border: Border(
                  left: BorderSide(color: PelinesColors.brandPrimary, width: 4),
                ),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (trailing == null)
              Text(
                title,
                style: PelinesTypography.sectionTitle(
                  Theme.of(context).textTheme,
                )?.copyWith(fontSize: 22),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final titleWidget = Text(
                    title,
                    style: PelinesTypography.sectionTitle(
                      Theme.of(context).textTheme,
                    )?.copyWith(fontSize: 22),
                  );
                  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                  if (constraints.maxWidth < 280 * scale) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        titleWidget,
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: trailing!,
                        ),
                      ],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(flex: 3, child: titleWidget),
                      const SizedBox(width: 12),
                      Flexible(flex: 2, child: trailing!),
                    ],
                  );
                },
              ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    ),
  );
}

OrderSummary _summary(OrderDetail order) => OrderSummary(
  id: order.id,
  orderNumber: order.orderNumber,
  locationId: order.locationId,
  orderType: order.orderType,
  status: order.status,
  rawStatus: order.rawStatus,
  paymentStatus: order.paymentStatus,
  fulfillmentType: order.fulfillmentType,
  contactName: order.contactName,
  createdAt: order.createdAt,
  scheduledFor: order.scheduledFor,
  itemCount: order.items.length,
  totalCents: order.totalCents,
);

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
    child: OrderInlineValueRow(
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
            FilledButton(
              onPressed: onRetry,
              child: Text(tr(context, 'Try again')),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(tr(context, 'Back to Today Orders')),
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
