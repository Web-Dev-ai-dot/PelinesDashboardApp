import 'package:flutter/services.dart';

enum OrderSoundStatus { started, skipped, failed }

class OrderSoundResult {
  const OrderSoundResult(this.status, [this.reason]);

  final OrderSoundStatus status;
  final String? reason;

  static const started = OrderSoundResult(OrderSoundStatus.started);
  static const busy = OrderSoundResult(OrderSoundStatus.skipped, 'busy');
  static const inactive = OrderSoundResult(
    OrderSoundStatus.skipped,
    'inactive',
  );
  static const unavailable = OrderSoundResult(
    OrderSoundStatus.failed,
    'unavailable',
  );

  bool get retryable => const {
    'busy',
    'interrupted',
    'inactive',
    'session',
    'playback',
  }.contains(reason);
}

abstract interface class OrderAlertSound {
  Future<OrderSoundResult> play({int soundCount = 1, bool test = false});
  Future<void> stop();
  Future<void> dispose();
}

class AssetOrderAlertSound implements OrderAlertSound {
  static const MethodChannel _channel = MethodChannel(
    'com.pelines.admin/order_alert_sound',
  );

  @override
  Future<OrderSoundResult> play({int soundCount = 1, bool test = false}) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('play', {
        'soundCount': soundCount,
        if (test) 'test': true,
      });
      final reason = result?['reason'];
      return switch ((result?['status'], reason)) {
        ('started', _) => OrderSoundResult.started,
        ('skipped', 'busy') => OrderSoundResult.busy,
        ('skipped', 'inactive') => OrderSoundResult.inactive,
        ('skipped', 'interrupted' || 'devicePolicy') => OrderSoundResult(
          OrderSoundStatus.skipped,
          reason as String,
        ),
        ('failed', 'asset' || 'session' || 'playback') => OrderSoundResult(
          OrderSoundStatus.failed,
          reason as String,
        ),
        _ => OrderSoundResult.unavailable,
      };
    } on Object {
      // Platform exceptions and malformed replies become a safe UI outcome.
      return OrderSoundResult.unavailable;
    }
  }

  @override
  Future<void> stop() async {
    await _channel.invokeMethod<void>('stop');
  }

  @override
  Future<void> dispose() async {
    try {
      await stop();
    } on Object {
      // There is no active UI to report teardown failures to.
    }
  }
}
