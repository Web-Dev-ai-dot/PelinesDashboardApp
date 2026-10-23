import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/locations/data/locations_repository.dart';
import 'package:pelines_admin_app/features/locations/models/auto_cancellation.dart';
import 'package:pelines_admin_app/features/locations/models/pickup_service_settings.dart';
import 'package:pelines_admin_app/features/locations/providers/pickup_service_controller.dart';
import 'package:pelines_admin_app/features/locations/providers/pickup_preferences_controller.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/locations/providers/service_preferences_write_lock.dart';

import 'auto_cancellation_harness.dart';

void main() {
  for (final kind in PickupOrderKind.values) {
    test(
      'one group merges changed keys without touching the other kind: $kind',
      () async {
        final harness = CancellationHarness(
          prefs: {
            'unknown': {
              'nested': [1],
            },
            'minRegular': 21,
            'minCatering': 200,
          },
        );
        final original = PickupServiceSettings.fromJson(
          harness.location.servicePrefsJson,
          kind,
        );
        final suffix = kind == PickupOrderKind.regular ? 'Regular' : 'Catering';
        final draft = PickupServiceSettings.fromJson({
          ...?harness.location.servicePrefsJson,
          'min$suffix': 33,
          'autoAccept$suffix': true,
          'autoCancel${suffix}Enabled': false,
        }, kind);
        await harness.repository.savePickupService(
          locationId: 'A',
          kind: kind,
          original: original,
          settings: draft,
          canWrite: () => true,
        );
        expect(harness.patches.length, 1);
        final json = harness.patches.single['servicePrefsJson'] as Map;
        expect(json['min$suffix'], 33);
        expect(json['autoAccept$suffix'], true);
        expect(json['autoCancel${suffix}Enabled'], false);
        expect(json['unknown'], {
          'nested': [1],
        });
        expect(
          json[kind == PickupOrderKind.regular ? 'minCatering' : 'minRegular'],
          kind == PickupOrderKind.regular ? 200 : 21,
        );
      },
    );
  }
  test('scope conflict and changed location prevent PATCH', () async {
    final harness = CancellationHarness();
    final original = PickupServiceSettings.fromJson(
      null,
      PickupOrderKind.regular,
    );
    final draft = PickupServiceSettings.fromJson({
      'minRegular': 22,
    }, PickupOrderKind.regular);
    await expectLater(
      harness.repository.savePickupService(
        locationId: 'A',
        kind: PickupOrderKind.regular,
        original: original,
        settings: draft,
        canWrite: () => false,
      ),
      throwsA(isA<Exception>()),
    );
    harness.data['servicePrefsJson'] = {'autoAcceptRegular': true};
    await expectLater(
      harness.repository.savePickupService(
        locationId: 'A',
        kind: PickupOrderKind.regular,
        original: original,
        settings: draft,
        canWrite: () => true,
      ),
      throwsA(isA<LocationSettingsConflict>()),
    );
    expect(harness.patches, isEmpty);
  });
  test('rebase unrelated canonical changes but preserve them', () async {
    final harness = CancellationHarness();
    final original = PickupServiceSettings.fromJson(
      null,
      PickupOrderKind.regular,
    );
    final draft = PickupServiceSettings.fromJson({
      'minRegular': 22,
    }, PickupOrderKind.regular);
    harness.data['servicePrefsJson'] = {'minCatering': 399, 'other': true};
    harness.data['updatedAt'] = '2026-10-20T00:00:00Z';
    await harness.repository.savePickupService(
      locationId: 'A',
      kind: PickupOrderKind.regular,
      original: original,
      settings: draft,
      canWrite: () => true,
    );
    expect(harness.patches.single['servicePrefsJson'], {
      'minCatering': 399,
      'other': true,
      'minRegular': 22,
    });
  });
  test('no-op preserves missing keys without writing defaults', () async {
    final harness = CancellationHarness();
    final original = PickupServiceSettings.fromJson(
      null,
      PickupOrderKind.regular,
    );
    await harness.repository.savePickupService(
      locationId: 'A',
      kind: PickupOrderKind.regular,
      original: original,
      settings: original,
      canWrite: () => true,
    );
    expect(harness.patches, isEmpty);
  });
  test(
    'shared lock blocks a grouped save and location mismatch is rejected',
    () async {
      final harness = CancellationHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);
      final original = PickupServiceSettings.fromJson(
        null,
        PickupOrderKind.regular,
      );
      final draft = PickupServiceSettings.fromJson({
        'minRegular': 22,
      }, PickupOrderKind.regular);
      final controller = container.read(
        pickupServiceProvider(PickupOrderKind.regular).notifier,
      );
      final lock = container.read(servicePreferencesWriteProvider.notifier);
      lock.tryAcquire();
      final blocked = await controller.save(
        locationId: 'A',
        original: original,
        settings: draft,
      );
      expect(blocked.phase, PickupPreferencesPhase.error);
      lock.release();
      final mismatch = await controller.save(
        locationId: 'B',
        original: original,
        settings: draft,
      );
      expect(mismatch.phase, PickupPreferencesPhase.error);
      expect(harness.patches, isEmpty);
    },
  );
}
