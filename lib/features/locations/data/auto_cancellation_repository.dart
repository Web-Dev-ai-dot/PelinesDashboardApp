import '../models/auto_cancellation.dart';
import '../models/location.dart';

abstract interface class AutoCancellationRepository {
  Future<Location> saveAutoCancellationSettings({
    required String locationId,
    required DateTime originalUpdatedAt,
    required PickupOrderKind kind,
    required AutoCancellationRule original,
    required AutoCancellationRule rule,
    required bool Function() canWrite,
  });
}
