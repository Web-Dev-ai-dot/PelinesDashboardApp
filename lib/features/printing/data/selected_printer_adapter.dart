import '../models/print_job.dart';
import '../models/print_result.dart';
import '../models/printer.dart';
import 'printer_adapter.dart';

/// Stable queue dependency. Runtime switches only after draining its worker.
class SelectedPrinterAdapter implements PrinterAdapter {
  SelectedPrinterAdapter(this.current);
  PrinterAdapter current;
  @override
  Printer get printer => current.printer;
  @override
  Future<PrinterConnectionResult> connect() => current.connect();
  @override
  Future<PrinterConnectionResult> disconnect() => current.disconnect();
  @override
  Future<PrinterStatus> getStatus() => current.getStatus();
  @override
  Future<PrintResult> print(PrintJob job) => current.print(job);
}
