import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../locations/providers/locations_providers.dart';
import '../application/analytics_calculator.dart';
import '../data/analytics_repository.dart';
import '../models/analytics_date_range.dart';
import '../models/analytics_result.dart';

final analyticsRepositoryProvider = Provider<AnalyticsRepository>(
  (ref) => ApiAnalyticsRepository(ref.watch(apiClientProvider)),
);

class AnalyticsDatasetState {
  const AnalyticsDatasetState({
    required this.dataset,
    this.isRefreshing = false,
    this.refreshError,
  });
  final AnalyticsDataset dataset;
  final bool isRefreshing;
  final Object? refreshError;
}

// Keep the current dataset across navigation; build still invalidates it on
// session/location changes. No timer or polling is introduced.
final analyticsDatasetProvider =
    NotifierProvider<
      AnalyticsDatasetController,
      AsyncValue<AnalyticsDatasetState?>
    >(AnalyticsDatasetController.new);

/// Each rebuild starts a new request generation and clears the old scope.
/// Both success and error completions must still belong to that generation.
class AnalyticsDatasetController
    extends Notifier<AsyncValue<AnalyticsDatasetState?>> {
  int _generation = 0;
  bool _inFlight = false;
  String? _locationId;
  AnalyticsRepository? _repository;

  @override
  AsyncValue<AnalyticsDatasetState?> build() {
    final generation = ++_generation;
    ref.onDispose(() => _generation++);
    _inFlight = false;
    _locationId = null;
    final auth = ref.watch(authControllerProvider);
    if (auth.isLoading) return const AsyncLoading();
    if (auth.hasError) return AsyncError(auth.error!, auth.stackTrace!);
    if (auth.value == null) return const AsyncData(null);
    final location = ref.watch(currentLocationProvider);
    if (location.isLoading) return const AsyncLoading();
    if (location.hasError) {
      return AsyncError(location.error!, location.stackTrace!);
    }
    if (location.value == null) return const AsyncData(null);
    _locationId = location.value!.id;
    _repository = ref.watch(analyticsRepositoryProvider);
    _inFlight = true;
    final repository = _repository!;
    final locationId = _locationId!;
    // Defer state writes until build has returned its clean loading state.
    unawaited(
      Future<void>.microtask(
        () => _load(generation, repository, locationId, null),
      ),
    );
    return const AsyncLoading();
  }

  Future<void> refresh() async {
    if (_inFlight || _locationId == null || !ref.mounted) return;
    final previous = state.value;
    _inFlight = true;
    state = previous == null
        ? const AsyncLoading()
        : AsyncData(
            AnalyticsDatasetState(
              dataset: previous.dataset,
              isRefreshing: true,
            ),
          );
    await _load(_generation, _repository!, _locationId!, previous);
  }

  Future<void> _load(
    int generation,
    AnalyticsRepository repository,
    String locationId,
    AnalyticsDatasetState? previous,
  ) async {
    if (!ref.mounted || generation != _generation) return;
    try {
      final dataset = await repository.getDataset(locationId: locationId);
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(AnalyticsDatasetState(dataset: dataset));
    } catch (error, stack) {
      if (!ref.mounted || generation != _generation) return;
      state = previous == null
          ? AsyncError(error, stack)
          : AsyncData(
              AnalyticsDatasetState(
                dataset: previous.dataset,
                refreshError: error,
              ),
            );
    } finally {
      if (ref.mounted && generation == _generation) _inFlight = false;
    }
  }
}

final analyticsRangeProvider =
    NotifierProvider<AnalyticsRangeController, AnalyticsDateRange>(
      AnalyticsRangeController.new,
    );

class AnalyticsRangeController extends Notifier<AnalyticsDateRange> {
  @override
  AnalyticsDateRange build() =>
      AnalyticsDateRange.preset(AnalyticsDatePreset.last30Days);
  void selectPreset(AnalyticsDatePreset preset, {DateTime? now}) {
    state = AnalyticsDateRange.preset(preset, now: now);
  }

  void selectCustom(DateTime from, DateTime through) {
    state = AnalyticsDateRange.custom(from, through);
  }
}

/// Loading/errors remain loading/errors; absence of session/location is null.
/// Refresh errors and completeness metadata remain on analyticsDatasetProvider.
final analyticsResultProvider =
    Provider.autoDispose<AsyncValue<AnalyticsResult?>>((ref) {
      final dataset = ref.watch(analyticsDatasetProvider);
      final range = ref.watch(analyticsRangeProvider);
      return dataset.whenData(
        (value) => value == null
            ? null
            : const AnalyticsCalculator().calculate(
                value.dataset.orders,
                locationId: value.dataset.locationId,
                range: range,
              ),
      );
    });

final analyticsRefreshProvider = Provider.autoDispose<Future<void> Function()>((
  ref,
) {
  ref.watch(analyticsDatasetProvider);
  return () => ref.read(analyticsDatasetProvider.notifier).refresh();
});
