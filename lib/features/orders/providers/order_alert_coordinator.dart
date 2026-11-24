import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/order_alert_sound.dart';
import '../models/order_models.dart';
import 'order_alerts_controller.dart';

final orderAlertCoordinatorProvider = Provider<OrderAlertCoordinator>((ref) {
  final coordinator = OrderAlertCoordinator(ref.read(orderAlertSoundProvider));
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

class _AlertBudget {
  DateTime? deadline;
  bool muted = false;
  bool resolved = false;
  bool played = false;
  bool repeating = false;
}

/// One foreground owner, one finite native pulse, and one scheduling timer.
/// Budgets survive presentation rebuilds and lifecycle transitions.
class OrderAlertCoordinator {
  OrderAlertCoordinator(this.sound, {DateTime Function()? now})
    : _now = now ?? _monotonicClock();

  static DateTime Function() _monotonicClock() {
    final origin = DateTime.now();
    final elapsed = Stopwatch()..start();
    return () {
      final monotonic = origin.add(elapsed.elapsed);
      final wall = DateTime.now();
      // Include device sleep, without extending a budget if wall time moves back.
      return wall.isAfter(monotonic) ? wall : monotonic;
    };
  }

  static const cadence = Duration(seconds: 4);
  static const budget = Duration(minutes: 2);
  static const queuePause = Duration(seconds: 2);
  final OrderAlertSound sound;
  final DateTime Function() _now;
  final Map<(String, String), _AlertBudget> _budgets = {};
  (String, String)? _current;
  Timer? _timer;
  int _generation = 0;
  bool _foreground = true;
  bool _verified = false;
  bool _disposed = false;
  bool _playInFlight = false;
  bool _confirmation = false;
  DateTime? _nextPulse;
  DateTime? _nextOrderAt;
  void Function()? _nextOrder;

  int get generation => _generation;
  String? get orderId => _current?.$2;
  String? get locationId => _current?.$1;
  bool get hasTimer => _timer?.isActive ?? false;
  _AlertBudget? get _entry => _budgets[_current];

  void present(String location, String order) {
    if (_disposed || _current == (location, order)) return;
    dismiss();
    _current = (location, order);
    _budgets.putIfAbsent(_current!, _AlertBudget.new);
  }

  /// Call only with a successful canonical detail, obtained in this generation.
  void verify(int token, {required bool needsDecision, required bool paid}) {
    if (_disposed || token != _generation || !_foreground) return;
    final entry = _entry;
    if (entry == null || entry.resolved) return;
    _verified = true;
    if (!paid || (entry.repeating && !needsDecision)) {
      resolve();
      return;
    }
    entry.repeating = needsDecision;
    if (entry.muted || _confirmation) return;
    if (entry.played && !entry.repeating) return;
    entry.deadline ??= _now().add(budget);
    _arm();
  }

  void reconcile(String location, List<OrderSummary> orders) {
    if (_current == null || locationId != location) return;
    final order = orders.where((o) => o.id == orderId).firstOrNull;
    if (order == null ||
        !order.paymentStatus.isPaid ||
        (order.status != OrderStatus.pending &&
            (order.status != OrderStatus.confirmed ||
                _entry?.repeating == true))) {
      resolve();
    }
  }

  void mute() {
    if (_entry == null) return;
    _entry?.muted = true;
    _cancel();
  }

  void beginConfirmation() {
    if (_entry == null) return;
    _confirmation = true;
    _cancel();
  }

  void endConfirmation({required bool confirmed}) {
    if (_entry == null) return;
    _confirmation = false;
    if (confirmed) {
      mute();
    } else {
      _nextPulse = _now().add(queuePause);
      _arm();
    }
  }

  void resolve() {
    if (_entry == null) return;
    _entry?.resolved = true;
    _cancel();
  }

  void suspend() {
    _foreground = false;
    _verified = false;
    _cancel();
  }

  void resume() {
    if (_disposed) return;
    _foreground = true;
    // Current order needs a fresh canonical verification before any pulse.
    _verified = false;
    _armNextOrder();
  }

  void advance(void Function() next) {
    dismiss();
    _nextOrder = next;
    _nextOrderAt = _now().add(queuePause);
    _armNextOrder();
  }

  void _armNextOrder() {
    if (!_foreground || _disposed || _nextOrder == null) return;
    _timer?.cancel();
    final token = _generation;
    final delay = _nextOrderAt!.difference(_now());
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _timer = null;
      if (token != _generation || !_foreground || _disposed) return;
      final next = _nextOrder;
      _nextOrder = null;
      _nextOrderAt = null;
      next?.call();
    });
  }

  void dismiss() {
    _cancel();
    _current = null;
    _verified = false;
    _confirmation = false;
    _nextPulse = null;
    _nextOrder = null;
    _nextOrderAt = null;
  }

  void logout() {
    dismiss();
    _budgets.clear();
  }

  bool get _canPlay {
    final entry = _entry;
    return !_disposed &&
        _foreground &&
        _verified &&
        !_confirmation &&
        entry != null &&
        !entry.muted &&
        !entry.resolved &&
        entry.deadline != null &&
        _now().isBefore(entry.deadline!) &&
        (!entry.played || entry.repeating);
  }

  void _arm() {
    if (!_canPlay || hasTimer || _playInFlight) return;
    final deadline = _entry!.deadline!;
    final due = _nextPulse ?? _now();
    final target = due.isBefore(deadline) ? due : deadline;
    final delay = target.difference(_now());
    final token = _generation;
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _timer = null;
      if (token != _generation || _disposed) return;
      if (!_canPlay) {
        _cancel();
        return;
      }
      unawaited(_pulse(token));
    });
  }

  Future<void> _pulse(int token) async {
    if (!_canPlay || token != _generation || _playInFlight) return;
    _playInFlight = true;
    _entry!.played = true;
    _nextPulse = _now().add(cadence);
    try {
      await sound.play(soundCount: _entry!.repeating ? 3 : 1);
    } on Object {
      // Audio and haptics are best-effort, never a prerequisite for UI actions.
    } finally {
      _playInFlight = false;
    }
    if (_disposed || token != _generation) {
      // stop was already dispatched synchronously by the invalidating action.
      // Do not let a late completion recreate an old timer.
      _arm();
      return;
    }
    _arm();
  }

  void _cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    unawaited(_stop());
  }

  Future<void> _stop() async {
    try {
      await sound.stop();
    } on Object {
      // Native lifecycle cleanup is an additional defensive stop.
    }
  }

  void dispose() {
    if (_disposed) return;
    dismiss();
    _disposed = true;
    _budgets.clear();
  }
}
