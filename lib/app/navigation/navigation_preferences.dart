import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class NavigationPreferencesStore {
  Future<bool?> readCollapsed();
  Future<void> writeCollapsed(bool collapsed);
}

class LocalNavigationPreferencesStore implements NavigationPreferencesStore {
  static const key = 'admin_navigation_collapsed';
  @override
  Future<bool?> readCollapsed() async =>
      (await SharedPreferences.getInstance()).getBool(key);
  @override
  Future<void> writeCollapsed(bool collapsed) async {
    await (await SharedPreferences.getInstance()).setBool(key, collapsed);
  }
}

final navigationPreferencesStoreProvider = Provider<NavigationPreferencesStore>(
  (ref) => LocalNavigationPreferencesStore(),
);
final navigationCollapsedProvider =
    NotifierProvider<NavigationCollapsedController, bool?>(
      NavigationCollapsedController.new,
    );

/// Null preserves the adaptive default until the user makes a manual choice.
class NavigationCollapsedController extends Notifier<bool?> {
  int _revision = 0;
  Future<void> _writes = Future<void>.value();
  @override
  bool? build() {
    final store = ref.watch(navigationPreferencesStoreProvider);
    final revision = _revision;
    Future<void>(() async {
      try {
        final saved = await store.readCollapsed();
        if (ref.mounted && revision == _revision) state = saved;
      } catch (_) {
        // Local storage failure must not block navigation.
      }
    });
    return null;
  }

  Future<void> select(bool collapsed) {
    _revision++;
    state = collapsed;
    final store = ref.read(navigationPreferencesStoreProvider);
    return _writes = _writes.then((_) async {
      try {
        await store.writeCollapsed(collapsed);
      } catch (_) {
        // Retain the visible session preference if storage is unavailable.
      }
    });
  }
}
