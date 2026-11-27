import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/orders/data/order_alert_sound.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.pelines.admin/order_alert_sound');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'play and immediate stop use the same native channel; dispose stops',
    () async {
      final calls = <String>[];
      final arguments = <Object?>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        arguments.add(call.arguments);
        return call.method == 'play' ? {'status': 'started'} : null;
      });
      final sound = AssetOrderAlertSound();
      expect(await sound.play(soundCount: 3), OrderSoundResult.started);
      await sound.stop();
      await sound.dispose();
      expect(calls, ['play', 'stop', 'stop']);
      expect(arguments, [
        {'soundCount': 3},
        null,
        null,
      ]);
    },
  );

  test(
    'reports native skip and failure reasons and sends a test flag',
    () async {
      final sound = AssetOrderAlertSound();
      for (final (status, reason, expected) in [
        ('skipped', 'interrupted', OrderSoundStatus.skipped),
        ('failed', 'asset', OrderSoundStatus.failed),
      ]) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.arguments, {'soundCount': 1, 'test': true});
          return {'status': status, 'reason': reason};
        });
        final result = await sound.play(test: true);
        expect(result.status, expected);
        expect(result.reason, reason);
      }
    },
  );

  test('native failure or unsupported platform never blocks UI', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    final sound = AssetOrderAlertSound();
    expect(await sound.play(), OrderSoundResult.unavailable);
    await expectLater(sound.stop(), throwsA(isA<PlatformException>()));
    await sound.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    expect(await sound.play(), OrderSoundResult.unavailable);
    await sound.dispose();
  });
}
