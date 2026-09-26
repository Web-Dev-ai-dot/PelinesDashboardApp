# Pickup Settings — confirmed functional capabilities

## Delivered

General reuses the original accepting-orders control, provider, confirmation and scope warning. Location active is a read-only status: mobile excludes inactive locations from normal selection and this block does not add a separate administrative reactivation path. Web administration remains the activation-management route. No claim is made that isActive=false blocks Catering.

Regular Orders and Catering Orders have independent cards. Each opens the same AutoAcceptScreen, scoped to that order type, retaining its model/parser, mutation and confirmations. The original combined editor remains available to existing callers. Each card adds inline Auto Cancel enabled, integer duration, Minutes/Hours and Save/Cancel. Catering explicitly states the clock starts at order creation, not the scheduled event. Both cards warn that the scheduler runs every minute and can affect existing pending orders.

No controls for acceptRegular/acceptCatering, minimums, capacities, preparation time, independent Enable Pickup, hours or Delivery were added.

## Safety

- Defaults: Regular true/10/minutes; Catering true/12/hours. Null/missing fields use backend defaults. Wrong types and unknown units block editing.
- Enabled rules require positive integer durations: Regular 1–1440 effective minutes; Catering 10–10080. Hours conversion is validated before multiplication to reject oversized inputs safely.
- Activating cancellation or shortening effective duration opens an explicit confirmation about existing pending orders and possible refunds. Cancelling sends no PATCH. Controls are frozen while awaiting the dialog; network progress starts only after confirmation.
- Preflight reads canonical Location and checks updatedAt and the original rule. It rechecks selected location before PATCH.
- Deep-copy canonical servicePrefsJson; apply only changed keys for the requested rule; preserve Auto Accept, the other rule and unknown nested keys. No-op sends no PATCH.
- Re-read after write and reconcile the rule and explicit changed fields. Ambiguous network failures trigger one read, never a blind write retry. Conflicts adopt canonical state and require reload. Reload fetches canonical server data.
- Shared local write lock covers Auto Accept and both Auto Cancel scopes through final reconciliation. Contenders are disabled/rejected rather than queued with stale drafts. Existing Auto Accept save logic is wrapped, not duplicated.
- Backend has no atomic If-Match/conditional update. Cross-device races between preflight and PATCH remain; the local lock cannot eliminate them.
- Phone sections stack; wide screens use two service columns when text scale permits. Forms remain mounted while scrolling to preserve drafts.

## Validation

140 tests passed across auto_cancellation_test, pickup_auto_cancellation_test, pickup_settings_test, auto_accept_test, store_operations_test, router_test, delivery_settings_test and locations_parity_test. Includes EN/ES, phone/tablet/wide, 2x text without overflow, parser/defaults/bounds, preserved JSON, confirmation/cancel, double-submit, bidirectional Auto Accept contention, preflight conflict, ambiguous timeout, reconciliation and location changes. Responsive checks are widget tests, not device screenshots. No real order or API mutation was performed by these tests.

## Files changed in this task

- lib/app/l10n/catalog.dart
- lib/features/locations/models/auto_cancellation.dart (new)
- lib/features/locations/data/auto_cancellation_repository.dart (new capability interface)
- lib/features/locations/data/locations_repository.dart (implements the new capability; existing methods unchanged)
- lib/features/locations/providers/auto_cancellation_controller.dart (new)
- lib/features/locations/providers/service_preferences_write_lock.dart (new)
- lib/features/locations/providers/auto_accept_controller.dart (shared-lock wrapper)
- lib/features/locations/presentation/auto_accept_screen.dart (optional order scope and shared busy state)
- lib/features/locations/presentation/pickup_service_card.dart (new)
- lib/features/locations/presentation/pickup_settings_screen.dart
- lib/features/locations/presentation/store_operations_screen.dart (two imports only)
- test/auto_cancellation_harness.dart (new)
- test/auto_cancellation_test.dart (new)
- test/pickup_auto_cancellation_test.dart (new)
- test/pickup_settings_test.dart (updated expectations for separate cards)
- docs/pickup-functional-settings.md (this report)

Delivery and other sections were not edited. No commit/push. Stop for visual/functional review.
