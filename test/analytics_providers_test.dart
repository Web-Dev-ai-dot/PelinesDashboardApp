import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/account/models/profile.dart';
import 'package:pelines_admin_app/features/auth/models/admin_session.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_controller.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_providers.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/analytics/data/analytics_repository.dart';
import 'package:pelines_admin_app/features/analytics/models/analytics_order.dart';
import 'package:pelines_admin_app/features/analytics/models/analytics_date_range.dart';
import 'package:pelines_admin_app/features/analytics/providers/analytics_providers.dart';

import 'order_test_data.dart';

void main() {
  late FakeRepository repository;
  late FakeAuth auth;
  late FakeLocation location;
  late ProviderContainer container;
  late void Function() stopListening;

  setUp(() async {
    repository = FakeRepository();
    auth = FakeAuth();
    location = FakeLocation();
    container = ProviderContainer(
      overrides: [
        analyticsRepositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith(() => auth),
        currentLocationProvider.overrideWith(() => location),
      ],
    );
    final subscription = container.listen(analyticsResultProvider, (_, _) {});
    stopListening = subscription.close;
    await settle(container);
  });
  tearDown(() => container.dispose());

  test(
    'leaving and returning retains the same location dataset without polling',
    () async {
      repository.requests.single.complete(data('a'));
      await settle(container);
      final original = container.read(analyticsDatasetProvider).value!.dataset;
      stopListening();
      await settle(container);
      final subscription = container.listen(analyticsResultProvider, (_, _) {});
      await settle(container);
      expect(repository.requests.length, 1);
      expect(
        container.read(analyticsDatasetProvider).value!.dataset,
        same(original),
      );
      subscription.close();
    },
  );

  test(
    'session changes while away cannot expose cached analytics on return',
    () async {
      repository.requests.single.complete(data('a'));
      await settle(container);
      stopListening();
      await settle(container);
      auth.replace(null);
      await settle(container);
      final subscription = container.listen(analyticsResultProvider, (_, _) {});
      await settle(container);
      expect(container.read(analyticsResultProvider).value, isNull);
      expect(container.read(analyticsDatasetProvider).value, isNull);
      subscription.close();
    },
  );

  test(
    'loads current location; range and custom recalculate without a GET',
    () async {
      expect(repository.locations, ['a']);
      repository.requests[0].complete(data('a'));
      await settle(container);
      container
          .read(analyticsRangeProvider.notifier)
          .selectCustom(DateTime(2026, 9, 4), DateTime(2026, 9, 4));
      expect(
        container.read(analyticsResultProvider).value!.current.salesCents,
        1100,
      );
      container
          .read(analyticsRangeProvider.notifier)
          .selectPreset(
            AnalyticsDatePreset.today,
            now: DateTime.utc(2026, 9, 5, 18),
          );
      expect(
        container.read(analyticsResultProvider).value!.current.salesCents,
        0,
      );
      expect(repository.locations, ['a']);
    },
  );

  test(
    'location change hides previous data and ignores late initial success',
    () async {
      location.setLocation('b');
      await settle(container);
      expect(repository.locations, ['a', 'b']);
      expect(container.read(analyticsDatasetProvider).isLoading, isTrue);
      repository.requests[1].complete(data('b'));
      await settle(container);
      repository.requests[0].complete(data('a'));
      await settle(container);
      expect(
        container.read(analyticsDatasetProvider).value!.dataset.locationId,
        'b',
      );
    },
  );

  test(
    'manual refresh deduplicates and preserves previous dataset on error',
    () async {
      repository.requests[0].complete(data('a'));
      await settle(container);
      final old = container.read(analyticsDatasetProvider).value!.dataset;
      final refresh = container.read(analyticsRefreshProvider)();
      await container.read(analyticsRefreshProvider)();
      expect(repository.requests.length, 2);
      expect(
        container.read(analyticsDatasetProvider).value!.isRefreshing,
        isTrue,
      );
      repository.requests[1].completeError(
        const ApiException(message: 'offline'),
      );
      await refresh;
      final state = container.read(analyticsDatasetProvider).value!;
      expect(state.dataset, same(old));
      expect(state.refreshError, isA<ApiException>());
      expect(state.isRefreshing, isFalse);
      expect(container.read(analyticsResultProvider).hasError, isFalse);
      final retry = container.read(analyticsRefreshProvider)();
      repository.requests[2].complete(data('a', empty: true));
      await retry;
      expect(
        container.read(analyticsDatasetProvider).value!.dataset.orders,
        isEmpty,
      );
      expect(
        container.read(analyticsDatasetProvider).value!.refreshError,
        isNull,
      );
    },
  );

  test('initial error remains error and refresh can retry', () async {
    repository.requests[0].completeError(
      const ApiException(message: 'denied', statusCode: 403),
    );
    await settle(container);
    expect(container.read(analyticsDatasetProvider).hasError, isTrue);
    expect(container.read(analyticsResultProvider).hasError, isTrue);
    final retry = container.read(analyticsRefreshProvider)();
    repository.requests[1].complete(data('a'));
    await retry;
    expect(container.read(analyticsDatasetProvider).hasError, isFalse);
  });

  for (final fails in [false, true]) {
    test(
      'late refresh ${fails ? 'error' : 'success'} cannot replace next location',
      () async {
        repository.requests[0].complete(data('a'));
        await settle(container);
        final refresh = container.read(analyticsRefreshProvider)();
        location.setLocation('b');
        await settle(container);
        repository.requests[2].complete(data('b'));
        await settle(container);
        if (fails) {
          repository.requests[1].completeError(Exception('old failure'));
        } else {
          repository.requests[1].complete(data('a'));
        }
        await refresh;
        expect(
          container.read(analyticsDatasetProvider).value!.dataset.locationId,
          'b',
        );
        expect(
          container.read(analyticsDatasetProvider).value!.refreshError,
          isNull,
        );
      },
    );
  }

  test(
    'logout removes dataset; same-user new session ignores old request',
    () async {
      auth.replace(null);
      await settle(container);
      expect(container.read(analyticsDatasetProvider).value, isNull);
      expect(container.read(analyticsResultProvider).value, isNull);
      await container.read(analyticsRefreshProvider)();
      expect(repository.requests.length, 1);
      auth.replace(session('user'));
      await settle(container);
      repository.requests[1].complete(data('a', empty: true));
      await settle(container);
      repository.requests[0].complete(data('a'));
      await settle(container);
      expect(
        container.read(analyticsDatasetProvider).value!.dataset.orders,
        isEmpty,
      );
    },
  );

  test('direct session replacement clears previously loaded records', () async {
    repository.requests[0].complete(data('a'));
    await settle(container);
    auth.replace(session('other-user'));
    await settle(container);
    expect(container.read(analyticsDatasetProvider).isLoading, isTrue);
    expect(container.read(analyticsDatasetProvider).value, isNull);
    expect(repository.requests.length, 2);
    repository.requests[1].completeError(Exception('new session error'));
    await settle(container);
    expect(container.read(analyticsDatasetProvider).hasError, isTrue);
    expect(container.read(analyticsDatasetProvider).value, isNull);
  });

  test('no selected location clears results and does not query', () async {
    location.setLocation(null);
    await settle(container);
    repository.requests[0].complete(data('a'));
    await settle(container);
    expect(container.read(analyticsDatasetProvider).value, isNull);
    expect(repository.requests.length, 1);
  });
}

Future<void> settle(ProviderContainer container) async {
  for (var i = 0; i < 4; i++) {
    await container.pump();
    await Future<void>.delayed(Duration.zero);
  }
}

AnalyticsDataset data(String location, {bool empty = false}) =>
    AnalyticsDataset(
      locationId: location,
      orders: empty
          ? []
          : [AnalyticsOrder.fromJson(orderJson(locationId: location))],
    );

class FakeRepository implements AnalyticsRepository {
  final locations = <String>[];
  final requests = <Completer<AnalyticsDataset>>[];
  @override
  Future<AnalyticsDataset> getDataset({required String locationId}) {
    locations.add(locationId);
    final request = Completer<AnalyticsDataset>();
    requests.add(request);
    return request.future;
  }
}

AdminSession session(String id) => AdminSession(
  profile: Profile(
    id: id,
    role: ProfileRole.admin,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
);

class FakeAuth extends AuthController {
  @override
  Future<AdminSession?> build() async => session('user');
  void replace(AdminSession? value) => state = AsyncData(value);
}

class FakeLocation extends CurrentLocationController {
  @override
  Future<Location?> build() async => makeLocation('a');
  void setLocation(String? id) =>
      state = AsyncData(id == null ? null : makeLocation(id));
}

Location makeLocation(String id) => Location(
  id: id,
  name: id,
  slug: id,
  isActive: true,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  isAcceptingOrders: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
