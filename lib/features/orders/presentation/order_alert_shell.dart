import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'new_order_alert.dart';
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
  RawDialogRoute<void>? _alertRoute;
  NavigatorState? _alertNavigator;
  String? _alertLocation;
  late final FullscreenAlertVisibility _visibility;

  @override
  void initState() {
    super.initState();
    _visibility = ref.read(fullscreenOrderAlertVisibleProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    _isResumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (_isResumed) _startPolling();
    // Seed from an already-loaded snapshot as well as subsequent polling.
    ref.listenManual<AsyncValue<TodayOrdersState>>(
      todayOrdersProvider,
      (_, next) => _processSnapshot(next),
      fireImmediately: true,
    );
    ref.listenManual<AsyncValue<Location?>>(
      currentLocationProvider,
      (_, _) => _processSnapshot(ref.read(todayOrdersProvider)),
      fireImmediately: true,
    );
  }

  void _processSnapshot(AsyncValue<TodayOrdersState> next) {
    final Location? selected = ref.read(currentLocationProvider).value;
    final TodayOrdersState? snapshot = next.value;
    if (selected == null ||
        snapshot == null ||
        next.isLoading ||
        next.hasError ||
        snapshot.snapshotLocationId != selected.id ||
        snapshot.fullLocationSnapshot == null ||
        snapshot.isRefreshing ||
        snapshot.refreshError != null) {
      return;
    }
    unawaited(
      ref
          .read(orderAlertsProvider.notifier)
          .processSnapshot(
            locationId: selected.id,
            orders: snapshot.fullLocationSnapshot!,
            mayPlaySound: _isResumed,
          ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    final route = _alertRoute;
    final navigator = _alertNavigator;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route?.isActive == true && navigator?.mounted == true) {
        navigator!.removeRoute(route!);
      }
      _visibility.setVisible(false);
    });
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
    ref.watch(currentLocationProvider);
    ref.watch(todayOrdersProvider);
    ref.watch(orderAlertsProvider);

    ref.listen<AsyncValue<AdminSession?>>(authControllerProvider, (
      previous,
      next,
    ) {
      if (previous?.value != null && next.value == null) {
        ref.read(orderAlertsProvider.notifier).clearMemory();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _syncAlert());
    return widget.child;
  }

  void _syncAlert() {
    if (!mounted) return;
    final location = ref.read(currentLocationProvider).value;
    final alerts = ref.read(orderAlertsProvider).value;
    if (_alertRoute != null) {
      if (location?.id != _alertLocation ||
          alerts?.locationId != _alertLocation) {
        _closeAlert();
      }
      return;
    }
    if (!_isResumed ||
        location == null ||
        alerts?.locationId != location.id ||
        alerts!.unseenIds.isEmpty) {
      return;
    }
    final container = ProviderScope.containerOf(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = RawDialogRoute<void>(
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => UncontrolledProviderScope(
        container: container,
        child: NewOrderAlertQueue(location: location, onEmpty: _closeAlert),
      ),
    );
    _alertRoute = route;
    _alertLocation = location.id;
    _alertNavigator = navigator;
    _visibility.setVisible(true);
    unawaited(
      navigator.push(route).whenComplete(() {
        if (_alertRoute == route) {
          _alertRoute = null;
          _alertLocation = null;
          _visibility.setVisible(false);
        }
      }),
    );
  }

  void _closeAlert() {
    final route = _alertRoute;
    _alertRoute = null;
    _alertLocation = null;
    _visibility.setVisible(false);
    if (route?.isActive == true && _alertNavigator?.mounted == true) {
      _alertNavigator!.removeRoute(route!);
    }
  }
}
