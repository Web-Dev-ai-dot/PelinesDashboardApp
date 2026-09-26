import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/orders/data/order_alert_sound.dart';
import 'package:pelines_admin_app/features/orders/providers/order_alert_coordinator.dart';

class _Sound implements OrderAlertSound {
  int plays = 0;
  final soundCounts = <int>[];
  int stops = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  bool fail = false;
  Completer<void>? hold;
  @override
  Future<void> play({int soundCount = 1}) async {
    plays++;
    soundCounts.add(soundCount);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      if (fail) throw StateError('audio/haptics unavailable');
      await hold?.future;
    } finally {
      inFlight--;
    }
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() => stop();
}

void main() {
  late _Sound sound;
  late OrderAlertCoordinator coordinator;
  void setup(WidgetTester tester) {
    sound = _Sound();
    coordinator = OrderAlertCoordinator(sound, now: tester.binding.clock.now);
    addTearDown(coordinator.dispose);
    coordinator.present('location', 'A');
  }

  void verify({bool pending = true}) => coordinator.verify(
    coordinator.generation,
    needsDecision: pending,
    paid: true,
  );

  testWidgets('deadline stops a triple pattern resumed just before 2 minutes', (
    tester,
  ) async {
    setup(tester);
    verify();
    await tester.pump(Duration.zero);
    coordinator.suspend();
    await tester.pump(const Duration(seconds: 119));
    coordinator.resume();
    verify();
    await tester.pump(Duration.zero);
    expect(sound.soundCounts, [3, 3]);
    final stops = sound.stops;
    await tester.pump(const Duration(seconds: 1));
    expect(sound.stops, stops + 1);
    expect(coordinator.hasTimer, isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(sound.plays, 2);
  });

  testWidgets('three-ding cycles, 4 second cadence, hard 2 minute budget', (
    tester,
  ) async {
    setup(tester);
    verify();
    await tester.pump(Duration.zero);
    expect(sound.plays, 1);
    expect(sound.soundCounts, [3]);
    await tester.pump(const Duration(seconds: 3));
    expect(sound.plays, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(sound.plays, 2);
    for (var i = 0; i < 28; i++) {
      coordinator.present('location', 'A');
      verify(); // rebuild/poll/refresh never resets the budget or cadence.
      await tester.pump(const Duration(seconds: 4));
    }
    expect(sound.plays, 30);
    expect(sound.soundCounts, everyElement(3));
    await tester.pump(const Duration(seconds: 4));
    expect(coordinator.hasTimer, isFalse);
    expect(sound.plays, 30);
    verify();
    await tester.pump(const Duration(minutes: 5));
    expect(sound.plays, 30);
    expect(coordinator.orderId, 'A');
  });

  testWidgets('Mute stays muted through refresh and resume', (tester) async {
    setup(tester);
    verify();
    await tester.pump(Duration.zero);
    final stops = sound.stops;
    coordinator.mute();
    expect(sound.stops, stops + 1);
    expect(coordinator.orderId, 'A');
    coordinator.suspend();
    coordinator.resume();
    verify();
    await tester.pump(const Duration(seconds: 20));
    expect(sound.plays, 1);
    expect(coordinator.hasTimer, isFalse);
  });

  testWidgets('Keep Order pauses 2 seconds without resetting deadline', (
    tester,
  ) async {
    setup(tester);
    verify();
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(seconds: 115));
    coordinator.beginConfirmation();
    final plays = sound.plays;
    coordinator.endConfirmation(confirmed: false);
    await tester.pump(const Duration(seconds: 1));
    expect(sound.plays, plays);
    await tester.pump(const Duration(seconds: 1));
    expect(sound.plays, plays + 1);
    await tester.pump(const Duration(seconds: 3));
    expect(coordinator.hasTimer, isFalse);
  });

  testWidgets('confirmed cancel stays muted; autoaccepted only pulses once', (
    tester,
  ) async {
    setup(tester);
    verify(pending: false);
    await tester.pump(Duration.zero);
    expect(sound.soundCounts, [1]);
    verify(pending: false);
    await tester.pump(const Duration(seconds: 15));
    expect(sound.plays, 1);
    expect(coordinator.hasTimer, isFalse);
    coordinator.present('location', 'B');
    verify();
    await tester.pump(Duration.zero);
    coordinator.beginConfirmation();
    coordinator.endConfirmation(confirmed: true);
    verify();
    await tester.pump(const Duration(seconds: 10));
    expect(sound.plays, 2);
  });

  testWidgets(
    'background invalidates verification; resume keeps original deadline',
    (tester) async {
      setup(tester);
      verify();
      await tester.pump(Duration.zero);
      final old = coordinator.generation;
      coordinator.suspend();
      await tester.pump(const Duration(seconds: 110));
      coordinator.resume();
      coordinator.verify(old, needsDecision: true, paid: true);
      await tester.pump(Duration.zero);
      expect(sound.plays, 1);
      verify();
      await tester.pump(Duration.zero);
      expect(sound.plays, 2);
      await tester.pump(const Duration(seconds: 10));
      expect(coordinator.hasTimer, isFalse);
      coordinator.suspend();
      coordinator.resume();
      verify();
      await tester.pump(Duration.zero);
      expect(sound.plays, 4); // Cycles at 0, 110, 114 and 118 seconds only.
    },
  );

  testWidgets('one timer, late play completion cannot revive muted session', (
    tester,
  ) async {
    setup(tester);
    sound.hold = Completer<void>();
    verify();
    await tester.pump(Duration.zero);
    for (var i = 0; i < 10; i++) {
      verify();
    }
    await tester.pump(const Duration(seconds: 20));
    expect(sound.plays, 1);
    coordinator.mute();
    sound.hold!.complete();
    await tester.pump(Duration.zero);
    expect(coordinator.hasTimer, isFalse);
    expect(sound.maxInFlight, 1);
  });

  testWidgets('A B C transition uses one timer and a fresh budget per order', (
    tester,
  ) async {
    setup(tester);
    verify();
    await tester.pump(Duration.zero);
    coordinator.advance(() {
      coordinator.present('location', 'B');
      verify();
    });
    expect(coordinator.hasTimer, isTrue);
    coordinator
        .mute(); // Always accessible Mute cannot strand queue transition.
    await tester.pump(const Duration(seconds: 1));
    expect(sound.plays, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(coordinator.orderId, 'B');
    expect(sound.plays, 2);
    coordinator.advance(() {
      coordinator.present('location', 'C');
      verify();
    });
    coordinator.suspend();
    await tester.pump(const Duration(seconds: 3));
    expect(sound.plays, 2);
    coordinator.resume();
    await tester.pump(Duration.zero);
    expect(coordinator.orderId, 'C');
    expect(sound.plays, 3);
    expect(sound.maxInFlight, 1);
    coordinator.dispose();
  });

  for (final action in ['logout', 'location', 'dispose', 'resolved']) {
    testWidgets('$action stops and rejects old callbacks', (tester) async {
      setup(tester);
      verify();
      await tester.pump(Duration.zero);
      final token = coordinator.generation;
      switch (action) {
        case 'logout':
          coordinator.logout();
        case 'location':
          coordinator.dismiss();
        case 'dispose':
          coordinator.dispose();
        case 'resolved':
          coordinator.resolve();
      }
      coordinator.verify(token, needsDecision: true, paid: true);
      await tester.pump(const Duration(seconds: 10));
      expect(sound.plays, 1);
      expect(coordinator.hasTimer, isFalse);
    });
  }

  testWidgets('play failure remains stoppable and does not duplicate loops', (
    tester,
  ) async {
    setup(tester);
    sound.fail = true;
    verify();
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(seconds: 5));
    expect(sound.plays, 2);
    coordinator.mute();
    expect(coordinator.hasTimer, isFalse);
    expect(sound.maxInFlight, 1);
  });

  testWidgets('late A play completion schedules only verified B', (
    tester,
  ) async {
    setup(tester);
    final oldPlay = Completer<void>();
    sound.hold = oldPlay;
    verify();
    await tester.pump(Duration.zero);
    coordinator.present('location', 'B');
    verify();
    expect(coordinator.hasTimer, isFalse);
    sound.hold = null;
    oldPlay.complete();
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    expect(sound.plays, 2);
    expect(sound.maxInFlight, 1);
    expect(coordinator.orderId, 'B');
    coordinator.dispose();
  });
}
