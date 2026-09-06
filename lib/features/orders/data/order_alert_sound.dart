import 'package:flutter/services.dart';

abstract interface class OrderAlertSound {
  Future<void> play();
  Future<void> dispose();
}

class AssetOrderAlertSound implements OrderAlertSound {
  static const MethodChannel _channel = MethodChannel(
    'com.pelines.admin/order_alert_sound',
  );

  @override
  Future<void> play() async {
    try {
      await _channel.invokeMethod<void>('play');
    } on Object {
      // Audio is best-effort; the persistent visual alert remains available.
    }
  }

  @override
  Future<void> dispose() async {}
}
