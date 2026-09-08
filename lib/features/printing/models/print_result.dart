import 'print_job.dart';
import 'printer.dart';

enum PrintOutcome { submitted, confirmed, failedBeforeSend, unknown }

class PrintResult {
  const PrintResult(this.outcome, {this.message});
  final PrintOutcome outcome;
  final String? message;
  PrintJobStatus get jobStatus => PrintJobStatus.values.byName(outcome.name);
}

class PrinterConnectionResult {
  const PrinterConnectionResult(this.status, {this.message});
  final PrinterStatus status;
  final String? message;
}
