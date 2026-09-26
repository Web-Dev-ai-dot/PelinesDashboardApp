import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pelines_admin_app/features/locations/data/locations_repository.dart';
import 'package:pelines_admin_app/features/locations/models/auto_cancellation.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/auto_accept_controller.dart';
import 'package:pelines_admin_app/features/locations/providers/auto_cancellation_controller.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/locations/providers/service_preferences_write_lock.dart';

import 'auto_cancellation_harness.dart';

AutoCancellationRule rule(
  int value, {
  bool enabled = true,
  AutoCancellationUnit unit = AutoCancellationUnit.minutes,
}) => AutoCancellationRule(enabled: enabled, value: value, unit: unit);
Future<AutoCancellationState> save(
  ProviderContainer container,
  PickupOrderKind kind,
  AutoCancellationRule next, {
  Location? originalLocation,
}) {
  final location =
      originalLocation ?? container.read(currentLocationProvider).value!;
  return container
      .read(autoCancellationProvider(kind).notifier)
      .save(
        locationId: location.id,
        originalUpdatedAt: location.updatedAt,
        original: AutoCancellationRule.fromJson(
          location.servicePrefsJson,
          kind,
        ),
        rule: next,
      );
}

void main() {
  test('backend defaults for null, empty and null fields', () {
    for (final json in [
      null,
      <String, dynamic>{},
      <String, dynamic>{
        'autoCancelRegularEnabled': null,
        'autoCancelCateringValue': null,
      },
    ]) {
      final regular = AutoCancellationRule.fromJson(
        json,
        PickupOrderKind.regular,
      );
      final catering = AutoCancellationRule.fromJson(
        json,
        PickupOrderKind.catering,
      );
      expect(regular.enabled, true);
      expect(regular.value, 10);
      expect(regular.unit, AutoCancellationUnit.minutes);
      expect(catering.enabled, true);
      expect(catering.value, 12);
      expect(catering.unit, AutoCancellationUnit.hours);
    }
  });
  for (final kind in PickupOrderKind.values) {
    final prefix = AutoCancellationRule.keyPrefix(kind);
    for (final entry in {
      'Enabled': 'false',
      'Value': 1.5,
      'Unit': 'days',
    }.entries) {
      test(
        'reject $kind ${entry.key}',
        () => expect(
          () => AutoCancellationRule.fromJson({
            '$prefix${entry.key}': entry.value,
          }, kind),
          throwsA(isA<UnsupportedAutoCancellationFormat>()),
        ),
      );
    }
    test('exact minute/hour limits $kind', () {
      final min = kind == PickupOrderKind.regular ? 1 : 10,
          max = kind == PickupOrderKind.regular ? 1440 : 10080;
      for (final v in [min, max]) {
        expect(rule(v).validate(kind), null);
      }
      for (final v in [0, -1, min - 1, max + 1]) {
        expect(rule(v).validate(kind), isNotNull);
      }
      expect(
        rule(max ~/ 60, unit: AutoCancellationUnit.hours).validate(kind),
        null,
      );
      expect(
        rule(max ~/ 60 + 1, unit: AutoCancellationUnit.hours).validate(kind),
        isNotNull,
      );
      expect(rule(1, unit: AutoCancellationUnit.hours).validate(kind), null);
      expect(rule(0, enabled: false).validate(kind), null);
    });
    test(
      'minimal safe PATCH, deep unknown preservation and independent scope $kind',
      () async {
        final prefs = <String, dynamic>{
          'autoAcceptRegular': true,
          'autoAcceptCatering': false,
          'autoCancelRegularValue': 10,
          'autoCancelCateringValue': 12,
          'acceptRegular': false,
          'minRegular': 15,
          'future': {
            'list': [
              {'preserve': true},
            ],
          },
        };
        final harness = CancellationHarness(prefs: prefs);
        final old = AutoCancellationRule.fromJson(prefs, kind);
        final next = rule(30);
        final merged = next.mergeInto(prefs, old, kind);
        expect(identical(merged['future'], prefs['future']), false);
        await harness.repository.saveAutoCancellationSettings(
          locationId: 'A',
          originalUpdatedAt: harness.location.updatedAt,
          kind: kind,
          original: old,
          rule: next,
          canWrite: () => true,
        );
        expect(harness.patches.single, {
          'servicePrefsJson': {...prefs, ...next.changesFrom(old, kind)},
        });
      },
    );
    test('successful write and canonical reread $kind', () async {
      final harness = CancellationHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);
      final result = await save(container, kind, rule(25));
      expect(result.phase, AutoCancellationPhase.success);
      expect(harness.patches.length, 1);
      expect(harness.reads, 2);
      expect(
        AutoCancellationRule.fromJson(
          container.read(currentLocationProvider).value!.servicePrefsJson,
          kind,
        ).value,
        25,
      );
      expect(container.read(servicePreferencesWriteProvider), false);
    });
  }
  test('confirmation uses effective duration not numeric value', () {
    expect(rule(10).requiresConfirmation(rule(10, enabled: false)), true);
    expect(
      rule(1, unit: AutoCancellationUnit.hours).requiresConfirmation(rule(120)),
      true,
    );
    expect(
      rule(60).requiresConfirmation(rule(1, unit: AutoCancellationUnit.hours)),
      false,
    );
    expect(rule(1, enabled: false).requiresConfirmation(rule(10)), false);
    expect(rule(20).requiresConfirmation(rule(10)), false);
  });
  test('preflight timestamp conflict and no-op never PATCH', () async {
    final harness = CancellationHarness();
    final original = harness.location;
    final old = AutoCancellationRule.fromJson(null, PickupOrderKind.regular);
    await harness.repository.saveAutoCancellationSettings(
      locationId: 'A',
      originalUpdatedAt: original.updatedAt,
      kind: PickupOrderKind.regular,
      original: old,
      rule: old,
      canWrite: () => true,
    );
    expect(harness.patches, isEmpty);
    harness.data['updatedAt'] = '2026-09-26T00:00:00Z';
    await expectLater(
      harness.repository.saveAutoCancellationSettings(
        locationId: 'A',
        originalUpdatedAt: original.updatedAt,
        kind: PickupOrderKind.regular,
        original: old,
        rule: rule(20),
        canWrite: () => true,
      ),
      throwsA(isA<LocationSettingsConflict>()),
    );
    expect(harness.patches, isEmpty);
  });
  for (final applied in [true, false]) {
    test('ambiguous timeout reconciles once applied=$applied', () async {
      final harness = CancellationHarness()
        ..timeout = true
        ..applyPatch = applied;
      final container = harness.container();
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);
      final result = await save(container, PickupOrderKind.regular, rule(20));
      expect(
        result.phase,
        applied ? AutoCancellationPhase.success : AutoCancellationPhase.error,
      );
      expect(harness.patches.length, 1);
      expect(harness.reads, 2);
      expect(container.read(servicePreferencesWriteProvider), false);
    });
  }
  test('reconciliation failure releases lock without retry', () async {
    final harness = CancellationHarness()
      ..timeout = true
      ..failReadAfterPatch = true;
    final container = harness.container();
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    expect(
      (await save(container, PickupOrderKind.regular, rule(20))).phase,
      AutoCancellationPhase.error,
    );
    expect(harness.patches.length, 1);
    expect(container.read(servicePreferencesWriteProvider), false);
  });
  test('context change during preflight blocks PATCH', () async {
    final harness = CancellationHarness()..readHold = Completer<void>();
    final container = harness.container();
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    final future = save(container, PickupOrderKind.regular, rule(20));
    await Future<void>.delayed(Duration.zero);
    (container.read(currentLocationProvider.notifier) as CancellationCurrent)
        .replace(Location.fromJson({...harness.data, 'id': 'B'}));
    harness.readHold!.complete();
    expect((await future).phase, AutoCancellationPhase.error);
    expect(harness.patches, isEmpty);
  });
  test('context change during write does not adopt wrong location', () async {
    final harness = CancellationHarness()..patchHold = Completer<void>();
    final container = harness.container();
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    final future = save(container, PickupOrderKind.regular, rule(20));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    (container.read(currentLocationProvider.notifier) as CancellationCurrent)
        .replace(Location.fromJson({...harness.data, 'id': 'B'}));
    harness.patchHold!.complete();
    expect((await future).phase, AutoCancellationPhase.error);
    expect(container.read(currentLocationProvider).value!.id, 'B');
  });
  test('conflict adopts canonical and releases lock', () async {
    final harness = CancellationHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    harness.data['updatedAt'] = '2026-09-26T00:00:00Z';
    expect(
      (await save(container, PickupOrderKind.regular, rule(20))).phase,
      AutoCancellationPhase.conflict,
    );
    expect(harness.patches, isEmpty);
    expect(
      container.read(currentLocationProvider).value!.updatedAt,
      harness.location.updatedAt,
    );
    expect(container.read(servicePreferencesWriteProvider), false);
  });
  test('double submit and Auto Accept contention cannot overlap; retry preserves both', () async {
    final harness = CancellationHarness()..patchHold = Completer<void>();
    final container = harness.container();
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    final original = container.read(currentLocationProvider).value!;
    final first = save(container, PickupOrderKind.regular, rule(20));
    await save(container, PickupOrderKind.regular, rule(30));
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
    harness.patchHold!.complete();
    await first;
    expect(harness.patches.length, 1);
    await container
        .read(autoAcceptProvider.notifier)
        .save(
          locationId: 'A',
          originalUpdatedAt: harness.location.updatedAt,
          originalRegular: false,
          regular: true,
          originalCatering: false,
          catering: false,
        );
    expect(harness.patches.length, 2);
    expect(harness.data['servicePrefsJson'], {
      'autoCancelRegularValue': 20,
      'autoAcceptRegular': true,
    });
  });
  test('Auto Accept holds shared lock through reconciliation', () async {
    final harness = CancellationHarness()..patchHold = Completer<void>();
    final container = harness.container();
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    final first = container
        .read(autoAcceptProvider.notifier)
        .save(
          locationId: 'A',
          originalUpdatedAt: harness.location.updatedAt,
          originalRegular: false,
          regular: true,
          originalCatering: false,
          catering: false,
        );
    expect(
      (await save(container, PickupOrderKind.catering, rule(60))).phase,
      AutoCancellationPhase.error,
    );
    harness.patchHold!.complete();
    await first;
    expect(harness.patches.length, 1);
    expect(container.read(servicePreferencesWriteProvider), false);
  });
}
