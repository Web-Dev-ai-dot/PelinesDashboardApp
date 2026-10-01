import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pelines_admin_app/features/locations/models/auto_cancellation.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/models/pickup_service_preferences.dart';
import 'package:pelines_admin_app/features/locations/providers/auto_accept_controller.dart';
import 'package:pelines_admin_app/features/locations/providers/auto_cancellation_controller.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/locations/providers/pickup_preferences_controller.dart';
import 'package:pelines_admin_app/features/locations/providers/service_preferences_write_lock.dart';

import 'auto_cancellation_harness.dart';

const next = PickupServicePreferences(
  accept: false,
  minimum: 24.75,
  capacity: 9,
);

Future<PickupPreferencesState> save(
  ProviderContainer container,
  PickupOrderKind kind, {
  PickupServicePreferences preferences = next,
  Location? baseline,
}) {
  final location = baseline ?? container.read(currentLocationProvider).value!;
  return container
      .read(pickupPreferencesProvider(kind).notifier)
      .save(
        locationId: location.id,
        originalUpdatedAt: location.updatedAt,
        original: PickupServicePreferences.fromJson(
          location.servicePrefsJson,
          kind,
        ),
        preferences: preferences,
      );
}

void main() {
  for (final kind in PickupOrderKind.values) {
    final suffix = PickupServicePreferences.suffix(kind);
    test('defaults for absent/null/partial fields $kind', () {
      for (final json in [
        null,
        <String, dynamic>{},
        {'min$suffix': null},
      ]) {
        final prefs = PickupServicePreferences.fromJson(json, kind);
        expect(prefs.accept, true);
        expect(prefs.minimum, kind == PickupOrderKind.regular ? 15 : 150);
        expect(prefs.capacity, kind == PickupOrderKind.regular ? 80 : 6);
      }
    });
    test('canonical numbers, booleans and integral numeric capacity $kind', () {
      final prefs = PickupServicePreferences.fromJson({
        'accept$suffix': false,
        'min$suffix': 245.75,
        'cap$suffix': 12.0,
      }, kind);
      expect(prefs.accept, false);
      expect(prefs.minimum, 245.75);
      expect(prefs.capacity, 12);
      expect(prefs.capacity, isA<int>());
    });
    for (final key in ['accept', 'min', 'cap']) {
      final badValues = key == 'accept'
          ? <Object>['false', 0, {}]
          : <Object>[
              '15',
              'garbage',
              true,
              -1,
              double.nan,
              double.infinity,
              key == 'min' ? 1.234 : 1.5,
            ];
      for (final value in badValues) {
        test('reject malformed canonical $key$suffix=$value', () {
          expect(
            () =>
                PickupServicePreferences.fromJson({'$key$suffix': value}, kind),
            throwsA(isA<UnsupportedPickupPreferencesFormat>()),
          );
        });
      }
    }
    test(
      'section payload uses dollars and preserves all canonical JSON $kind',
      () async {
        final prefs = <String, dynamic>{
          'acceptRegular': true,
          'minRegular': 15,
          'capRegular': 80,
          'acceptCatering': true,
          'minCatering': 150,
          'capCatering': 6,
          'autoAcceptRegular': true,
          'autoAcceptCatering': false,
          'autoCancelRegularEnabled': true,
          'autoCancelRegularValue': 10,
          'autoCancelRegularUnit': 'minutes',
          'autoCancelCateringValue': 12,
          'autoCancelCateringUnit': 'hours',
          'autoCancelCateringEnabled': false,
          'unknown': {
            'nested': [
              {'keep': true},
            ],
          },
        };
        final harness = CancellationHarness(prefs: prefs);
        final container = harness.container();
        addTearDown(container.dispose);
        await container.read(currentLocationProvider.future);
        final original = PickupServicePreferences.fromJson(prefs, kind);
        final copy = next.mergeInto(prefs, original, kind);
        (copy['unknown']['nested'][0] as Map)['keep'] = false;
        expect(prefs['unknown']['nested'][0]['keep'], true);
        expect(
          (await save(container, kind)).phase,
          PickupPreferencesPhase.success,
        );
        expect(harness.patches.single, {
          'servicePrefsJson': {
            ...prefs,
            'accept$suffix': false,
            'min$suffix': 24.75,
            'cap$suffix': 9,
          },
        });
        final sent = harness.patches.single['servicePrefsJson'] as Map;
        expect(sent['accept$suffix'], isA<bool>());
        expect(sent['min$suffix'], isA<num>());
        expect(sent['cap$suffix'], isA<int>());
        expect(harness.reads, 2);
        final canonical = container.read(currentLocationProvider).value!;
        expect(
          PickupServicePreferences.fromJson(
            canonical.servicePrefsJson,
            kind,
          ).sameAs(next),
          true,
        );
        expect(canonical.updatedAt, harness.location.updatedAt);
        expect(container.read(servicePreferencesWriteProvider), false);
      },
    );
    test(
      'zero minimum and capacity persist, no-op never PATCH $kind',
      () async {
        final harness = CancellationHarness();
        final container = harness.container();
        addTearDown(container.dispose);
        await container.read(currentLocationProvider.future);
        await save(
          container,
          kind,
          preferences: PickupServicePreferences.fromJson(null, kind),
        );
        expect(harness.patches, isEmpty);
        const zero = PickupServicePreferences(
          accept: true,
          minimum: 0,
          capacity: 0,
        );
        expect(
          (await save(container, kind, preferences: zero)).phase,
          PickupPreferencesPhase.success,
        );
        expect(harness.patches.single, {
          'servicePrefsJson': {'min$suffix': 0, 'cap$suffix': 0},
        });
      },
    );
  }

  test(
    'money text validates decimals and finite amounts without cents conversion',
    () {
      for (final entry in {
        '0': 0,
        '0.01': 0.01,
        '12.30': 12.3,
        ' 245.75 ': 245.75,
      }.entries) {
        expect(
          PickupServicePreferences.minimumFromText(entry.key),
          entry.value,
        );
      }
      for (final text in [
        '',
        '-1',
        '-0',
        'NaN',
        'Infinity',
        '1e3',
        '1.234',
        'abc',
        'true',
        '1,50',
        '9' * 400,
      ]) {
        expect(
          PickupServicePreferences.minimumFromText(text),
          null,
          reason: text,
        );
      }
      for (final text in ['', '-1', '1.5', '1.0', 'abc', 'NaN', '9' * 400]) {
        expect(
          PickupServicePreferences.capacityFromText(text),
          null,
          reason: text,
        );
      }
      expect(PickupServicePreferences.capacityFromText('0'), 0);
      expect(PickupServicePreferences.capacityFromText('80'), 80);
    },
  );
  test('controller rejects invalid typed drafts before any request', () async {
    final harness = CancellationHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    for (final preferences in [
      const PickupServicePreferences(accept: true, minimum: -1, capacity: 0),
      const PickupServicePreferences(accept: true, minimum: 1.234, capacity: 0),
      const PickupServicePreferences(
        accept: true,
        minimum: double.infinity,
        capacity: 0,
      ),
      const PickupServicePreferences(accept: true, minimum: 0, capacity: -1),
    ]) {
      expect(
        (await save(
          container,
          PickupOrderKind.regular,
          preferences: preferences,
        )).phase,
        PickupPreferencesPhase.error,
      );
    }
    expect(harness.patches, isEmpty);
    expect(harness.reads, 0);
    expect(container.read(servicePreferencesWriteProvider), false);
  });
  for (final timestamp in [true, false]) {
    test(
      'preflight conflict by ${timestamp ? 'updatedAt' : 'original values'}',
      () async {
        final harness = CancellationHarness();
        final container = harness.container();
        addTearDown(container.dispose);
        await container.read(currentLocationProvider.future);
        if (timestamp) {
          harness.data['updatedAt'] = '2026-09-26T00:00:00Z';
        } else {
          harness.data['servicePrefsJson'] = {'minRegular': 20};
        }
        expect(
          (await save(container, PickupOrderKind.regular)).phase,
          PickupPreferencesPhase.conflict,
        );
        expect(harness.patches, isEmpty);
        expect(
          container.read(currentLocationProvider).value!.servicePrefsJson,
          harness.location.servicePrefsJson,
        );
        expect(container.read(servicePreferencesWriteProvider), false);
      },
    );
  }
  for (final timeout in [true, false]) {
    for (final applied in [true, false]) {
      test(
        'canonical reconciliation timeout=$timeout applied=$applied',
        () async {
          final harness = CancellationHarness()
            ..timeout = timeout
            ..applyPatch = applied;
          final container = harness.container();
          addTearDown(container.dispose);
          await container.read(currentLocationProvider.future);
          final result = await save(container, PickupOrderKind.regular);
          expect(
            result.phase,
            applied
                ? PickupPreferencesPhase.success
                : PickupPreferencesPhase.error,
          );
          expect(harness.patches.length, 1);
          expect(harness.reads, 2);
          expect(container.read(servicePreferencesWriteProvider), false);
        },
      );
    }
  }
  test(
    'failed reconciliation never retries the write and releases lock',
    () async {
      final harness = CancellationHarness()
        ..timeout = true
        ..failReadAfterPatch = true;
      final container = harness.container();
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);
      expect(
        (await save(container, PickupOrderKind.regular)).phase,
        PickupPreferencesPhase.error,
      );
      expect(harness.patches.length, 1);
      expect(harness.reads, 2);
      expect(container.read(servicePreferencesWriteProvider), false);
    },
  );
  for (final duringWrite in [true, false]) {
    test(
      'location change during ${duringWrite ? 'PATCH' : 'preflight'}',
      () async {
        final hold = Completer<void>();
        final harness = CancellationHarness();
        if (duringWrite) {
          harness.patchHold = hold;
        } else {
          harness.readHold = hold;
        }
        final container = harness.container();
        addTearDown(container.dispose);
        await container.read(currentLocationProvider.future);
        final pending = save(container, PickupOrderKind.regular);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        (container.read(currentLocationProvider.notifier)
                as CancellationCurrent)
            .replace(Location.fromJson({...harness.data, 'id': 'B'}));
        hold.complete();
        expect((await pending).phase, PickupPreferencesPhase.error);
        expect(harness.patches.length, duringWrite ? 1 : 0);
        expect(container.read(currentLocationProvider).value!.id, 'B');
        expect(container.read(servicePreferencesWriteProvider), false);
      },
    );
  }
  test(
    'double submit, other section and Auto Accept/Cancel cannot overlap',
    () async {
      final harness = CancellationHarness()..patchHold = Completer<void>();
      final container = harness.container();
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);
      final original = harness.location;
      final pending = save(container, PickupOrderKind.regular);
      await save(container, PickupOrderKind.regular);
      expect(
        (await save(container, PickupOrderKind.catering)).phase,
        PickupPreferencesPhase.error,
      );
      await container
          .read(autoAcceptProvider.notifier)
          .save(
            locationId: 'A',
            originalUpdatedAt: original.updatedAt,
            originalRegular: false,
            regular: true,
            originalCatering: false,
            catering: false,
          );
      expect(container.read(autoAcceptProvider).phase, AutoAcceptPhase.error);
      final cancelled = await container
          .read(autoCancellationProvider(PickupOrderKind.regular).notifier)
          .save(
            locationId: 'A',
            originalUpdatedAt: original.updatedAt,
            original: AutoCancellationRule.fromJson(
              null,
              PickupOrderKind.regular,
            ),
            rule: const AutoCancellationRule(
              enabled: true,
              value: 20,
              unit: AutoCancellationUnit.minutes,
            ),
          );
      expect(cancelled.phase, AutoCancellationPhase.error);
      harness.patchHold!.complete();
      await pending;
      expect(harness.patches.length, 1);
    },
  );
  for (final autoAccept in [true, false]) {
    test(
      'Auto ${autoAccept ? 'Accept' : 'Cancel'} excludes service saves',
      () async {
        final harness = CancellationHarness()..patchHold = Completer<void>();
        final container = harness.container();
        addTearDown(container.dispose);
        await container.read(currentLocationProvider.future);
        final pending = autoAccept
            ? container
                  .read(autoAcceptProvider.notifier)
                  .save(
                    locationId: 'A',
                    originalUpdatedAt: harness.location.updatedAt,
                    originalRegular: false,
                    regular: true,
                    originalCatering: false,
                    catering: false,
                  )
            : container
                  .read(
                    autoCancellationProvider(PickupOrderKind.regular).notifier,
                  )
                  .save(
                    locationId: 'A',
                    originalUpdatedAt: harness.location.updatedAt,
                    original: AutoCancellationRule.fromJson(
                      null,
                      PickupOrderKind.regular,
                    ),
                    rule: const AutoCancellationRule(
                      enabled: true,
                      value: 20,
                      unit: AutoCancellationUnit.minutes,
                    ),
                  );
        expect(
          (await save(container, PickupOrderKind.regular)).phase,
          PickupPreferencesPhase.error,
        );
        harness.patchHold!.complete();
        await pending;
        expect(harness.patches.length, 1);
      },
    );
  }
  test('shared lock stays held until canonical re-read completes', () async {
    final harness = CancellationHarness()..patchHold = Completer<void>();
    final container = harness.container();
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    final pending = save(container, PickupOrderKind.regular);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    harness.readHold = Completer<void>();
    harness.patchHold!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      container.read(pickupPreferencesProvider(PickupOrderKind.regular)).phase,
      PickupPreferencesPhase.reconciling,
    );
    expect(container.read(servicePreferencesWriteProvider), true);
    expect(
      (await save(container, PickupOrderKind.catering)).phase,
      PickupPreferencesPhase.error,
    );
    harness.readHold!.complete();
    expect((await pending).phase, PickupPreferencesPhase.success);
    expect(container.read(servicePreferencesWriteProvider), false);
  });
}
