import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/printing/data/printing_database.dart';
import 'package:pelines_admin_app/features/printing/data/printer_socket.dart';
import 'package:pelines_admin_app/features/printing/models/network_printer_endpoint.dart';
import 'package:pelines_admin_app/features/printing/models/printer.dart';
import 'package:pelines_admin_app/features/printing/models/print_job.dart';
import 'package:pelines_admin_app/features/printing/models/print_result.dart';
import 'package:pelines_admin_app/features/printing/presentation/printer_settings_screen.dart';
import 'package:pelines_admin_app/features/printing/providers/printing_providers.dart';
import 'package:pelines_admin_app/features/printing/application/ticket_builder.dart';

import 'order_test_data.dart';

class _Location extends CurrentLocationController {
  @override
  Future<Location?> build() async => Location(
    id: 'location-id',
    name: 'Troutdale',
    slug: 'troutdale',
    isActive: true,
    deliveryFeeCents: 0,
    deliveryMinimumCents: 0,
    isAcceptingOrders: true,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

void main() {
  sqfliteFfiInit();
  _block8PrinterTests();
  for (final (width, height, scale) in <(double, double, double)>[
    (390, 844, 1),
    (320, 700, 2),
    (768, 1024, 1.5),
  ]) {
    testWidgets('printer controls fit at $width with text scale $scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, height));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        final runtime = PrintingRuntime(
          await openPrintingDatabase(
            factory: databaseFactoryFfiNoIsolate,
            path: inMemoryDatabasePath,
          ),
          connector: _Connector(),
        );
        await runtime.start();
        final container = ProviderContainer(
          overrides: [
            printingRuntimeProvider.overrideWith((ref) async => runtime),
            currentLocationProvider.overrideWith(_Location.new),
          ],
        );
        Future<void> settle() async {
          for (var i = 0; i < 8; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
          }
          expect(tester.takeException(), isNull);
        }

        Future<void> reach(Finder finder) async {
          await tester.scrollUntilVisible(
            finder,
            180,
            scrollable: find.byType(Scrollable).first,
            maxScrolls: 80,
          );
          await settle();
          expect(finder.hitTestable(), findsOneWidget);
        }

        try {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: AppTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const PrinterSettingsScreen(),
              ),
            ),
          );
          await settle();
          // Exercise the longest simulation label in both the field and popup.
          final outcome = find.byType(DropdownButtonFormField<PrintOutcome>);
          await reach(outcome);
          final outcomeHeight = tester.getSize(outcome).height;
          expect(outcomeHeight, greaterThanOrEqualTo(48));
          final selectedOutcome = find.descendant(
            of: outcome,
            matching: find.text('Submitted (not physical confirmation)'),
          );
          expect(tester.widget<Text>(selectedOutcome).maxLines, 1);
          expect(
            tester.widget<Text>(selectedOutcome).overflow,
            TextOverflow.ellipsis,
          );
          await tester.tap(outcome);
          await settle();
          await tester.tap(
            find.text('Submitted (not physical confirmation)').last,
          );
          await settle();
          // Return to the top before locating the lazily built transport field.
          await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
          await settle();
          final transport = find.byType(
            DropdownButtonFormField<PrinterTransport>,
          );
          await reach(transport);
          final transportHeight = tester.getSize(transport).height;
          expect(transportHeight, closeTo(outcomeHeight, 1));
          await tester.tap(transport);
          await settle();
          await tester.tap(find.text('Network Epson / ESC-POS').last);
          await settle();
          expect(tester.getSize(transport).height, closeTo(transportHeight, 1));
          final selectedTransport = find.descendant(
            of: transport,
            matching: find.text('Network Epson / ESC-POS'),
          );
          expect(tester.widget<Text>(selectedTransport).maxLines, 1);
          final chevron = find.descendant(
            of: transport,
            matching: find.byIcon(Icons.arrow_drop_down),
          );
          expect(
            (tester.getCenter(selectedTransport).dy -
                    tester.getCenter(chevron).dy)
                .abs(),
            lessThanOrEqualTo(2),
          );
          await reach(find.widgetWithText(TextField, 'IP address / hostname'));
          await tester.enterText(
            find.widgetWithText(TextField, 'IP address / hostname'),
            '192.168.1.50',
          );
          await settle();
          final probe = find.widgetWithText(FilledButton, 'Test Connection');
          await reach(probe);
          expect(tester.getSize(probe).height, greaterThanOrEqualTo(48));
          await tester.tap(probe);
          await settle();
          await tester.scrollUntilVisible(
            find.text('Connection status: Printer reachable'),
            -120,
            scrollable: find.byType(Scrollable).first,
          );
          await settle();
          expect(
            find.text('Connection status: Printer reachable'),
            findsOneWidget,
          );
          await reach(find.widgetWithText(FilledButton, 'Test Print'));
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Test Print'),
                )
                .onPressed,
            isNull,
          );
          expect(await runtime.jobs.list(), isEmpty);
          for (final status in [
            PrintJobStatus.failedBeforeSend,
            PrintJobStatus.unknown,
            PrintJobStatus.queued,
          ]) {
            final now = DateTime.utc(2026, 9, 12);
            await runtime.jobs.insert(
              PrintJob(
                id: status.name,
                orderId: status.name,
                locationId: 'location-id',
                purpose: PrintPurpose.test,
                status: status,
                createdAt: now,
                updatedAt: now,
                printerId: 'fake',
                ticket: const TicketBuilder().build(orderDetail()),
                lastError: 'A long connection message that must wrap without hiding the job action or overlapping its text.',
              ),
            );
          }
          await settle();
          for (final label in ['Cancel', 'Review', 'Retry']) {
            final action = find.widgetWithText(TextButton, label);
            await tester.scrollUntilVisible(
              action,
              180,
              scrollable: find.byType(Scrollable).first,
              maxScrolls: 80,
            );
            await Scrollable.ensureVisible(
              tester.element(action),
              alignment: 0.5,
            );
            await settle();
            expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
            expect(tester.getRect(action).bottom, lessThanOrEqualTo(height));
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          await runtime.dispose();
        }
      });
    });
  }

  testWidgets(
    'network form validates, probes without job, saves and prints via queue',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        final connector = _Connector();
        final runtime = PrintingRuntime(
          await openPrintingDatabase(
            factory: databaseFactoryFfiNoIsolate,
            path: inMemoryDatabasePath,
          ),
          connector: connector,
        );
        runtime.adapter.delay = Duration.zero;
        await runtime.start();
        runtime.active = true;
        final container = ProviderContainer(
          overrides: [
            printingRuntimeProvider.overrideWith((ref) async => runtime),
            currentLocationProvider.overrideWith(_Location.new),
          ],
        );
        Future<void> settle() async {
          for (var i = 0; i < 8; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
          }
        }

        try {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: AppTheme.light,
                home: const PrinterSettingsScreen(),
              ),
            ),
          );
          await settle();
          await tester.tap(
            find.byType(DropdownButtonFormField<PrinterTransport>),
          );
          await settle();
          await tester.tap(find.text('Network Epson / ESC-POS').last);
          await settle();
          expect(find.text('IP address / hostname'), findsOneWidget);
          expect(find.text('Simulation controls'), findsNothing);
          final printFinder = find.widgetWithText(FilledButton, 'Test Print');
          expect(tester.widget<FilledButton>(printFinder).onPressed, isNull);
          final probeFinder = find.widgetWithText(
            FilledButton,
            'Test Connection',
          );
          expect(tester.widget<FilledButton>(probeFinder).onPressed, isNull);
          final host = find.widgetWithText(TextField, 'IP address / hostname');
          await tester.enterText(host, 'http://printer');
          await settle();
          expect(tester.widget<FilledButton>(probeFinder).onPressed, isNull);
          await tester.enterText(host, '192.168.1.50');
          await tester.enterText(
            find.widgetWithText(TextField, 'Port'),
            '9200',
          );
          await settle();
          await tester.ensureVisible(probeFinder);
          await tester.tap(probeFinder);
          await settle();
          expect(
            find.text('Connection status: Printer reachable'),
            findsOneWidget,
          );
          expect(await runtime.jobs.list(), isEmpty);
          expect(connector.sockets.single.bytes, isEmpty);
          expect(connector.sockets.single.closed, isTrue);
          await tester.ensureVisible(find.text('Save Printer'));
          await tester.tap(find.text('Save Printer'));
          await settle();
          var settings = await runtime.settings.read('location-id');
          expect(settings.transport, PrinterTransport.network);
          expect(settings.port, 9200);
          expect(settings.enabled, isFalse);
          await tester.ensureVisible(
            find.text('Enable Printing on This Tablet'),
          );
          await tester.tap(find.text('Enable Printing on This Tablet'));
          await settle();
          await tester.ensureVisible(printFinder);
          await tester.tap(printFinder);
          await settle();
          await runtime.queue.idle;
          expect(
            (await runtime.jobs.list()).single.status,
            PrintJobStatus.submitted,
          );
          expect(connector.sockets.last.bytes, isNotEmpty);
          expect(runtime.adapter.printCalls, 0);
          await tester.ensureVisible(host);
          await tester.enterText(host, '192.168.1.51');
          await settle();
          expect(tester.widget<FilledButton>(printFinder).onPressed, isNull);
          expect(find.text('Connection status: Not tested'), findsOneWidget);
          // Leaving with an unsaved edit retains the saved endpoint.
          await tester.pumpWidget(const SizedBox.shrink());
          settings = await runtime.settings.read('location-id');
          expect(settings.host, '192.168.1.50');
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          await runtime.dispose();
        }
      });
    },
  );
  testWidgets(
    'settings saves preferences, processes fake test, survives screen exit',
    (tester) async {
      await tester.runAsync(() async {
        final db = await openPrintingDatabase(
          factory: databaseFactoryFfiNoIsolate,
          path: inMemoryDatabasePath,
        );
        final runtime = PrintingRuntime(db);
        runtime.adapter.delay = Duration.zero;
        await runtime.start();
        runtime.active = true;
        final container = ProviderContainer(
          overrides: [
            printingRuntimeProvider.overrideWith((ref) async => runtime),
            currentLocationProvider.overrideWith(_Location.new),
          ],
        );
        Future<void> settle() async {
          for (var i = 0; i < 8; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
          }
        }

        try {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: AppTheme.light,
                home: const PrinterSettingsScreen(),
              ),
            ),
          );
          await settle();
          expect(find.text('Printer Settings'), findsOneWidget);
          expect(find.text('Troutdale'), findsOneWidget);
          expect(
            find.text('Simulation only. No physical printer is connected.'),
            findsOneWidget,
          );
          await tester.tap(find.text('Enable Printing on This Tablet'));
          await settle();
          expect((await runtime.settings.read('location-id')).enabled, isTrue);
          await tester.tap(find.text('Connect'));
          await settle();
          expect(find.text('Status: connected'), findsOneWidget);
          await tester.tap(find.text('Test Print'));
          await settle();
          await runtime.queue.idle;
          await settle();
          final jobs = await runtime.jobs.list();
          expect(jobs.single.purpose, PrintPurpose.test);
          expect(jobs.single.status, PrintJobStatus.submitted);
          await tester.drag(find.byType(ListView), const Offset(0, -900));
          await settle();
          expect(find.textContaining('TEST · test'), findsOneWidget);
          expect(find.text('Submitted'), findsOneWidget);
          expect(find.text('Printed successfully'), findsNothing);
          runtime.adapter.delay = const Duration(milliseconds: 100);
          runtime.adapter.outcome = PrintOutcome.unknown;
          final second = await runtime.service.queueTestPrint('location-id');
          await tester.pumpWidget(const SizedBox.shrink());
          await runtime.queue.idle;
          expect(
            (await runtime.jobs.get(second.id))!.status,
            PrintJobStatus.unknown,
          );
          expect(runtime.adapter.printCalls, 2);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          await runtime.dispose();
        }
      });
    },
  );
}

class _Connector implements PrinterSocketConnector {
  final sockets = <_Socket>[];
  @override
  Future<PrinterSocket> connect(
    NetworkPrinterEndpoint endpoint,
    Duration timeout,
  ) async {
    final socket = _Socket();
    sockets.add(socket);
    return socket;
  }
}

class _Socket implements PrinterSocket {
  final bytes = <int>[];
  bool closed = false;
  @override
  void add(List<int> value) => bytes.addAll(value);
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  void destroy() {
    closed = true;
  }
}

void _block8PrinterTests() {
  for (final size in [
    (390.0, 1.0),
    (768.0, 1.0),
    (1400.0, 1.0),
    (320.0, 2.0),
  ]) {
    for (final lang in ['en', 'es']) {
      testWidgets('printer sections and jobs ${size.$1} ${size.$2} $lang', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(size.$1, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.runAsync(() async {
          final runtime = PrintingRuntime(
            await openPrintingDatabase(
              factory: databaseFactoryFfiNoIsolate,
              path: inMemoryDatabasePath,
            ),
            connector: _Connector(),
          );
          await runtime.start();
          for (final status in [
            PrintJobStatus.unknown,
            PrintJobStatus.failedBeforeSend,
            PrintJobStatus.submitted,
          ]) {
            final now = DateTime.utc(2026, 9, 12);
            await runtime.jobs.insert(
              PrintJob(
                id: status.name,
                orderId: status.name,
                locationId: 'location-id',
                purpose: PrintPurpose.test,
                status: status,
                createdAt: now,
                updatedAt: now,
                printerId: 'fake',
                ticket: const TicketBuilder().build(orderDetail()),
                lastError: 'Backend diagnostic stays unchanged',
              ),
            );
          }
          final container = ProviderContainer(
            overrides: [
              printingRuntimeProvider.overrideWith((ref) async => runtime),
              currentLocationProvider.overrideWith(_Location.new),
            ],
          );
          Future<void> settle() async {
            for (var i = 0; i < 8; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              await tester.pump();
            }
            expect(tester.takeException(), isNull);
          }

          try {
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: MaterialApp(
                  theme: AppTheme.light,
                  locale: Locale(lang),
                  supportedLocales: AdminLocalizations.supportedLocales,
                  localizationsDelegates: const [
                    AdminLocalizations.delegate,
                    ...GlobalMaterialLocalizations.delegates,
                  ],
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(size.$2)),
                    child: child!,
                  ),
                  home: const PrinterSettingsScreen(),
                ),
              ),
            );
            await settle();
            expect(find.text('Troutdale'), findsOneWidget);
            expect(
              find.byKey(const Key('printer-device-card')),
              findsOneWidget,
            );
            for (final key in [
              'printer-connection-card',
              'printer-preferences-card',
              'print-jobs-table',
            ]) {
              await tester.scrollUntilVisible(
                find.byKey(Key(key)),
                250,
                scrollable: find.byType(Scrollable).first,
                maxScrolls: 80,
              );
              await settle();
            }
            if (size.$1 == 1400) {
              expect(find.byType(DataTable), findsOneWidget);
            } else {
              expect(
                find.byKey(const Key('print-job-unknown')),
                findsOneWidget,
              );
            }
            expect(
              find.textContaining('Backend diagnostic stays unchanged'),
              findsWidgets,
            );
            final review = find.widgetWithText(
              TextButton,
              lang == 'es' ? 'Revisar' : 'Review',
            );
            await tester.ensureVisible(review);
            await settle();
            await tester.tap(review);
            await settle();
            expect(find.byType(AlertDialog), findsOneWidget);
            Navigator.of(tester.element(find.byType(AlertDialog))).pop(false);
            await settle();
            expect(
              (await runtime.jobs.list()).where(
                (j) => j.status == PrintJobStatus.unknown,
              ),
              hasLength(1),
            );
            expect(runtime.adapter.printCalls, 0);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            container.dispose();
            await runtime.dispose();
          }
        });
      });
    }
  }
}
