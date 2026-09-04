import 'package:shared_preferences/shared_preferences.dart';

abstract interface class LocationSelectionStore {
  Future<String?> readLocationId();
  Future<void> writeLocationId(String id);
  Future<void> clearLocationId();
}

class SharedPreferencesLocationSelectionStore
    implements LocationSelectionStore {
  static const String _locationIdKey = 'current_location_id';

  @override
  Future<String?> readLocationId() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getString(_locationIdKey);
  }

  @override
  Future<void> writeLocationId(String id) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(_locationIdKey, id);
  }

  @override
  Future<void> clearLocationId() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.remove(_locationIdKey);
  }
}
