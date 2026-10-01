import '../models/auto_cancellation.dart';
import '../models/location.dart';
import '../models/pickup_service_preferences.dart';

abstract interface class PickupPreferencesRepository {
  Future<Location> savePickupPreferences({
    required String locationId,
    required DateTime originalUpdatedAt,
    required PickupOrderKind kind,
    required PickupServicePreferences original,
    required PickupServicePreferences preferences,
    required bool Function() canWrite,
  });
}
