import 'printer_capabilities.dart';

enum PrinterTransport { fake, bluetooth, network, usb, epsonSdk }

enum PrinterStatus { disconnected, connecting, connected, error }

class Printer {
  const Printer({
    required this.id,
    required this.displayName,
    required this.transport,
    required this.status,
    required this.capabilities,
  });
  final String id, displayName;
  final PrinterTransport transport;
  final PrinterStatus status;
  final PrinterCapabilities capabilities;
}
