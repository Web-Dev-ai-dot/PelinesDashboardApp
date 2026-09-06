import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/models/admin_session.dart';
import '../../auth/providers/auth_providers.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../providers/order_alerts_controller.dart';
import '../providers/orders_providers.dart';

class OrderAlertShell extends ConsumerStatefulWidget {
  const OrderAlertShell({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<OrderAlertShell> createState() => _OrderAlertShellState();
}

class _OrderAlertShellState extends ConsumerState<OrderAlertShell>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _isResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isResumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (_isResumed) _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isResumed = state == AppLifecycleState.resumed;
    if (_isResumed) {
      _startPolling();
      unawaited(ref.read(todayOrdersProvider.notifier).refresh());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(ref.read(todayOrdersProvider.notifier).refresh()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Location?> location = ref.watch(currentLocationProvider);
    ref.watch(todayOrdersProvider);
    final AsyncValue<OrderAlertsState> alerts = ref.watch(orderAlertsProvider);

    ref.listen<AsyncValue<TodayOrdersState>>(todayOrdersProvider, (_, next) {
      final Location? selected = ref.read(currentLocationProvider).value;
      final TodayOrdersState? snapshot = next.value;
      if (selected == null ||
          snapshot == null ||
          snapshot.isRefreshing ||
          snapshot.refreshError != null) {
        return;
      }
      unawaited(
        ref
            .read(orderAlertsProvider.notifier)
            .processSnapshot(
              locationId: selected.id,
              orders: snapshot.orders,
              mayPlaySound: _isResumed,
            ),
      );
    });
    ref.listen<AsyncValue<AdminSession?>>(authControllerProvider, (
      previous,
      next,
    ) {
      if (previous?.value != null && next.value == null) {
        ref.read(orderAlertsProvider.notifier).clearMemory();
      }
    });

    final OrderAlertsState? alertState = alerts.value;
    final bool showBanner =
        location.value?.id == alertState?.locationId &&
        (alertState?.unseenCount ?? 0) > 0;
    return Stack(
      children: <Widget>[
        widget.child,
        if (showBanner)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.topCenter,
                child: _NewOrdersBanner(
                  count: alertState!.unseenCount,
                  onView: () =>
                      context.push('/app/orders/${alertState.unseenIds.first}'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NewOrdersBanner extends StatelessWidget {
  const _NewOrdersBanner({required this.count, required this.onView});

  final int count;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      key: const Key('new-orders-banner'),
      elevation: 6,
      color: colors.primaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.notifications_active_outlined,
              color: colors.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    count == 1 ? 'New order' : 'New orders',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    count == 1
                        ? '1 order needs your attention.'
                        : '$count orders need your attention.',
                  ),
                ],
              ),
            ),
            TextButton(
              key: const Key('view-new-order'),
              onPressed: onView,
              child: const Text('View'),
            ),
          ],
        ),
      ),
    );
  }
}
