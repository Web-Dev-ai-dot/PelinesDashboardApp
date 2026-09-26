import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One local writer for the whole servicePrefsJson object, through reconciliation.
/// Contending actions are disabled/rejected, never queued with a stale draft.
final servicePreferencesWriteProvider =
    NotifierProvider<ServicePreferencesWriteLock, bool>(
      ServicePreferencesWriteLock.new,
    );

class ServicePreferencesWriteLock extends Notifier<bool> {
  @override
  bool build() => false;
  bool tryAcquire() {
    if (state) return false;
    state = true;
    return true;
  }

  void release() => state = false;
}
