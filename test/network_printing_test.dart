import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/printing/application/esc_pos_ticket_renderer.dart';
import 'package:pelines_admin_app/features/printing/application/ticket_builder.dart';
import 'package:pelines_admin_app/features/printing/data/network_esc_pos_printer_adapter.dart';
import 'package:pelines_admin_app/features/printing/data/printer_socket.dart';
import 'package:pelines_admin_app/features/printing/data/printing_database.dart';
import 'package:pelines_admin_app/features/printing/models/network_printer_endpoint.dart';
import 'package:pelines_admin_app/features/printing/models/print_job.dart';
import 'package:pelines_admin_app/features/printing/models/print_result.dart';
import 'package:pelines_admin_app/features/printing/models/printer.dart';
import 'package:pelines_admin_app/features/printing/models/printer_settings.dart';
import 'package:pelines_admin_app/features/printing/providers/printing_providers.dart';

import 'order_test_data.dart';

PrinterSettings network({
  String location = 'location-id',
  String host = '192.168.1.50',
  int port = 9100,
}) => PrinterSettings(
  locationId: location,
  enabled: true,
  transport: PrinterTransport.network,
  printerId: NetworkPrinterEndpoint.parse(host, port).printerId(location),
  host: host,
  port: port,
);

PrintJob job({String? notes, PrinterSettings? config}) {
  final settings = config ?? network();
  final json = orderJson(status: 'confirmed')..['notes'] = notes;
  final ticket = const TicketBuilder().build(OrderDetail.fromJson(json));
  return PrintJob(
    id: 'job',
    orderId: ticket.orderId,
    locationId: settings.locationId,
    purpose: PrintPurpose.test,
    status: PrintJobStatus.sending,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    printerId: settings.printerId,
    ticket: ticket,
  );
}

class TestSocket implements PrinterSocket {
  final bytes = <int>[];
  int adds = 0, flushes = 0, closes = 0, destroys = 0;
  Object? addError, flushError, closeError;
  Completer<void>? flushGate, closeGate;
  @override
  void add(List<int> value) {
    adds++;
    bytes.addAll(value);
    if (addError != null) throw addError!;
  }

  @override
  Future<void> flush() async {
    flushes++;
    if (flushError != null) throw flushError!;
    await flushGate?.future;
  }

  @override
  Future<void> close() async {
    closes++;
    if (closeError != null) throw closeError!;
    await closeGate?.future;
  }

  @override
  void destroy() {
    destroys++;
  }
}

class TestConnector implements PrinterSocketConnector {
  final sockets = <TestSocket>[];
  Object? error;
  TestSocket Function()? makeSocket;
  Completer<PrinterSocket>? gate;
  Future<void> Function()? beforeConnect;
  int calls = 0;
  final endpoints = <NetworkPrinterEndpoint>[];
  @override
  Future<PrinterSocket> connect(
    NetworkPrinterEndpoint endpoint,
    Duration timeout,
  ) async {
    calls++;
    endpoints.add(endpoint);
    await beforeConnect?.call();
    if (error != null) throw error!;
    if (gate != null) return gate!.future;
    final socket = makeSocket?.call() ?? TestSocket();
    sockets.add(socket);
    return socket;
  }
}

void main() {
  sqfliteFfiInit();
  group('endpoint and settings', () {
    for (final host in [
      '',
      'http://192.168.1.2',
      '192.168.1.2:9100',
      'host/path',
      'user@host',
      '256.1.1.1',
      '1.2.3',
      '01.2.3.4',
      'a b',
      '-host',
      'a..b',
      '::1',
    ]) {
      test(
        'rejects invalid host $host',
        () => expect(
          () => NetworkPrinterEndpoint.parse(host, 9100),
          throwsFormatException,
        ),
      );
    }
    for (final port in [0, -1, 65536]) {
      test(
        'rejects port $port',
        () => expect(
          () => NetworkPrinterEndpoint.parse('printer.local', port),
          throwsFormatException,
        ),
      );
    }
    test('normalizes hostname and keeps configurable port', () {
      final endpoint = NetworkPrinterEndpoint.parse(' Kitchen.Local ', 9200);
      expect(endpoint.host, 'kitchen.local');
      expect(endpoint.port, 9200);
      expect(endpoint.printerId('one'), isNot(endpoint.printerId('two')));
    });
    test('old settings JSON remains readable with defaults', () {
      final json = const PrinterSettings(locationId: 'one').toJson()
        ..remove('host')
        ..remove('port')
        ..remove('displayName');
      final settings = PrinterSettings.fromJson(json);
      expect(settings.isValid, isTrue);
      expect(settings.port, 9100);
    });
    test('network requires complete matching identity and location', () {
      expect(network().isValid, isTrue);
      expect(network().copyWith(host: '').isValid, isFalse);
      expect(network().copyWith(port: 1).isValid, isFalse);
      expect(network().copyWith(displayName: ' ').isValid, isFalse);
      expect(network(location: ' ').isValid, isFalse);
      expect(
        network().copyWith(transport: PrinterTransport.usb).isValid,
        isFalse,
      );
    });
  });

  group('renderer', () {
    final fixtures = {
      'José': [74, 111, 115, 233],
      'Piña': [80, 105, 241, 97],
      'Jalapeño': [74, 97, 108, 97, 112, 101, 241, 111],
      'Tortilla española': [
        84,
        111,
        114,
        116,
        105,
        108,
        108,
        97,
        32,
        101,
        115,
        112,
        97,
        241,
        111,
        108,
        97,
      ],
      '¿Sin cebolla?': [
        191,
        83,
        105,
        110,
        32,
        99,
        101,
        98,
        111,
        108,
        108,
        97,
        63,
      ],
      'á é í ó ú ñ ü ¡': [
        225,
        32,
        233,
        32,
        237,
        32,
        243,
        32,
        250,
        32,
        241,
        32,
        252,
        32,
        161,
      ],
    };
    for (final entry in fixtures.entries) {
      test(
        'WPC1252 encodes ${entry.key}',
        () => expect(encodePrinterText(entry.key), entry.value),
      );
    }
    test('normalizes decomposed Spanish and Windows punctuation', () {
      expect(
        encodePrinterText('Jose\u0301 / nin\u0303o'),
        encodePrinterText('José / niño'),
      );
      expect(encodePrinterText('€ “Sí”'), [128, 32, 147, 83, 237, 148]);
    });
    test('rejects Unicode outside page and embedded printer commands', () {
      for (final value in ['🙂', '你好', '\x1b@', '\x00', '\x7f']) {
        expect(
          () => encodePrinterText(value),
          throwsA(isA<TicketEncodingException>()),
        );
      }
    });
    test('initializes page, emphasis and ends in feed plus partial cut', () {
      final bytes = const EscPosTicketRenderer().render(job().ticket);
      expect(bytes.take(2), [27, 64]);
      expect(_contains(bytes, [27, 116, 16]), isTrue);
      expect(_contains(bytes, [29, 33, 17]), isTrue);
      expect(bytes.skip(bytes.length - 7), [27, 100, 3, 29, 86, 66, 0]);
    });
    test(
      'real ticket preserves fields, cents, dates, modifiers and payment',
      () {
        final json = orderJson(status: 'confirmed')
          ..addAll({
            'location': {'name': 'Tualatin'},
            'contactName': 'José',
            'notes': '¿Sin cebolla?',
            'scheduledFor': '2026-09-08T20:00:00Z',
            'cardBrand': 'Visa',
            'cardLast4': '4242',
            'discountCode': 'SAVE',
            'subtotalCents': 1234,
            'serviceFeeCents': 15,
            'tipCents': 25,
            'deliveryFeeCents': 30,
            'discountCents': 10,
            'taxCents': 12,
            'totalCents': 1306,
            'items': [
              {
                'id': 'i',
                'productName': 'Piña',
                'quantity': 2,
                'unitPriceCents': 617,
                'lineTotalCents': 1234,
                'notes': 'Jalapeño',
                'modifiers': [
                  {
                    'id': 'm',
                    'groupName': 'Extras',
                    'optionName': 'Tortilla española',
                    'priceDeltaCents': 17,
                  },
                ],
              },
            ],
          });
        final text = latin1.decode(
          const EscPosTicketRenderer().render(
            const TicketBuilder().build(OrderDetail.fromJson(json)),
          ),
        );
        for (final expected in [
          'Tualatin',
          'José',
          '2 x Piña',
          'Jalapeño',
          'Tortilla española',
          '¿Sin cebolla?',
          'Scheduled: 2026-09-08 13:00 Pacific',
          'Visa',
          '4242',
          'SAVE',
          '\$12.34',
          '\$0.15',
          '\$0.25',
          '\$0.30',
          '-\$0.10',
          '\$0.12',
          '\$13.06',
        ]) {
          expect(text, contains(expected), reason: expected);
        }
      },
    );
    test('refunded ticket carries a REFUNDED / REEMBOLSADO stamp', () {
      String render(String payment) => latin1.decode(
        const EscPosTicketRenderer().render(
          const TicketBuilder().build(
            OrderDetail.fromJson(orderJson()..['paymentStatus'] = payment),
          ),
        ),
      );
      expect(render('refunded'), contains('REFUNDED / REEMBOLSADO'));
      expect(render('paid'), isNot(contains('REFUNDED')));
    });
    test('unpaid amount stays unknown', () {
      final json = orderJson()..['paymentStatus'] = 'pending';
      final text = latin1.decode(
        const EscPosTicketRenderer().render(
          const TicketBuilder().build(OrderDetail.fromJson(json)),
        ),
      );
      expect(text, contains('Amount paid: Unknown'));
    });
    for (final profile in EscPosPaperProfile.values) {
      test('wraps long data without loss for ${profile.name}', () {
        final text = latin1.decode(
          EscPosTicketRenderer(profile: profile)
              .render(job(notes: 'Z' * 150).ticket),
        );
        expect('Z'.allMatches(text).length, 150);
        expect(text, contains('-' * profile.columns));
        expect(
          text
              .split('\n')
              .where((line) => line.contains('Z'))
              .every(
                (line) =>
                    line
                        .replaceAll(
                          RegExp(r'\x1b[\x61\x45].|\x1d\x21.', dotAll: true),
                          '',
                        )
                        .length <=
                    profile.columns,
              ),
          isTrue,
        );
      });
    }
  });

  group('network adapter', () {
    late TestConnector connector;
    late NetworkEscPosPrinterAdapter adapter;
    setUp(() {
      connector = TestConnector();
      adapter = NetworkEscPosPrinterAdapter(
        settings: network(),
        connector: connector,
        connectTimeout: const Duration(milliseconds: 30),
        sendTimeout: const Duration(milliseconds: 30),
        closeTimeout: const Duration(milliseconds: 30),
      );
    });
    test('connection probe closes without writing', () async {
      final result = await adapter.connect();
      expect(result.message, 'Printer reachable');
      expect(result.status, PrinterStatus.connected);
      expect(connector.sockets.single.adds, 0);
      expect(connector.sockets.single.closes, 1);
      expect(connector.sockets.single.destroys, 1);
      expect(adapter.printer.capabilities.statusReporting, isFalse);
    });
    test('connection refusal is friendly failedBeforeSend', () async {
      connector.error = const SocketException('private diagnostic');
      expect((await adapter.connect()).message, 'Cannot connect to printer');
      final result = await adapter.print(job());
      expect(result.outcome, PrintOutcome.failedBeforeSend);
      expect(result.message, 'Cannot connect to printer');
    });
    test('successful write and flush is submitted, never confirmed', () async {
      expect((await adapter.print(job())).outcome, PrintOutcome.submitted);
      expect(connector.sockets.single.flushes, 1);
      expect(connector.sockets.single.closes, 1);
      expect(connector.sockets.single.destroys, 1);
    });
    for (final stage in ['add', 'flush', 'close']) {
      test(
        '$stage error after write begins is unknown and cleaned up',
        () async {
          connector.makeSocket = () {
            final socket = TestSocket();
            switch (stage) {
              case 'add':
                socket.addError = StateError('write');
              case 'flush':
                socket.flushError = StateError('flush');
              case 'close':
                socket.closeError = StateError('close');
            }
            return socket;
          };
          expect((await adapter.print(job())).outcome, PrintOutcome.unknown);
          expect(connector.sockets.single.destroys, 1);
          expect(connector.calls, 1);
        },
      );
    }
    test(
      'connect timeout is failedBeforeSend and late socket is destroyed',
      () async {
        connector.gate = Completer<PrinterSocket>();
        final result = await adapter.print(job());
        expect(result.outcome, PrintOutcome.failedBeforeSend);
        expect(result.message, 'Connection timed out');
        final lateSocket = TestSocket();
        connector.gate!.complete(lateSocket);
        await Future<void>.delayed(Duration.zero);
        expect(lateSocket.destroys, 1);
        expect(lateSocket.adds, 0);
      },
    );
    for (final stage in ['flush', 'close']) {
      test('$stage timeout is unknown and releases socket', () async {
        connector.makeSocket = () => TestSocket()
          ..flushGate = stage == 'flush' ? Completer<void>() : null
          ..closeGate = stage == 'close' ? Completer<void>() : null;
        expect((await adapter.print(job())).outcome, PrintOutcome.unknown);
        expect(connector.sockets.single.destroys, 1);
      });
    }
    test('invalid settings and wrong job identity never connect', () async {
      final invalid = NetworkEscPosPrinterAdapter(
        settings: network().copyWith(host: ''),
        connector: connector,
      );
      expect((await invalid.connect()).message, 'Invalid printer address');
      expect(
        (await adapter.print(job(config: network(host: '192.168.1.51'))))
            .outcome,
        PrintOutcome.failedBeforeSend,
      );
      expect(connector.calls, 0);
    });
    test('unsupported ticket fails before opening socket', () async {
      final result = await adapter.print(job(notes: '🙂'));
      expect(result.outcome, PrintOutcome.failedBeforeSend);
      expect(result.message, contains('unsupported characters'));
      expect(connector.calls, 0);
    });
    test('Dart socket sends real bytes to loopback and closes', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<List<int>>();
      final subscription = server.listen((socket) {
        final bytes = <int>[];
        socket.listen(
          bytes.addAll,
          onDone: () {
            socket.destroy();
            if (!received.isCompleted) received.complete(bytes);
          },
        );
      });
      try {
        final config = network(host: '127.0.0.1', port: server.port);
        final real = NetworkEscPosPrinterAdapter(settings: config);
        expect(
          (await real.print(job(config: config))).outcome,
          PrintOutcome.submitted,
        );
        expect(
          await received.future.timeout(const Duration(seconds: 3)),
          const EscPosTicketRenderer().render(job(config: config).ticket),
        );
      } finally {
        await subscription.cancel();
        await server.close();
      }
    });
  });

  group('persisted pipeline and selection', () {
    late PrintingRuntime runtime;
    late TestConnector connector;
    setUp(() async {
      connector = TestConnector();
      runtime = PrintingRuntime(
        await openPrintingDatabase(
          factory: databaseFactoryFfiNoIsolate,
          path: inMemoryDatabasePath,
        ),
        connector: connector,
      );
      runtime.adapter.delay = Duration.zero;
      await runtime.start();
      runtime.active = true;
    });
    tearDown(() async => runtime.dispose());
    test('persists endpoint and refuses incomplete settings', () async {
      await runtime.saveSettings(network(port: 9200));
      expect(
        (await runtime.settings.read('location-id')).toJson(),
        network(port: 9200).toJson(),
      );
      await expectLater(
        runtime.saveSettings(network().copyWith(host: '')),
        throwsArgumentError,
      );
      expect((await runtime.settings.read('location-id')).port, 9200);
    });
    test(
      'diagnostic passes SQLite sending boundary and network queue',
      () async {
        await runtime.saveSettings(network());
        connector.beforeConnect = () async {
          final saved = (await runtime.jobs.list()).single;
          expect(saved.status, PrintJobStatus.sending);
          expect(saved.purpose, PrintPurpose.test);
          expect(saved.attemptCount, 1);
        };
        final queued = await runtime.service.queueTestPrint(
          'location-id',
          locationName: 'Tualatin',
        );
        await runtime.queue.idle;
        expect(
          (await runtime.jobs.get(queued.id))!.status,
          PrintJobStatus.submitted,
        );
        expect(
          latin1.decode(connector.sockets.single.bytes),
          contains('PRINTER TEST - TEST ONLY'),
        );
        expect(runtime.adapter.printCalls, 0);
      },
    );
    test(
      'probe makes no job; type switches route only selected adapter',
      () async {
        await runtime.saveSettings(network());
        await runtime.selectedAdapter.connect();
        expect(await runtime.jobs.list(), isEmpty);
        await runtime.saveSettings(
          const PrinterSettings(locationId: 'location-id', enabled: true),
        );
        await runtime.adapter.connect();
        await runtime.service.queueTestPrint('location-id');
        await runtime.queue.idle;
        expect(runtime.adapter.printCalls, 1);
        expect(connector.calls, 1);
        expect(connector.sockets.single.bytes, isEmpty);
      },
    );
    test('activation restores saved network without a probe', () async {
      await runtime.settings.save(network());
      await runtime.activate();
      expect(runtime.selectedAdapter.printer.id, network().printerId);
      expect(connector.calls, 0);
    });
    test('endpoint change never redirects previously queued jobs', () async {
      runtime.pause();
      await runtime.saveSettings(network());
      final old = await runtime.service.queueTestPrint('location-id');
      await runtime.queue.idle;
      await runtime.saveSettings(network(host: '192.168.1.51'));
      await runtime.activate();
      await runtime.queue.idle;
      expect((await runtime.jobs.get(old.id))!.status, PrintJobStatus.queued);
      expect(connector.calls, 0);
      await runtime.service.queueTestPrint('location-id');
      await runtime.queue.idle;
      expect(connector.endpoints.single.host, '192.168.1.51');
    });
    test(
      'unknown is not resent; failedBeforeSend supports manual retry',
      () async {
        await runtime.saveSettings(network());
        connector.error = const SocketException('offline');
        final first = await runtime.service.queueTestPrint('location-id');
        await runtime.queue.idle;
        expect(
          (await runtime.jobs.get(first.id))!.status,
          PrintJobStatus.failedBeforeSend,
        );
        connector.error = null;
        connector.makeSocket = () =>
            TestSocket()..flushError = StateError('interrupted');
        await runtime.queue.retry(first.id);
        await runtime.queue.idle;
        expect(
          (await runtime.jobs.get(first.id))!.status,
          PrintJobStatus.unknown,
        );
        runtime.queue.kick();
        await runtime.queue.idle;
        expect(connector.calls, 2);
        await expectLater(runtime.queue.retry(first.id), throwsStateError);
      },
    );
    test(
      'settings switch waits for active send and retains original endpoint',
      () async {
        final gate = Completer<void>();
        connector.makeSocket = () => TestSocket()..flushGate = gate;
        await runtime.saveSettings(network());
        await runtime.service.queueTestPrint('location-id');
        while (connector.sockets.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        final saving = runtime.saveSettings(network(host: '192.168.1.51'));
        await Future<void>.delayed(Duration.zero);
        expect(runtime.selectedAdapter.printer.id, network().printerId);
        gate.complete();
        await saving;
        expect(connector.endpoints.single.host, '192.168.1.50');
        expect(
          runtime.selectedAdapter.printer.id,
          network(host: '192.168.1.51').printerId,
        );
      },
    );
  });
}

bool _contains(List<int> source, List<int> pattern) {
  for (var i = 0; i <= source.length - pattern.length; i++) {
    if (List.generate(
      pattern.length,
      (j) => source[i + j] == pattern[j],
    ).every((v) => v)) {
      return true;
    }
  }
  return false;
}
