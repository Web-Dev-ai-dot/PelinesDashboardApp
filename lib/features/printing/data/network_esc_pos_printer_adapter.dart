import 'dart:async';

import '../application/esc_pos_ticket_renderer.dart';
import '../models/print_job.dart';
import '../models/print_result.dart';
import '../models/printer.dart';
import '../models/printer_capabilities.dart';
import '../models/printer_settings.dart';
import 'printer_adapter.dart';
import 'printer_socket.dart';

class NetworkEscPosPrinterAdapter implements PrinterAdapter {
  NetworkEscPosPrinterAdapter({
    required this.settings,
    this.connector = const DartPrinterSocketConnector(),
    this.renderer = const EscPosTicketRenderer(),
    this.connectTimeout = const Duration(seconds: 4),
    this.sendTimeout = const Duration(seconds: 8),
    this.closeTimeout = const Duration(seconds: 2),
  });
  final PrinterSettings settings;
  final PrinterSocketConnector connector;
  final EscPosTicketRenderer renderer;
  final Duration connectTimeout, sendTimeout, closeTimeout;
  PrinterStatus _status = PrinterStatus.disconnected;
  @override
  Printer get printer => Printer(
    id: settings.printerId,
    displayName: settings.displayName,
    transport: PrinterTransport.network,
    status: _status,
    capabilities: const PrinterCapabilities(
      network: true,
      rawEscPos: true,
      cutter: true,
    ),
  );

  Future<PrinterSocket> _open() async {
    if (!settings.isValid || settings.transport != PrinterTransport.network) {
      throw const FormatException('Invalid printer address');
    }
    // Also bound custom connectors. Dispose any connection arriving after timeout.
    var expired = false;
    return connector
        .connect(settings.endpoint, connectTimeout)
        .then((socket) {
          if (expired) socket.destroy();
          return socket;
        })
        .timeout(
          connectTimeout,
          onTimeout: () {
            expired = true;
            throw TimeoutException('Connection timed out');
          },
        );
  }

  /// Reachability only. No writes, no PrintJob and no held connection.
  @override
  Future<PrinterConnectionResult> connect() async {
    PrinterSocket? socket;
    _status = PrinterStatus.connecting;
    try {
      socket = await _open();
      await socket.close().timeout(closeTimeout);
      _status = PrinterStatus.connected;
      return PrinterConnectionResult(_status, message: 'Printer reachable');
    } on Object catch (error) {
      _status = PrinterStatus.error;
      return PrinterConnectionResult(
        _status,
        message: _connectionMessage(error),
      );
    } finally {
      socket?.destroy();
    }
  }

  @override
  Future<PrinterConnectionResult> disconnect() async {
    _status = PrinterStatus.disconnected;
    return const PrinterConnectionResult(PrinterStatus.disconnected);
  }

  /// Last connection observation, not live printer or paper status.
  @override
  Future<PrinterStatus> getStatus() async => _status;

  @override
  Future<PrintResult> print(PrintJob job) async {
    PrinterSocket? socket;
    var startedWriting = false;
    try {
      if (job.printerId != settings.printerId ||
          job.locationId != settings.locationId) {
        throw const FormatException('Invalid printer address');
      }
      final bytes = renderer.render(job.ticket);
      socket = await _open();
      // Set before add: even a synchronous write exception can be ambiguous.
      startedWriting = true;
      socket.add(bytes);
      await socket.flush().timeout(sendTimeout);
      await socket.close().timeout(closeTimeout);
      _status = PrinterStatus.connected;
      return const PrintResult(
        PrintOutcome.submitted,
        message: 'Sent to printer connection. Check the physical ticket.',
      );
    } on Object catch (error) {
      _status = PrinterStatus.error;
      if (startedWriting) {
        return const PrintResult(
          PrintOutcome.unknown,
          message: 'Delivery is unknown. Check the printer before any intentional reprint.',
        );
      }
      return PrintResult(
        PrintOutcome.failedBeforeSend,
        message: error is TicketEncodingException
            ? 'Ticket contains unsupported characters. Nothing was sent; review the ticket text.'
            : _connectionMessage(error),
      );
    } finally {
      socket?.destroy();
    }
  }
}

String _connectionMessage(Object error) => switch (error) {
  FormatException() => 'Invalid printer address',
  TimeoutException() => 'Connection timed out',
  _ => 'Cannot connect to printer',
};
