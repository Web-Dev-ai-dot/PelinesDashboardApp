import '../models/printer.dart';
import '../models/print_job.dart';
import '../models/print_result.dart';

abstract interface class PrinterAdapter {
  Printer get printer;
  Future<PrinterConnectionResult> connect();
  Future<PrinterConnectionResult> disconnect();
  Future<PrinterStatus> getStatus();
  Future<PrintResult> print(PrintJob job);
}
