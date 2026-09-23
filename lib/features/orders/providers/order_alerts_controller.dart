import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/order_alert_sound.dart';
import '../data/order_alert_store.dart';
import '../models/order_models.dart';

final orderAlertStoreProvider = Provider<OrderAlertStore>((Ref ref) {
  return SharedPreferencesOrderAlertStore();
});

final orderAlertSoundProvider = Provider<OrderAlertSound>((Ref ref) {
  final OrderAlertSound sound = AssetOrderAlertSound();
  ref.onDispose(() => unawaited(sound.dispose()));
  return sound;
});

final orderAlertsProvider =
    AsyncNotifierProvider<OrderAlertsController, OrderAlertsState>(
      OrderAlertsController.new,
    );

final appResumeTickProvider = NotifierProvider<AppResumeTick, int>(
  AppResumeTick.new,
);

class AppResumeTick extends Notifier<int> {
  @override
  int build() => 0;

  void resumed() => state++;
}

class OrderAlertsState {
  const OrderAlertsState({
    this.locationId,
    this.knownIds = const <String>[],
    this.unseenIds = const <String>[],
    this.version = 0,
  });

  final String? locationId;
  final List<String> knownIds;
  final List<String> unseenIds;
  final int version;

  int get unseenCount => unseenIds.length;
}

class OrderAlertsController extends AsyncNotifier<OrderAlertsState> {
  static const int maxIdsPerLocation = 200;
  Future<void> _serial = Future<void>.value();

  @override
  Future<OrderAlertsState> build() async => const OrderAlertsState();

  Future<void> processSnapshot({
    required String locationId,
    required List<OrderSummary> orders,
    required bool mayPlaySound,
  }) {
    final Completer<void> done = Completer<void>();
    _serial = _serial
        .then((_) async {
          await _processSnapshot(locationId, orders, mayPlaySound);
          done.complete();
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!done.isCompleted) done.completeError(error, stackTrace);
        });
    return done.future;
  }

  Future<void> _processSnapshot(
    String locationId,
    List<OrderSummary> orders,
    bool mayPlaySound,
  ) async {
    final OrderAlertStore store = ref.read(orderAlertStoreProvider);
    final StoredOrderAlerts? stored = await store.read(locationId);
    final bool sameLocation = state.value?.locationId == locationId;
    final List<String> known = sameLocation
        ? List<String>.of(state.value!.knownIds)
        : List<String>.of(stored?.knownIds ?? const <String>[]);
    final List<String> unseen = sameLocation
        ? List<String>.of(state.value!.unseenIds)
        : List<String>.of(stored?.unseenIds ?? const <String>[]);

    final locationOrders = orders.where(
      (order) => order.locationId == locationId,
    );
    final Set<String> operationalIds = locationOrders
        .where(_isOperational)
        .map((OrderSummary order) => order.id)
        .toSet();
    final List<String> eligibleIds = locationOrders
        .where(_isAlertEligible)
        .map((OrderSummary order) => order.id)
        .toList(growable: false);

    final version = sameLocation ? state.value!.version : stored?.version ?? 0;
    if (version < StoredOrderAlerts.fullSnapshotVersion) {
      // Baseline the expanded universe once, retaining the persisted queue.
      known.addAll(eligibleIds);
    } else {
      final Set<String> knownSet = known.toSet();
      final List<String> newIds = eligibleIds
          .where((String id) => !knownSet.contains(id))
          .toList(growable: false);
      known.addAll(newIds);
      unseen.addAll(newIds.where((String id) => !unseen.contains(id)));
      if (newIds.isNotEmpty && mayPlaySound) {
        unawaited(ref.read(orderAlertSoundProvider).play());
      }
    }

    unseen.removeWhere((String id) => !operationalIds.contains(id));
    final OrderAlertsState next = OrderAlertsState(
      locationId: locationId,
      version: StoredOrderAlerts.fullSnapshotVersion,
      // Keep all currently operational IDs; cap only historical IDs. Otherwise
      // a large active snapshot re-alerts evicted IDs on every poll.
      knownIds: [
        ..._bounded(known.where((id) => !operationalIds.contains(id)).toList()),
        ...{...known, ...unseen}.where(operationalIds.contains),
      ],
      unseenIds: unseen.toSet().toList(),
    );
    state = AsyncData<OrderAlertsState>(next);
    try {
      await store.write(
        locationId,
        StoredOrderAlerts(
          knownIds: next.knownIds,
          unseenIds: next.unseenIds,
          version: next.version,
        ),
      );
    } on Object {
      // Persistence failure must not break foreground detection or UI.
    }
  }

  Future<void> acknowledge(String orderId) async {
    final OrderAlertsState? current = state.value;
    final String? locationId = current?.locationId;
    if (current == null ||
        locationId == null ||
        !current.unseenIds.contains(orderId)) {
      return;
    }
    final OrderAlertsState next = OrderAlertsState(
      locationId: locationId,
      knownIds: current.knownIds,
      version: current.version,
      unseenIds: current.unseenIds.where((String id) => id != orderId).toList(),
    );
    state = AsyncData<OrderAlertsState>(next);
    try {
      await ref
          .read(orderAlertStoreProvider)
          .write(
            locationId,
            StoredOrderAlerts(
              knownIds: next.knownIds,
              unseenIds: next.unseenIds,
              version: next.version,
            ),
          );
    } on Object {
      // Acknowledgement remains effective in memory if persistence fails.
    }
  }

  void clearMemory() {
    state = const AsyncData<OrderAlertsState>(OrderAlertsState());
  }

  static bool _isAlertEligible(OrderSummary order) =>
      order.paymentStatus.isOperationallyPaid &&
      (order.status == OrderStatus.pending ||
          order.status == OrderStatus.confirmed);

  static bool _isOperational(OrderSummary order) =>
      order.paymentStatus.isOperationallyPaid &&
      const <OrderStatus>{
        OrderStatus.pending,
        OrderStatus.confirmed,
        OrderStatus.preparing,
        OrderStatus.ready,
      }.contains(order.status);

  static List<String> _bounded(List<String> ids) {
    final List<String> unique = <String>[];
    for (final String id in ids.reversed) {
      if (!unique.contains(id)) unique.add(id);
      if (unique.length == maxIdsPerLocation) break;
    }
    return unique.reversed.toList(growable: false);
  }
}
