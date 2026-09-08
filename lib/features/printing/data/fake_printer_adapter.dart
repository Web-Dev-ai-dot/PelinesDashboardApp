import '../models/printer.dart';
import '../models/printer_capabilities.dart';
import '../models/print_job.dart';
import '../models/print_result.dart';
import 'printer_adapter.dart';

class FakePrinterAdapter implements PrinterAdapter {
  FakePrinterAdapter({
    this.connectionFails = false,
    this.outcome = PrintOutcome.submitted,
    this.delay = const Duration(milliseconds: 700),
  });
  bool connectionFails;
  PrintOutcome outcome;
  Duration delay;
  PrinterStatus _status = PrinterStatus.disconnected;
  int printCalls = 0;
  int activeCalls = 0;
  int maxActiveCalls = 0;
  @override
  Printer get printer => Printer(
    id: 'fake',
    displayName: 'Fake Printer',
    transport: PrinterTransport.fake,
    status: _status,
    capabilities: const PrinterCapabilities(statusReporting: true),
  );
  @override
  Future<PrinterConnectionResult> connect() async {
    _status = PrinterStatus.connecting;
    await Future<void>.delayed(delay);
    _status = connectionFails ? PrinterStatus.error : PrinterStatus.connected;
    return PrinterConnectionResult(
      _status,
      message: connectionFails ? 'Simulated connection failure.' : null,
    );
  }

  @override
  Future<PrinterConnectionResult> disconnect() async {
    _status = PrinterStatus.disconnected;
    return const PrinterConnectionResult(PrinterStatus.disconnected);
  }

  @override
  Future<PrinterStatus> getStatus() async => _status;
  @override
  Future<PrintResult> print(PrintJob job) async {
    if (_status != PrinterStatus.connected) {
      return const PrintResult(
        PrintOutcome.failedBeforeSend,
        message: 'Fake Printer is disconnected.',
      );
    }
    final selected = outcome;
    printCalls++;
    activeCalls++;
    if (activeCalls > maxActiveCalls) maxActiveCalls = activeCalls;
    try {
      await Future<void>.delayed(delay);
      return PrintResult(
        selected,
        message: switch (selected) {
          PrintOutcome.failedBeforeSend =>
            'Simulated failure before send. Manual retry is safe.',
          PrintOutcome.unknown =>
            'Simulated uncertain result. Review before an intentional reprint.',
          _ => null,
        },
      );
    } finally {
      activeCalls--;
    }
  }
}
