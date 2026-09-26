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
        return null;
      });
      final sound = AssetOrderAlertSound();
      await sound.play(soundCount: 3);
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

  test('native failure or unsupported platform never blocks UI', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    final sound = AssetOrderAlertSound();
    await sound.play();
    await sound.stop();
    await sound.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    await sound.play();
    await sound.stop();
  });
}
