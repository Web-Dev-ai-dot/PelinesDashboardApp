import 'package:flutter/services.dart';

abstract interface class OrderAlertSound {
  Future<void> play({int soundCount = 1});
  Future<void> stop();
  Future<void> dispose();
}

class AssetOrderAlertSound implements OrderAlertSound {
  static const MethodChannel _channel = MethodChannel(
    'com.pelines.admin/order_alert_sound',
  );

  @override
  Future<void> play({int soundCount = 1}) async {
    try {
      await _channel.invokeMethod<void>('play', {'soundCount': soundCount});
    } on Object {
      // Audio is best-effort; the persistent visual alert remains available.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on Object {
      // A missing platform implementation must never block the decision UI.
    }
  }

  @override
  Future<void> dispose() => stop();
}
