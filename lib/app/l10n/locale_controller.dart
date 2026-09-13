import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class LanguageStore {
  Future<String?> read();
  Future<void> write(String language);
}

class PreferencesLanguageStore implements LanguageStore {
  static const key = 'admin_language';
  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String language) async {
    await (await SharedPreferences.getInstance()).setString(key, language);
  }
}

final languageStoreProvider = Provider<LanguageStore>((ref) => PreferencesLanguageStore());
final localeProvider = NotifierProvider<LocaleController, Locale>(LocaleController.new);

class LocaleController extends Notifier<Locale> {
  int _revision = 0;
  Future<void> _writes = Future<void>.value();
  @override
  Locale build() {
    final store = ref.watch(languageStoreProvider);
    final revision = _revision;
    Future<void>(() async {
      try {
        final saved = await store.read();
        if (ref.mounted && revision == _revision && (saved == 'en' || saved == 'es')) {
          state = Locale(saved!);
        }
      } catch (_) {
        // A missing/unavailable local preference keeps the existing English default.
      }
    });
    return const Locale('en');
  }

  Future<void> select(String language) {
    if (language != 'en' && language != 'es') return Future<void>.value();
    _revision++;
    state = Locale(language);
    final store = ref.read(languageStoreProvider);
    // Serialize rapid changes so the last visible selection is also persisted.
    return _writes = _writes.catchError((Object _) {}).then((_) => store.write(language));
  }
}
