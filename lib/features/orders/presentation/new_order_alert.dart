import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/api/api_exception.dart';
import '../../auth/providers/auth_providers.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
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

/// Presentation only. At short heights (including an open keyboard), the whole
/// sheet scrolls; otherwise the header and decision actions remain in view.
class _AlertSheetLayout extends StatelessWidget {
  const _AlertSheetLayout({
    required this.header,
    required this.content,
    required this.actions,
  });
  final Widget header, content, actions;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('new-order-bottom-sheet'),
    color: PelinesColors.card,
    child: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight <
              300 * MediaQuery.textScalerOf(context).scale(1)) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [header, content, const Divider(height: 1), actions],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(child: SingleChildScrollView(child: content)),
              const Divider(height: 1),
              actions,
            ],
          );
        },
      ),
    ),
  );
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

class _NewOrderDecisionState extends ConsumerState<_NewOrderDecision>
    with WidgetsBindingObserver {
  OrderDetail? _order;
  Object? _error;
  bool _loading = true;
  bool _acting = false;
  bool _completed = false;
  bool _requiresRefresh = false;
  bool _refreshOnCompletion = false;
  final Object _session = Object();
  int _request = 0;
  bool _requestInFlight = false;
  bool _foreground = true;
  OrderStatus? _initialCanonicalStatus;
  OrderStatusAction? _localAction;
  bool _localRequestSent = false;
  bool _localSuccess = false;
  final _cancelKey = GlobalKey<CancelOrderActionState>();
  late final OrderAlertCoordinator _feedback;

  bool get _active =>
      mounted &&
      !_completed &&
      ref.read(currentLocationProvider).value?.id == widget.location.id &&
      ref.read(orderAlertsProvider).value?.locationId == widget.location.id &&
      _feedback.orderId == widget.orderId &&
      _feedback.locationId == widget.location.id;

  bool _owns(Object session, int request) =>
      identical(session, _session) &&
      request == _request &&
      _active &&
      _foreground;

  static bool _resolvedStatus(OrderStatus status) =>
      const {OrderStatus.confirmed, OrderStatus.cancelled}.contains(status);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _feedback = ref.read(orderAlertCoordinatorProvider);
    _feedback.present(widget.location.id, widget.orderId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _request++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _request++;
    }
    // The shell's resume tick requests a fresh detail. Its post-frame dispatch
    // runs after all lifecycle observers have updated their foreground state.
  }

  void _finishResolvedDecision() {
    if (!_active || !_foreground || _localSuccess) return;
    _feedback.resolve();
    _cancelKey.currentState?.dismissConfirmation();
    unawaited(_finish());
    setState(() {}); // Hide the completed presentation during the queue pause.
    // Completion does not wait for the list refresh or invent a board move.
    unawaited(ref.read(todayOrdersProvider.notifier).refresh());
    ref.invalidate(orderDetailProvider(widget.orderId));
  }

  Future<void> _refresh() async {
    if (!_active || !_foreground || _localSuccess) {
      return;
    }
    if (_acting || ref.read(orderMutationProvider(widget.orderId)).isBusy) {
      return;
    }
    final request = ++_request;
    if (_requestInFlight) {
      _refreshOnCompletion = true;
      return;
    }
    _requestInFlight = true;
    final session = _session;
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = _feedback.generation;
    try {
      // Own this GET directly: a shared provider refresh must not deliver an
      // older result into a newer presentation request.
      final order = await ref
          .read(ordersRepositoryProvider)
          .getOrderById(widget.orderId);
      if (!_owns(session, request) ||
          ref.read(orderMutationProvider(widget.orderId)).isBusy) {
        return;
      }
      if (order.id != widget.orderId ||
          order.locationId != widget.location.id) {
        throw const ApiException(message: 'Unable to verify order identity.');
      }
      _initialCanonicalStatus ??= order.status;
      final localResolved =
          _localRequestSent && _localAction?.target == order.status;
      ref
          .read(orderMutationProvider(widget.orderId).notifier)
          .adoptRefreshedOrder(order);
      setState(() {
        _order = order;
        _requiresRefresh = false;
      });
      if (localResolved) {
        _localSuccess = true;
        _feedback.resolve();
        await _finish();
        if (mounted) {
          unawaited(ref.read(todayOrdersProvider.notifier).refresh());
        }
        return;
      }
      if (_initialCanonicalStatus == OrderStatus.pending &&
          _resolvedStatus(order.status)) {
        _finishResolvedDecision();
        return;
      }
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
      if (!_owns(session, request)) return;
      if (error is ApiException && error.statusCode == 401) {
        await ref.read(authControllerProvider.notifier).signOut();
        return;
      }
      if (error is ApiException && error.statusCode == 404) {
        _feedback.resolve();
        // A 404 permits explicit acknowledgement; it does not prove a status.
      }
      setState(() {
        _error = error;
      });
    } finally {
      _requestInFlight = false;
      if (mounted) setState(() => _loading = false);
      if (mounted && _refreshOnCompletion) {
        _refreshOnCompletion = false;
        unawaited(_refresh());
      }
    }
  }

  Future<void> _finish() async {
    if (!_active) return;
    _request++;
    _feedback.mute();
    _completed = true;
    await widget.onComplete();
  }

  Future<void> _accept(OrderDetail order) async {
    if (!_active || _acting || _loading) return;
    _feedback.mute();
    setState(() => _acting = true);
    try {
      await ref
          .read(orderMutationProvider(widget.orderId).notifier)
          .acceptOrder(order);
    } finally {
      if (mounted) setState(() => _acting = false);
      if (_active && _refreshOnCompletion) {
        _refreshOnCompletion = false;
        unawaited(_refresh());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mutation = ref.watch(orderMutationProvider(widget.orderId));
    if (_completed &&
        !_localSuccess &&
        _initialCanonicalStatus == OrderStatus.pending &&
        _order != null &&
        _resolvedStatus(_order!.status)) {
      return const SizedBox.shrink();
    }
    final notes = ref.watch(orderNotesProvider(widget.orderId));
    ref.listen<OrderMutationState>(orderMutationProvider(widget.orderId), (
      previous,
      next,
    ) {
      if (!_active) return;
      if (next.isBusy) {
        _request++;
        _localAction = next.action;
        _localRequestSent = ref
            .read(orderMutationProvider(widget.orderId).notifier)
            .statusRequestSent;
      }
      if (next.phase == OrderMutationPhase.error) {
        _localAction = next.action;
        _localRequestSent = ref
            .read(orderMutationProvider(widget.orderId).notifier)
            .statusRequestSent;
        setState(() => _requiresRefresh = true);
      }
      if (next.phase == OrderMutationPhase.success &&
          next.canonicalOrder != null &&
          next.action != null &&
          next.canonicalOrder!.status == next.action!.target) {
        _localSuccess = true;
        _feedback.resolve();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_finish());
        });
      }
      if (previous?.isBusy == true && !next.isBusy && _refreshOnCompletion) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_active && !_acting) {
            _refreshOnCompletion = false;
            unawaited(_refresh());
          }
        });
      }
    });
    ref.listen<AsyncValue<TodayOrdersState>>(todayOrdersProvider, (_, next) {
      if (next.value != null &&
          !next.isLoading &&
          !next.hasError &&
          next.value!.snapshotLocationId == widget.location.id &&
          !next.value!.isRefreshing &&
          next.value!.refreshError == null) {
        unawaited(_refresh());
      }
    });
    ref.listen<int>(appResumeTickProvider, (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_active) unawaited(_refresh());
      });
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
    return _AlertSheetLayout(
      header: Padding(
        padding: const EdgeInsets.all(PelinesSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, 'New order received'),
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
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.volume_off_outlined, size: 20),
              onPressed: _feedback.mute,
            ),
            IconButton(
              key: const Key('alert-defer'),
              tooltip: tr(context, 'Decide later'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
                          ref.read(orderNotesProvider(widget.orderId)).isBusy) {
                        return;
                      }
                      unawaited(_finish());
                    }
                  : null,
            ),
          ],
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.all(PelinesSpacing.md),
        child: PelinesPageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading || mutation.isBusy) const LinearProgressIndicator(),
              if (mutation.isBusy) Text(tr(context, 'Verifying order update…')),
              if (order != null) ...[
                Text(
                  '${tr(context, 'Order')} ${order.orderNumber} · ${tr(context, 'respond to accept or decline')}',
                  style: const TextStyle(color: PelinesColors.textSecondary),
                ),
                const SizedBox(height: 16),
                NewOrderParityContent(
                  order: order,
                  locationName: widget.location.name,
                  locationAddress: widget.location.address,
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
                Text(tr(context, 'Refresh to verify the final order state.')),
              if (mutation.message != null)
                Text(
                  mutation.message!,
                  key: const Key('alert-mutation-message'),
                ),
            ],
          ),
        ),
      ),
      actions: Padding(
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
                        minimumSize: const WidgetStatePropertyAll(Size(48, 56)),
                      ),
                  onPressed: busy || _completed ? null : () => _accept(order),
                  child: PelinesButtonLabel(
                    busy: busy,
                    label: busy
                        ? tr(context, 'Accepting?')
                        : AdminLocalizations.of(context)
                              .text('Accept order', key: 'alert.Accept order'),
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
                  key: _cancelKey,
                  canSubmit: () =>
                      _active &&
                      _foreground &&
                      !_loading &&
                      !_requiresRefresh &&
                      !ref.read(orderMutationProvider(widget.orderId)).isBusy,
                  order: order,
                  busy: busy || _completed,
                  expanded: true,
                  sheetStyle: true,
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
                onPressed: busy || _completed ? null : _refresh,
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
                        if (i > 0) const SizedBox(width: PelinesSpacing.sm),
                        Expanded(flex: i == 0 ? 2 : 1, child: buttons[i]),
                      ],
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < buttons.length; i++) ...[
                        if (i > 0) const SizedBox(height: PelinesSpacing.xs),
                        buttons[i],
                      ],
                    ],
                  );
          },
        ),
      ),
    );
  }
}
