# Printing Block 2 — Network ESC/POS

This block supersedes the deferred Epson SDK proposal. It implements manual TCP
printing entirely in Dart, without Epson SDK libraries or a Flutter printing
plugin. Physical output has not been tested on a TM-m30II. Accept and scheduled
auto-print remain outside this block.

## Official references and protocol decisions

- [TM-m30II Technical Reference Guide, Rev F](https://download4.epson.biz/sec_pubs/bs/pdf/TM-m30II_trg_en_revF.pdf):
  direct printing uses bidirectional TCP port 9100 (pp. 107/109); only one
  connection can print at a time. Port 9100 is an editable default, not a
  discovered capability. The printer's configured network interface must be
  reachable from the tablet. The guide describes 80/58 mm paper and 48/35 versus
  42/32 column modes. Interface configuration can be printed on a status sheet
  (p. 72). This app does not change network or persistent paper settings.
- [TM-m30II supported ESC/POS commands](https://download4.epson.biz/sec_pubs/pos/reference_en/escpos/tmm30ii.html):
  model-specific support includes text, graphics, cutting and status commands.
- [Initialize](https://download4.epson.biz/sec_pubs/pos/reference_en/escpos/esc_atsign.html),
  [alignment](https://download4.epson.biz/sec_pubs/pos/reference_en/escpos/esc_la.html),
  [emphasis](https://download4.epson.biz/sec_pubs/pos/reference_en/escpos/esc_ce.html),
  [font](https://download4.epson.biz/sec_pubs/pos/reference_en/escpos/esc_cm.html),
  [size](https://download4.epson.biz/sec_pubs/pos/reference_en/escpos/gs_exclamation.html),
  [feed](https://download4.epson.biz/sec_pubs/pos/reference_en/escpos/esc_ld.html),
  [cut](https://download4.epson.biz/sec_pubs/pos/reference_en/escpos/gs_cv.html):
  renderer uses initialization, Font A, alignment/emphasis, double-sized order
  number, line feed and feed-to-cut-position with partial cut. No cash-drawer
  pulse, persistent setting writes, firmware changes or NV-memory writes.
- [Character page selection](https://download4.epson.biz/sec_pubs/pos/reference_en/escpos/esc_lt.html)
  documents page 16 / WPC1252. [Encoding mode](https://download4.epson.biz/sec_pubs/pos/reference_en/escpos/fs_lparen_cc_fn48.html)
  selects character-table mode explicitly rather than inheriting UTF-8 mode.
- [Real-time status](https://download4.epson.biz/sec_pubs/pos/reference_en/escpos/dle_eot.html)
  supports printer/offline/error/paper observations. Status parsing, ASB framing,
  correlation and reliable job-completion evidence are deferred to Block 2.1.
  A ready printer is not proof that a particular job printed. V1 sends no status
  requests and ignores unsolicited input; it never returns `confirmed`.
- Graphics are supported by the model (GS ( L / GS 8 L); bitmap/logo rendering
  is deferred. The ticket uses the text heading PELINES.

## Architecture and safety

`TicketBuilder → TicketDocument → PrintOrderService → SQLite PrintJob →
PrintQueue → SelectedPrinterAdapter → FakePrinterAdapter OR
NetworkEscPosPrinterAdapter → EscPosTicketRenderer → PrinterSocket → Dart Socket`.

The existing domain, queue worker, CAS status updates, SQLite schema and dedupe
index remain unchanged. Network configuration extends the JSON settings
document, with defaults when older Block 1 settings are loaded.

`PrintingRuntime.saveSettings` serializes configuration changes, pauses new
queue dispatch, waits for the active worker and then switches the adapter.
Network printer identity includes location, normalized host and port. A queued
job for an old endpoint is never redirected to a new one. Restore its original
endpoint to process it, or cancel the pending job. An IP/DNS identity is not a
hardware serial number: use a DHCP reservation to avoid address reassignment.

Network jobs connect per attempt, even if the previous connection test failed.
There is no automatic retry. `failedBeforeSend` permits manual retry; `unknown`
does not. Test jobs use their own purpose and unique order IDs. Initial order
dedupe, explicit reprints, persistence before send and restart recovery
(`sending → unknown`) retain Block 1 behavior. Leaving Settings does not dispose
the app-scoped worker; sign-out pauses dispatch after the current attempt.

## Configuration and UI

Per-location JSON stores printer type, display name, host, integer port, printer
identity, enabled state and existing future auto-print preferences. No passwords.
Only one location is enabled per tablet. V1 accepts IPv4 and ASCII DNS hostnames;
it rejects URLs, inline ports, paths, credentials, invalid IPv4, empty locations,
empty names and ports outside 1–65535. IPv6 and discovery are deferred.

Choose Network Epson / ESC-POS, edit fields, Save Printer, then enable printing.
Unsaved configuration disables Test Print. Test Connection may inspect valid
draft fields without saving, enabling printing, creating a job or sending bytes.
Its `Printer reachable` result proves only that a TCP endpoint accepted a
connection. It does not identify the model, paper state or ESC/POS readiness.
All probe sockets are closed. The displayed result is the last test observation.

Test Print creates a diagnostic TicketDocument through PrintOrderService, saves
it as a test job and uses the normal queue. Its timestamp is persisted. The
diagnostic includes location, printer name, Spanish examples and TEST ONLY.
Totals are diagnostic zeroes; unknown payment is not described as paid.

## Renderer and encoding

The neutral ticket supplies all business values. Renderer formats location,
fulfillment/order type, order number, customer/phone, Pacific placed/scheduled
time or ASAP, items/quantities/base unit and line prices, modifiers, instructions,
notes, fees, tip, delivery, discount/code, tax, total, amount paid and available
card metadata. Delivery/event maps are rendered as wrapped JSON text in V1.
Amounts use integer cents; the renderer does not recompute business totals.

Default `EscPosPaperProfile.paper80` uses 42 columns with Font A: a conservative
fit for either 80 mm character mode. It also provides a 32-column `paper58`
profile in code, not in Settings yet. This does not configure physical paper.
Double-sized headings wrap at half the profile width. Text wraps by encoded
characters and long words are split without truncation. No HTML is generated.

WPC1252 supports á é í ó ú ñ ü ¿ ¡ and uppercase equivalents. Common decomposed
Spanish forms are composed before encoding. Other unrepresentable Unicode
(including emoji/CJK), unsupported combining sequences and control characters
fail the entire render **before connecting**. They are never silently replaced
with question marks or interpreted as printer commands. The manager receives
an unsupported-character message. A future raster/Unicode renderer can extend
coverage without changing domain or transport contracts.

## Transport results and deadlines

Connect: 4 seconds; flush: 8 seconds; close: 2 seconds. Late connections after
timeout are destroyed. Every attempt releases its socket; stream errors are
consumed and mapped instead of escaping into the UI.

| Result | Meaning in this adapter |
| --- | --- |
| failedBeforeSend | Validation/render/connect failed before any write was attempted. |
| submitted | Write, flush and close completed without an observed error. Physical output is unverified. |
| unknown | An error/timeout occurred after the first write was attempted, including close failure. Some or all bytes may have reached the printer. |
| confirmed | Never returned by this network adapter. Fake can still simulate it. |

Socket flush is not a printer receipt or physical-output acknowledgement; see
[Dart Socket](https://api.dart.dev/dart-io/Socket-class.html). Online/paper/cover/
busy/cutter errors are not reported by V1. Review paper physically after sending.

## Android and future iPad

Android already has INTERNET. No manifest/Gradle/Kotlin changes or new Bluetooth,
location, USB, storage or notification permissions. No Epson JAR/SO or SDK.
Raw TCP is unencrypted and should stay on the restaurant LAN; do not expose the
printer port publicly. This is not a Windows Surface printing implementation.

Dart models, settings, queue, renderer and socket adapter can be reused on iOS.
The iOS block must add an appropriate NSLocalNetworkUsageDescription and test
permission denial/recovery on actual iPads, per [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).
Manual unicast TCP does not require Bonjour discovery or a Bluetooth/MFi route.
No iOS files were changed; the current delivery is an Android technical build.

## First restaurant test (Android for this block)

1. Build a debug APK with the usual authorized Pelines client configuration
   (APP_ENV, API_BASE_URL, SUPABASE_URL, SUPABASE_ANON_KEY). The bare
   `flutter build apk --debug` validation artifact has no dart-defines and
   therefore opens the existing configuration-error screen; it is a compilation
   check, not a configured restaurant APK. For the physical test use
   `flutter build apk --debug --dart-define-from-file="C:\path\pelines-client-config.json"`
   with your existing local configuration, then install that debug APK on a
   development Android tablet. Keep the approved Manager Test APK unchanged.
   Sign in and select the correct Pelines location.
2. Put tablet and printer on the same reachable restaurant LAN. Avoid guest
   Wi-Fi/client isolation. A wired printer and Wi-Fi tablet can share the LAN.
   Make sure another POS client is not holding the print connection.
3. Obtain the active printer IP from its interface status sheet. Epson's method:
   printer powered on and ready, roll cover closed; remove bottom cover if
   present and hold the status-sheet button at least three seconds. Do not hold
   it while powering on (that is a different operation). See guide p. 72.
4. Confirm the selected printer's model, paper width and raw TCP configuration.
   Reserve its IP in DHCP if possible. V1 Settings expects 80 mm paper.
5. Open Admin → Printer Settings; choose Network Epson / ESC-POS.
6. Enter a recognizable name, the IP/hostname and port (normally 9100).
7. Tap Test Connection. Expect Printer reachable. On failure, check address,
   port, LAN isolation and other active clients; this operation uses no paper.
8. Tap Save Printer, then Enable Printing on This Tablet for this location.
9. Tap Test Print once. The job should transition through the persisted queue
   to Submitted. Observe the printer and inspect the ticket/cut separately.
10. Verify location/time, José, Piña, Jalapeño, Tortilla española, ¿Sin cebolla?,
    accents, columns and cut. Record model/firmware/paper mode and any issue.
    For Unknown or Submitted without paper, investigate before creating another
    test. Only Failed before send offers a safe manual Retry.

## Validation

Automated coverage includes endpoint/config validation and legacy persistence,
Spanish and unsafe-text encoding, renderer fields/layout/cut, connection probe,
send outcome boundaries, timeouts/late sockets, an actual loopback TCP transfer,
SQLite test pipeline, adapter selection and endpoint-change serialization.
Existing Block 1 dedupe/recovery tests remain in place. Widget tests exercise
Fake and Network Settings. Run with the project's approved PUB_CACHE:

```powershell
$env:PUB_CACHE='C:\Users\HP 800G5\pub-cache-clean'
flutter analyze
flutter test
flutter build apk --debug
```

Build/test success establishes technical readiness, not printer hardware
compatibility validation. Physical output, variant/firmware, actual LAN and
paper configuration, and future iPad permission behavior remain to be checked.

Validation run on 2026-09-08: `flutter analyze` clean; `flutter test` **384 passed**
(333 existing plus 51 new); `flutter build apk --debug` succeeded. Artifact:
`build/app/outputs/flutter-apk/app-debug.apk` (ignored, compilation-only without
client dart-defines). Existing Android tooling/Kotlin plugin warnings did not
prevent the build. The approved Desktop Manager Test APK was not replaced.

Changed files: added `application/esc_pos_ticket_renderer.dart`,
`data/network_esc_pos_printer_adapter.dart`, `data/printer_socket.dart`,
`data/selected_printer_adapter.dart`, `models/network_printer_endpoint.dart`
under `lib/features/printing/`; extended `application/print_order_service.dart`,
`data/printer_settings_store.dart`, `models/printer_settings.dart`,
`presentation/printer_settings_screen.dart`, `providers/printer_controller.dart`
and `providers/printing_providers.dart`. Added `test/network_printing_test.dart`,
extended `test/printer_settings_screen_test.dart`, and added this document.
