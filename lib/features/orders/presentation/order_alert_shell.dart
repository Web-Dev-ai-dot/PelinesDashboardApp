import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/pelines_tokens.dart';
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
      ref.read(appResumeTickProvider.notifier).resumed();
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
              padding: const EdgeInsets.fromLTRB(
                PelinesSpacing.sm,
                PelinesSpacing.xs,
                PelinesSpacing.sm,
                0,
              ),
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
    return Container(
      key: const Key('new-orders-banner'),
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: BoxDecoration(
        color: PelinesColors.brandYellowSoft,
        border: Border.all(color: PelinesColors.brandYellow),
        borderRadius: BorderRadius.circular(PelinesRadius.prominentCard),
        boxShadow: PelinesShadows.prominent,
      ),
      child: Material(
        color: PelinesColors.card.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(PelinesRadius.prominentCard),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            PelinesSpacing.sm,
            PelinesSpacing.xs,
            PelinesSpacing.xs,
            PelinesSpacing.xs,
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: PelinesColors.brandPrimary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  color: PelinesColors.card,
                ),
              ),
              const SizedBox(width: PelinesSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      count == 1 ? 'New order' : 'New orders',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      count == 1
                          ? '1 order needs your attention.'
                          : '$count orders need your attention.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: PelinesColors.textSecondary),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('view-new-order'),
                onPressed: onView,
                style: TextButton.styleFrom(
                  foregroundColor: PelinesColors.brandPrimary,
                  minimumSize: const Size(64, 48),
                ),
                child: const Text('View'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
