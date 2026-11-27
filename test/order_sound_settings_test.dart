import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/orders/data/order_alert_sound.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_sound_settings.dart';
import 'package:pelines_admin_app/features/orders/providers/order_alert_coordinator.dart';
import 'package:pelines_admin_app/features/orders/providers/order_alerts_controller.dart';

class _Sound implements OrderAlertSound {
  final outcome = Completer<OrderSoundResult>();
  int starts = 0;
  int stops = 0;
  @override
  Future<OrderSoundResult> play({int soundCount = 1, bool test = false}) {
    expect(test, isTrue);
    expect(soundCount, 1);
    starts++;
    return outcome.future;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('button serializes tests and shows the native outcome', (
    tester,
  ) async {
    final sound = _Sound();
    final container = ProviderContainer(
      overrides: [orderAlertSoundProvider.overrideWithValue(sound)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: OrderSoundSettings())),
      ),
    );
    final button = find.widgetWithText(OutlinedButton, 'Test sound');
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(sound.starts, 1);
    sound.outcome.complete(OrderSoundResult.started);
    await tester.pumpAndSettle();
    expect(
      find.text('Sound started. Check that you can hear it.'),
      findsOneWidget,
    );

    final coordinator = container.read(orderAlertCoordinatorProvider);
    coordinator.present('store', 'order');
    final stops = sound.stops;
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(sound.starts, 1);
    expect(sound.stops, stops);
    expect(
      find.text('Wait for the current order alert or sound test to finish.'),
      findsOneWidget,
    );
  });
}
