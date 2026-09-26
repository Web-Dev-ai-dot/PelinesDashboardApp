import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/api/api_exception.dart';
import '../../locations/models/location.dart';
import '../models/order_models.dart';
import '../models/order_status_action.dart';
import '../providers/order_alerts_controller.dart';
import '../providers/order_alert_coordinator.dart';
import '../providers/orders_providers.dart';
import 'cancel_order_action.dart';
import 'order_parity_content.dart';
import '../../../app/theme/app_theme.dart';

// Prevents an already-open Detail beneath the modal from acknowledging a new
// alert merely because the canonical provider refreshes that hidden screen.
final fullscreenOrderAlertVisibleProvider =
    NotifierProvider<FullscreenAlertVisibility, bool>(
      FullscreenAlertVisibility.new,
    );

class FullscreenAlertVisibility extends Notifier<bool> {
  @override
  bool build() => false;

  void setVisible(bool value) {
    if (ref.mounted) state = value;
  }
}

/// Pins the current ID even when a new snapshot removes it from unseenIds.
/// Only the explicit completion callback advances the presentation queue.
class NewOrderAlertQueue extends ConsumerStatefulWidget {
  const NewOrderAlertQueue({
    required this.location,
    required this.onEmpty,
    super.key,
  });
  final Location location;
  final VoidCallback onEmpty;
  @override
  ConsumerState<NewOrderAlertQueue> createState() => _NewOrderAlertQueueState();
}

class _NewOrderAlertQueueState extends ConsumerState<NewOrderAlertQueue> {
  String? _current;
  bool _advancing = false;

  Future<void> _complete() async {
    if (_advancing || _current == null) return;
    _advancing = true;
    final feedback = ref.read(orderAlertCoordinatorProvider);
    feedback.mute();
    await ref.read(orderAlertsProvider.notifier).acknowledge(_current!);
    if (!mounted) return;
    if (feedback.locationId != widget.location.id ||
        feedback.orderId != _current) {
      return;
    }
    final alerts = ref.read(orderAlertsProvider).value;
    final ids = alerts?.locationId == widget.location.id
        ? alerts!.unseenIds
        : <String>[];
    if (ids.isEmpty) {
      widget.onEmpty();
    } else {
      feedback.advance(() {
        if (!mounted) return;
        final latest = ref.read(orderAlertsProvider).value;
        final remaining = latest?.locationId == widget.location.id
            ? latest!.unseenIds
            : <String>[];
        if (remaining.isEmpty) {
          widget.onEmpty();
          return;
        }
        setState(() {
          _current = remaining.first;
          _advancing = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(orderAlertsProvider).value;
    final ids = alerts?.locationId == widget.location.id
        ? alerts!.unseenIds
        : <String>[];
    _current ??= ids.firstOrNull;
    return PopScope(
      canPop: false,
      child: _current == null
          ? const SizedBox.shrink()
          : _NewOrderDecision(
              key: ValueKey(_current),
              orderId: _current!,
              location: widget.location,
              count: 1 + ids.where((id) => id != _current).length,
              onComplete: _complete,
            ),
    );
  }
}

class _NewOrderDecision extends ConsumerStatefulWidget {
  const _NewOrderDecision({
    required this.orderId,
    required this.location,
    required this.count,
    required this.onComplete,
    super.key,
  });
  final String orderId;
  final Location location;
  final int count;
  final Future<void> Function() onComplete;
  @override
  ConsumerState<_NewOrderDecision> createState() => _NewOrderDecisionState();
}

class _NewOrderDecisionState extends ConsumerState<_NewOrderDecision> {
  OrderDetail? _order;
  Object? _error;
  bool _loading = true;
  bool _acting = false;
  bool _completed = false;
  bool _requiresRefresh = false;
  bool _refreshOnCompletion = false;
  late final OrderAlertCoordinator _feedback;

  @override
  void initState() {
    super.initState();
    _feedback = ref.read(orderAlertCoordinatorProvider);
    _feedback.present(widget.location.id, widget.orderId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (_acting || ref.read(orderMutationProvider(widget.orderId)).isBusy) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = _feedback.generation;
    // Observe the first GET result, including an error while Riverpod schedules
    // a read retry. Awaiting provider.future alone hides those errors from UI.
    final result = Completer<OrderDetail>();
    ref.invalidate(orderDetailProvider(widget.orderId));
    final subscription = ref.listenManual<AsyncValue<OrderDetail>>(
      orderDetailProvider(widget.orderId),
      (_, next) {
        if (result.isCompleted) return;
        if (next.hasError && !next.isLoading) {
          result.completeError(next.error!, next.stackTrace);
        } else if (!next.isLoading && next.value != null) {
          result.complete(next.value!);
        }
      },
      fireImmediately: true,
    );
    try {
      final order = await result.future;
      if (!mounted) return;
      if (order.id != widget.orderId) {
        throw const ApiException(message: 'Unable to verify order identity.');
      }
      ref
          .read(orderMutationProvider(widget.orderId).notifier)
          .adoptRefreshedOrder(order);
      setState(() {
        _order = order;
        _requiresRefresh = false;
      });
      if (_feedback.orderId == widget.orderId &&
          order.locationId == widget.location.id) {
        _feedback.verify(
          token,
          needsDecision:
              OrderStatusAction.forOrder(order.status, order.fulfillmentType) ==
              OrderStatusAction.acceptOrder,
          paid: order.paymentStatus.isOperationallyPaid,
        );
      }
    } on Object catch (error) {
      if (mounted &&
          token == _feedback.generation &&
          _feedback.orderId == widget.orderId &&
          error is ApiException &&
          error.statusCode == 404) {
        _feedback.resolve();
      }
      if (mounted) setState(() => _error = error);
    } finally {
      subscription.close();
      if (mounted) setState(() => _loading = false);
      if (mounted && _refreshOnCompletion) {
        _refreshOnCompletion = false;
        unawaited(_refresh());
      }
    }
  }

  Future<void> _finish() async {
    if (_completed) return;
    _feedback.mute();
    _completed = true;
    await widget.onComplete();
  }

  Future<void> _accept(OrderDetail order) async {
    if (_completed || _acting || _loading) return;
    _feedback.mute();
    setState(() => _acting = true);
    try {
      await ref
          .read(orderMutationProvider(widget.orderId).notifier)
          .acceptOrder(order);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mutation = ref.watch(orderMutationProvider(widget.orderId));
    final notes = ref.watch(orderNotesProvider(widget.orderId));
    ref.listen<OrderMutationState>(orderMutationProvider(widget.orderId), (
      previous,
      next,
    ) {
      if (next.phase == OrderMutationPhase.error) {
        setState(() => _requiresRefresh = true);
      }
      if (next.phase == OrderMutationPhase.success &&
          next.canonicalOrder != null &&
          next.action != null &&
          next.canonicalOrder!.status == next.action!.target) {
        _feedback.resolve();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_finish());
        });
      }
    });
    ref.listen<AsyncValue<TodayOrdersState>>(todayOrdersProvider, (_, next) {
      if (next.value != null &&
          !next.value!.isRefreshing &&
          next.value!.refreshError == null &&
          !_loading) {
        unawaited(_refresh());
      }
    });
    ref.listen<int>(appResumeTickProvider, (_, _) {
      if (_loading) {
        _refreshOnCompletion = true;
      } else {
        unawaited(_refresh());
      }
    });
    final order = mutation.canonicalOrder ?? _order;
    final busy = _loading || _acting || mutation.isBusy || notes.isBusy;
    final missing =
        _error is ApiException && (_error as ApiException).statusCode == 404;
    final safe =
        !_requiresRefresh &&
        !_loading &&
        _error == null &&
        order != null &&
        order.locationId == widget.location.id;
    final needsDecision =
        safe &&
        order.paymentStatus.isOperationallyPaid &&
        OrderStatusAction.forOrder(order.status, order.fulfillmentType) ==
            OrderStatusAction.acceptOrder;
    final canCancel =
        needsDecision &&
        ref.watch(orderCancellationEnabledProvider) &&
        OrderStatusAction.canCancel(order);
    final canAcknowledge =
        !_completed && !busy && (missing || (safe && !needsDecision));
    final canDefer =
        !_completed && !busy && !_requiresRefresh && (safe || missing);
    return Scaffold(
      key: const Key('new-order-fullscreen'),
      backgroundColor: PelinesColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(PelinesSpacing.md),
              child: Row(
                children: [
                  const Icon(
                    Icons.notifications_active_outlined,
                    color: PelinesColors.brandPrimary,
                  ),
                  const SizedBox(width: PelinesSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(context, 'New Order'),
                          style: PelinesTypography.sectionTitle(
                            Theme.of(context).textTheme,
                          ),
                        ),
                        Text('1 ${tr(context, 'of')} ${widget.count}'),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('alert-mute'),
                    tooltip: tr(context, 'Mute'),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: const Icon(Icons.volume_off_outlined, size: 20),
                    onPressed: _feedback.mute,
                  ),
                  IconButton(
                    key: const Key('alert-defer'),
                    tooltip: tr(context, 'Decide later'),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: canDefer
                        ? () {
                            // Acknowledge this local alert only. Never resolve
                            // an order or hide an in-flight/uncertain mutation.
                            final current = ref.read(
                              orderMutationProvider(widget.orderId),
                            );
                            if (_completed ||
                                _acting ||
                                _loading ||
                                _requiresRefresh ||
                                current.isBusy ||
                                current.phase == OrderMutationPhase.error ||
                                ref
                                    .read(orderNotesProvider(widget.orderId))
                                    .isBusy) {
                              return;
                            }
                            unawaited(_finish());
                          }
                        : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(PelinesSpacing.md),
                child: PelinesPageBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_loading || mutation.isBusy)
                        const LinearProgressIndicator(),
                      if (mutation.isBusy)
                        Text(tr(context, 'Verifying order update…')),
                      if (order != null) ...[
                        NewOrderParityContent(
                          order: order,
                          locationName: widget.location.name,
                        ),
                        if (!order.paymentStatus.isOperationallyPaid)
                          Text(
                            tr(
                              context,
                              'Payment is not operationally paid. This order cannot be processed.',
                            ),
                          ),
                        if (order.locationId != widget.location.id)
                          Text(
                            tr(
                              context,
                              'Location context changed. Refresh to verify this order.',
                            ),
                          ),
                      ],
                      if (_error != null)
                        Text(
                          missing
                              ? tr(context, 'Order no longer available')
                              : tr(
                                  context,
                                  'Unable to verify the current order. Refresh to try again.',
                                ),
                        ),
                      if (_requiresRefresh)
                        Text(
                          tr(
                            context,
                            'Refresh to verify the final order state.',
                          ),
                        ),
                      if (mutation.message != null)
                        Text(
                          mutation.message!,
                          key: const Key('alert-mutation-message'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(PelinesSpacing.md),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final buttons = <Widget>[
                    if (needsDecision)
                      FilledButton(
                        key: const Key('alert-accept'),
                        style:
                            PelinesControlStyles.button(
                              PelinesButtonVariant.accept,
                            ).copyWith(
                              minimumSize: const WidgetStatePropertyAll(
                                Size(48, 56),
                              ),
                            ),
                        onPressed: busy || _completed
                            ? null
                            : () => _accept(order),
                        child: PelinesButtonLabel(
                          busy: busy,
                          label: busy
                              ? tr(context, 'Accepting?')
                              : tr(context, 'Accept'),
                        ),
                      ),
                    if (canAcknowledge)
                      FilledButton(
                        key: const Key('alert-acknowledge'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                        onPressed: _finish,
                        child: Text(tr(context, 'Acknowledge')),
                      ),
                    if (canCancel)
                      CancelOrderAction(
                        order: order,
                        busy: busy || _completed,
                        expanded: true,
                        onConfirmationOpened: _feedback.beginConfirmation,
                        onConfirmationClosed: (confirmed) {
                          if (_feedback.orderId == widget.orderId &&
                              _feedback.locationId == widget.location.id) {
                            _feedback.endConfirmation(confirmed: confirmed);
                          }
                        },
                      ),
                    TextButton(
                      key: const Key('alert-refresh'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: busy ? null : _refresh,
                      child: Text(tr(context, 'Refresh')),
                    ),
                  ];
                  final wide =
                      constraints.maxWidth >=
                      600 * MediaQuery.textScalerOf(context).scale(1);
                  return wide
                      ? Row(
                          children: [
                            for (var i = 0; i < buttons.length; i++) ...[
                              if (i > 0)
                                const SizedBox(width: PelinesSpacing.sm),
                              Expanded(flex: i == 0 ? 2 : 1, child: buttons[i]),
                            ],
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < buttons.length; i++) ...[
                              if (i > 0)
                                const SizedBox(height: PelinesSpacing.xs),
                              buttons[i],
                            ],
                          ],
                        );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
