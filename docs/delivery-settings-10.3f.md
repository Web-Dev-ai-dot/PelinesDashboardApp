# Block 10.3F — Delivery Settings production parity

## Audit (before implementation)

Evidence: supplied `../pelines-dash-forge/src/routes/_admin.store.delivery-settings.tsx`, including its inline DeliveryBlock, state/defaults and API mutations; Flutter RegularDeliverySettings, CateringDeliverySettings, both delivery controllers/editors and LocationsRepository. The production reference is the provided checkout, not a live authenticated deployment. No backend source/OpenAPI was supplied; backend behavior below is the existing Flutter contract, not independently verified server implementation.

| Capability | Production | Flutter classification and decision |
| --- | --- | --- |
| Regular enabled | regularDeliveryJson.enabled; absent defaults false | Supported in existing editor. Reused unchanged. |
| Regular cost | regularDeliveryJson.feeCents | Supported in existing editor. Preserve integer cents and strict decimal parsing. |
| Regular minimum | regularDeliveryJson.minimumCents; not editable; preserved in save | Supported read-only in Flutter. No safe minimum-edit mutation; no input added. |
| Regular radius / blocks / zone | No controls or mutations in this route | No safe typed Flutter mutation. Omitted. |
| Regular capacity / preferences / schedule | No controls in this route | No delivery-specific typed mutation. Omitted; service preferences are not imported from Pickup. |
| Catering enabled | cateringDeliveryJson.enabled; web defaults false | Supported in existing editor. Flutter default is TRUE for null/missing enabled. Keep effective backend contract and show Using default setting; do not copy web default. |
| Catering cost | top-level deliveryFeeCents | Supported in existing editor. Never use regularDeliveryJson.feeCents or cateringDeliveryJson.cost as fallback. |
| Catering minimum | top-level deliveryMinimumCents; not editable; preserved by web | Supported read-only in Flutter. Existing mutation does not write minimum; reconciliation verifies preservation. |
| Catering radius / zone / schedule / capacity | No controls in this route | No safe typed Flutter mutation. Omitted. No scheduling semantics changed. |
| Catering cost / label / applyAutomatically JSON properties | Declared/preserved opaque properties, not editable controls | Existing repository preserves unknown JSON properties. They are not interpreted as the top-level delivery fee or exposed as inputs. |

All four actual production editable controls are already supported by Flutter editors elsewhere; no newly discovered editable endpoint needs consumption. Other entries above are read-only or have no safe edit mutation. Both production blocks contain an enable switch, dollar cost input and independent Save action. Production dims/disables cost while delivery is off. Flutter intentionally retains its existing ability to prepare a fee while off, its strict parser (no permissive rounding), existing dirty-state rules and confirmations.

## Result

`/app/store/delivery-settings` now builds a standalone DeliverySettingsScreen. Location badge and EN/ES description precede distinct Regular and Catering summary cards. Each displays its own effective status, fee and read-only minimum and opens the existing editor. Malformed settings block only the affected editor. Busy state disables that service's Edit action. Loading, error/retry and missing selection are explicit.

Editors use Web Parity settings cards, bounded single-column forms, real switches, bordered dollar inputs, a service-specific fee explanation, read-only minimum, and existing Save/Cancel behavior. Providers, repository payloads, amount conversion, unknown-key preservation, defaults, concurrency checks, reconciliation and catering enable confirmation are unchanged. Existing English literal operational dialogs remain unchanged.

Regular and Catering summaries stack on phones and use two columns only when OperationsGrid has enough width for current text scale. Editors are capped at 860 logical pixels. Text scaling can return summaries to one column. Buttons retain >=48-pixel minimum targets. No Pickup, Auto Accept, online-ordering switch, hours, closures, contact, printer, promotions or menu controls appear in the new destination.

No changes to Locations, Pickup, Store navigation, backend/API or other features. Existing internal Store Operations and legacy delivery section remain available; ordinary Store destinations no longer need that screen.

## Files in this block

- lib/app/router.dart: delivery builder/import only.
- lib/app/l10n/catalog.dart: four used translation entries.
- lib/features/locations/presentation/delivery_settings_screen.dart: new standalone screen.
- lib/features/locations/presentation/regular_delivery_screen.dart: presentation only.
- lib/features/locations/presentation/catering_delivery_screen.dart: presentation only.
- test/delivery_settings_test.dart: summaries/editors, isolation, state and responsive tests.
- docs/delivery-settings-10.3f.md: audit and decisions.

## Validation scope

New tests cover 320/390/768/1400 widths, EN/ES and 1x/2x text, both summaries/editors, independent fields/defaults, Save and dirty Cancel, mutation loading/errors, location changes, malformed settings and initial loading/error/retry/empty selection. Existing Regular/Catering suites cover money parsing, exact payloads, minimum/unknown-key preservation, conflicts and catering confirmations/reconciliation. Router, Pickup and Locations suites provide regression checks. Responsive evidence is widget tests, not physical-device visual approval.

Final results: 24/24 new Delivery tests passed. All 60 selected existing tests passed across regular_delivery_test, catering_delivery_test, router_test, pickup_settings_test and locations_parity_test. flutter analyze: no issues found. git diff --check: exit 0. No commit/push; ready for visual review.
