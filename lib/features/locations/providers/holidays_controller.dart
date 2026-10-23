import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../data/holidays_repository.dart';
import '../data/locations_repository.dart';
import '../models/holiday.dart';
import '../models/location.dart';
import 'locations_providers.dart';

final holidaysRepositoryProvider = Provider<HolidaysRepository>((ref) {
  final repository = ref.watch(locationsRepositoryProvider);
  if (repository is HolidaysRepository) return repository as HolidaysRepository;
  throw StateError('Holidays repository unavailable.');
});

class HolidaysSaveState {
  const HolidaysSaveState({
    this.busy = false,
    this.success = false,
    this.reloadRequired = false,
    this.message,
  });
  final bool busy, success, reloadRequired;
  final String? message;
}

final holidaysSaveProvider =
    NotifierProvider<HolidaysController, HolidaysSaveState>(
      HolidaysController.new,
    );

class HolidaysController extends Notifier<HolidaysSaveState> {
  @override
  HolidaysSaveState build() => const HolidaysSaveState();
  bool _selected(String id) {
    if (!ref.mounted) return false;
    final current = ref.read(currentLocationProvider);
    return !current.isLoading && !current.hasError && current.value?.id == id;
  }

  void _adopt(Location location) {
    ref.read(locationsProvider.notifier).adoptCanonical(location);
    ref.read(currentLocationProvider.notifier).adoptCanonical(location);
  }

  Future<void> save({
    required Location original,
    required List<Holiday> holidays,
  }) async {
    if (state.busy) return;
    if (!_selected(original.id)) {
      state = const HolidaysSaveState(
        message: 'The selected location changed. No change was sent.',
      );
      return;
    }
    final validation = validateHolidays(holidays);
    if (validation != null) {
      state = HolidaysSaveState(message: validation);
      return;
    }
    state = const HolidaysSaveState(busy: true);
    try {
      await ref
          .read(holidaysRepositoryProvider)
          .saveHolidays(
            locationId: original.id,
            originalUpdatedAt: original.updatedAt,
            holidays: holidays,
            canWrite: () => _selected(original.id),
          );
    } on LocationSettingsConflict catch (conflict) {
      if (!ref.mounted) return;
      _adopt(conflict.canonical);
      state = const HolidaysSaveState(
        reloadRequired: true,
        message: 'Store settings were changed elsewhere. Reload before saving.',
      );
      return;
    } catch (error) {
      if (!ref.mounted) return;
      if (error is ApiException &&
          (error.statusCode == null || error.statusCode! >= 500)) {
        await _reconcile(original.id, holidays);
      } else {
        state = HolidaysSaveState(
          message: error is ArgumentError
              ? error.message.toString()
              : error is ApiException
              ? error.message
              : 'Holidays could not be saved.',
        );
      }
      return;
    }
    if (!ref.mounted) return;
    await _reconcile(original.id, holidays);
  }

  Future<void> _reconcile(String id, List<Holiday> expected) async {
    try {
      final canonical = await ref
          .read(locationsRepositoryProvider)
          .getLocation(id);
      if (!ref.mounted) return;
      if (!_selected(id)) {
        state = const HolidaysSaveState(
          reloadRequired: true,
          message: 'The selected location changed. No further change was sent.',
        );
        return;
      }
      final matches = sameHolidays(
        holidaysFromExtras(canonical.hoursExtrasJson),
        expected,
      );
      _adopt(canonical);
      state = matches
          ? const HolidaysSaveState(success: true)
          : const HolidaysSaveState(
              reloadRequired: true,
              message:
                  'The result could not be confirmed. Reload before retrying.',
            );
    } catch (_) {
      if (!ref.mounted) return;
      state = const HolidaysSaveState(
        reloadRequired: true,
        message: 'The result could not be confirmed. Reload before retrying.',
      );
    }
  }
}
