import '../models/holiday.dart';
import '../models/location.dart';

abstract interface class HolidaysRepository {
  Future<Location> saveHolidays({
    required String locationId,
    required DateTime originalUpdatedAt,
    required List<Holiday> holidays,
    required bool Function() canWrite,
  });
}
