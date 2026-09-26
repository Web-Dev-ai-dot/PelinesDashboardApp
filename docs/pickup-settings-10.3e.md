# Block 10.3E — Pickup Settings audit

## Scope and evidence

Reference is the supplied production-web checkout, not a live authenticated deployment. Read `_admin.store.pickup-settings.tsx`, `components/pelines/ServicePreferencesForm.tsx`, and `lib/servicePreferences.ts` in `../pelines-dash-forge/src`. Flutter evidence: Location, AutoAcceptSettings, LocationsRepository, StoreOperationsController, AutoAcceptController, BusinessHoursSchedule and their editors/tests. No backend source/OpenAPI is present in the supplied projects; web PATCH usage alone does not establish server validation or operational enforcement.

## Capability classification before implementation

| Production control | Contract / Flutter equivalent | Classification and decision |
| --- | --- | --- |
| Accepting online orders | PATCH locations/:id, isAcceptingOrders; existing preflight/reconciliation controller | Supported, previously exposed elsewhere. Reuse exact switch, confirmation and mutation in Pickup. This affects regular AND catering orders; not a pickup-only enable flag. |
| Location active | isActive is read by Location and active-location selection; web PATCH writes it | Endpoint used by web but no Flutter mutation. Omitted; disabling affects location visibility and selection. No new activation contract inferred. |
| Auto-accept regular/catering | servicePrefsJson.autoAcceptRegular / autoAcceptCatering; saveAutoAcceptSettings | Supported with editor elsewhere. Reuse summary and original editor, provider, confirmations, conflict checks, busy states and errors. |
| Accept regular/catering | servicePrefsJson.acceptRegular / acceptCatering | Web endpoint available, not consumed by Flutter as editable settings. Preserved as opaque JSON by existing mutation. Omitted pending validated mobile contract; not claimed absent from backend. |
| Minimum regular/catering order | servicePrefsJson.minRegular / minCatering | Same unconsumed web PATCH contract. No safe typed Flutter mutation. Omitted. Delivery minimum fields are NOT substituted. |
| Daily capacity regular/catering | servicePrefsJson.capRegular / capCatering | Same unconsumed contract. Catering capacity is per delivery/pickup date in web config. Omitted. |
| Auto-cancel regular/catering | servicePrefsJson.autoCancel{Regular,Catering}{Enabled,Value,Unit} | Same unconsumed contract. Web allows minutes/hours, validates regular 1–1440 minutes and catering 10–10080 minutes. Omitted. These are cancellation deadlines, NOT preparation time. |
| Enable Pickup independently | No independent field/control in this production route or typed Flutter contract | Not supported by available evidence. No simulated switch. |
| Pickup availability | Production uses location-wide flags and service preferences above | Only the supported location-wide ordering mutation is exposed, with its existing explicit warning. |
| Hours | No hours component in production Pickup route; Flutter hoursJson is shared Business Hours | Supported UI elsewhere (Locations). Not duplicated and not relabeled pickup hours. |
| Preparation / lead time | No control/field in this production route or related form/config; no typed Flutter location field/mutation | Not supported by available evidence. No input or translation added. |
| Restrictions / other settings | Minimums, capacity, accept and auto-cancel above are the full connected form | No other pickup restriction inferred. |

Web turns auto-accept off locally when the matching accept flag is disabled and restores its previous value when re-enabled. It validates nonnegative minimums and integer capacities. Existing Flutter auto-accept semantics and safety flow remain unchanged as requested; no wholesale web-default JSON writes are introduced.

## Final screen

`/app/store/pickup-settings` builds `PickupSettingsScreen`, not StoreOperationsScreen. It has a Bree Serif header, selected location badge, EN/ES description, ordering card with existing switch/warning, and auto-accept summary/Edit action. It uses the shared operations library solely to reuse existing controls without copying operational logic. The separate editor retains all existing behavior (including its pre-existing English literal confirmation/error text).

One scrollable column on phone, tablet and wide screens preserves production's sequential availability/preferences hierarchy. Existing dashboard maximum width bounds the content. Cards grow with content and text scale; interactive targets use the existing >=48-pixel design-system sizing. No contact, closures, delivery, printer, promotions or new decorative inputs are included.

Only the pickup route builder changes; navigation destinations, guards, Locations 10.3D and other screens retain their existing behavior. Legacy internal StoreOperationsSection.pickup remains untouched for compatibility.

## Validation

See final delivery for executed test/analyze results. New pickup widget tests cover EN/ES, 320/390/768/1400 widths at 1x and 2x text, editor navigation, exclusions, named ordering confirmation/cancel, busy/error, selected-location updates, unsupported preferences, loading/retry and empty selection. Existing auto-accept and ordering suites verify actual mutation, confirmation, conflict and reconciliation behavior. Existing router tests cover the registered destination and authentication guards.

Final validation: 20/20 new Pickup tests passed; 62/62 existing tests across auto_accept_test, store_operations_test, router_test, locations_parity_test and business_hours_test passed. Responsive coverage is widget-level, not device screenshots. flutter analyze reported no issues. git diff --check returned 0. No commits or pushes were made.

Files changed by this block: lib/app/router.dart (pickup builder only), lib/app/l10n/catalog.dart (one description), lib/features/locations/presentation/store_operations_screen.dart (part declaration only), lib/features/locations/presentation/pickup_settings_screen.dart (new), test/pickup_settings_test.dart (new), docs/pickup-settings-10.3e.md (new). Existing working-tree edits were preserved.
