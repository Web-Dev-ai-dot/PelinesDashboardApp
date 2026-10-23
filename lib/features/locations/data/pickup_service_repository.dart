import '../models/auto_cancellation.dart';
import '../models/location.dart';
import '../models/pickup_service_settings.dart';

abstract interface class PickupServiceRepository {
  Future<Location> savePickupService({
    required String locationId,
    required PickupOrderKind kind,
    required PickupServiceSettings original,
    required PickupServiceSettings settings,
    required bool Function() canWrite,
  });
}
