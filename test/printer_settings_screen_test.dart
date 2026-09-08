
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/printing/data/printing_database.dart';
import 'package:pelines_admin_app/features/printing/models/print_job.dart';
import 'package:pelines_admin_app/features/printing/models/print_result.dart';
import 'package:pelines_admin_app/features/printing/presentation/printer_settings_screen.dart';
import 'package:pelines_admin_app/features/printing/providers/printing_providers.dart';

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
          expect(
            find.textContaining('TEST · test · Submitted'),
            findsOneWidget,
          );
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
