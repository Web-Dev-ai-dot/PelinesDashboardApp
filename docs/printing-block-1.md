# Printing Block 1

Hardware-independent printing core. No Orders mutation code, Android permissions,
backend, Dashboard, physical transport, bytes, ESC/POS, XML or Epson SDK changes.

## Architecture

`OrderDetail → TicketBuilder → PrintOrderService → SQLite PrintJob → PrintQueue → PrinterAdapter`

`FakePrinterAdapter` is the only wired adapter. Transport enums describe future
Bluetooth, network, USB and Epson SDK support; they do not enable it.

- `models/`: printer/capabilities/settings, immutable ticket snapshot, jobs and typed results.
- `data/`: adapter interface/fake, SQLite database, job and settings stores.
- `application/`: ticket builder, explicit eligibility, enqueue services, serial queue.
- `providers/`: application-scoped runtime plus Riverpod settings/job subscriptions.
- `presentation/`: authenticated PrintingShell and Printer Settings.

Orders Accept is unchanged. There are no automatic callers for initial printing
and no scheduler. Automatic preference switches only persist future configuration.
Initial service requests accept paid, known-type orders in confirmed/preparing/ready
at an enabled configured location. The future Regular ASAP predicate additionally
requires online, confirmed, no scheduledFor and the Regular ASAP preference.
Explicit reprints also allow paid delivered orders.

## Ticket contract

All monetary values are integer cents. Base unit price is the canonical unit price
minus modifier deltas (the backend already includes modifiers in unitPriceCents).
Line totals and quantity remain separately available. Unknown/non-paid payments
retain their status and have null amountPaidCents; no payment is invented.
Regular/Catering, Pickup/Delivery, event data, delivery address, modifiers, product
instructions, customer notes, fees, tax, discounts and card metadata are retained.
No internal notes are implicitly printed. Nested snapshot collections are immutable.
Instants persist as UTC; presentation uses the existing PelinesTime Pacific helper.

## Persistence and dependencies

- `sqflite 2.4.3` (runtime): established Android/iOS SQLite plugin, transactions,
  database migration versioning, background database execution. Uses platform SQLite.
- `sqflite_common_ffi 2.3.6` (dev only): real SQLite tests on Windows, with bundled DLL.
- `sqlite3 2.9.4` (dev only, constraint >=2.7.6 <3): avoids the sqlite3 3.x native-assets
  hook failure with the current Windows SDK path containing spaces. FFI 2.3.6 is pinned
  deliberately; no SDK paths or test DLL binaries are checked into the repository.

References: https://pub.dev/packages/sqflite and
https://pub.dev/packages/sqflite_common_ffi/versions/2.3.6

Database: `pelines_printing.db` in the platform application database directory,
schema version 1, SQLite synchronous FULL. Jobs contain indexed identity/status
columns and a JSON ticket/job snapshot. Settings use the same transactional database,
not the fault-tolerant alert store. Write errors propagate to the service/UI or halt
the queue; they are not treated as successful persistence.

Settings are local to the installation, keyed by location. Only one location is
enabled per tablet; enabling another atomically disables the previous one while
retaining its preferences. Default lead time is 20 minutes. This is not a lease
across tablets. Clearing app data/uninstalling removes local history. Backup/restore
and device replacement need an operational policy before physical deployment.

## Job states and deduplication

`queued → sending → submitted | confirmed | failedBeforeSend | unknown`

- Persist queued before making work available; persist sending before calling adapter.
- One serial worker for the configured printer; CAS status updates prevent stale claims.
- submitted means accepted by transport, not physically confirmed.
- confirmed in this block is explicitly simulated.
- failedBeforeSend supports manual retry of the same job (attempt count increments).
- unknown has no retry action. Operator may review and close it as cancelled.
- queued/failedBeforeSend/unknown can be closed via the queue's cancel contract.
- Terminal initial jobs continue to reserve the initial identity. An intentional
  reprint creates a new job and references the original initial job if it exists.

Initial uniqueness is `(location_id, order_id)` in a partial UNIQUE index where
purpose = initial. Transactional insert returns the existing initial job under
concurrent calls. UUID/order ID is used, never the visual order number. Reprints and
tests have separate random 128-bit IDs and are not blocked by that index.

On startup queued jobs remain queued and sending becomes unknown in a transaction.
When an authenticated shell activates, a configured/enabled fake printer reconnects
and queued work resumes. Leaving Settings does not stop the application-scoped queue.
Signing out pauses dispatch; an already started job is allowed to record its result.
A storage failure halts further dispatch until application restart. If saving the
result failed after send, sending remains durable and becomes unknown next startup.
There is no automatic retry of unknown, submitted or confirmed.

No guarantee of background execution, exact scheduling or physical exactly-once
delivery is implied. Restoration occurs when the application runs again.

## Try it

1. Select a location, open the main menu → Printer Settings (`/app/printing`).
2. Enable Printing on This Tablet; Fake Printer is the only selectable printer.
3. Connect. Test Print creates a persisted purpose=test job.
4. Review Submitted (default), or choose Confirmed, Failed before send or Unknown
   under Simulation controls before another test.
5. Failed before send offers Retry. Unknown offers Review, never automatic retry.
6. Disconnect, select Simulate connection failure, and Connect to test that error.
7. Test Print while disconnected remains Queued; Connect resumes it.
8. Toggle automatic preferences or enter a lead time and press Done to save.
   These preferences do not activate automatic printing in Block 1.

Fake delay and outcomes are configurable in code/tests. Screen simulation controls
are session-local. Fake sends no data to a physical device.

## Validation coverage

`test/printing_core_test.dart`: builder mappings/serialization/immutability, payment
semantics, eligibility, concurrent initial requests, SQL uniqueness, intentional
reprints, location scope, queue serialization, all outcomes, retries, file close/reopen,
sending recovery, settings isolation, transaction rollback and storage write failures.

`test/printer_settings_screen_test.dart`: existing Pelines theme, location/configuration,
Connect/Test Print, submitted wording and queue completion after leaving the screen.

Required checks use PUB_CACHE configured by the project owner:

```powershell
$env:PUB_CACHE="C:\Users\HP 800G5\pub-cache-clean"
flutter analyze
flutter test
```

Android device/release integration and hardware behavior are not covered by these
host tests. No APK is generated for this block.

Validation on this implementation: `flutter analyze` reported no issues;
`flutter test` passed all 333 tests, including 31 new printing tests.

## Subsequent blocks

Block 2: integrate only verified acceptance results, preserve preflight/PATCH/reconciliation,
define handling of ambiguous mutations, add operational Print/Reprint UI, observe externally
accepted orders, and design Scheduled coverage/recovery. Resolve the backend 100-order
list cap before promising reliable recovery of older Scheduled orders. Coordinate the
single printing tablet and disable Web auto-print at migration. Multi-tablet leases
and distributed jobs remain future backend work.

Block 3 hardware checklist, per location/device:

- Tablet manufacturer, complete model, Android/build version, ABI and update policy.
- Bluetooth Classic/SPP versus BLE support and permissions in the app that worked.
- USB host/OTG support, port type, exact cable/hub, simultaneous charging capability.
- Printer manufacturer, full model/suffix, firmware, interface board and self-test page.
- Actual Bluetooth/Wi-Fi/Ethernet/USB interfaces; Bluetooth profile, pairing method
  and simultaneous connection limit; USB data role and VID/PID.
- Supported protocol: ESC/POS variant, ePOS XML, Epson SDK or other vendor SDK.
- Network IP/reservation, listening service/port, SSID/VLAN and client isolation.
- Paper nominal/printable width, resolution, cutter, image and Spanish character support.
- Exact successful app/version/configuration, exact failed step/error, and what the
  existing cable connects (tablet, PC, printer, router or power).
- Primary/backup tablet, sleep/power/kiosk policy, ticket copies and kitchen destinations.

## Changed files

New feature files live under `lib/features/printing/` (models, data, application,
providers and presentation as above). New tests are the two printing test files.
Existing changes are limited to `lib/app/router.dart`, the main administrative menu
in `lib/features/account/presentation/admin_home_screen.dart`, `pubspec.yaml` and
`pubspec.lock`. This document records the operational contract and dependency choice.
