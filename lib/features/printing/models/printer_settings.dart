import 'printer.dart';
import 'network_printer_endpoint.dart';

class PrinterSettings {
  const PrinterSettings({
    required this.locationId,
    this.enabled = false,
    this.printerId = 'fake',
    this.transport = PrinterTransport.fake,
    this.autoPrintRegularAsap = false,
    this.autoPrintScheduled = false,
    this.scheduledLeadMinutes = 20,
    this.displayName = 'Epson TM-m30II',
    this.host = '',
    this.port = 9100,
  });
  final String locationId, printerId;
  final bool enabled, autoPrintRegularAsap, autoPrintScheduled;
  final PrinterTransport transport;
  final int scheduledLeadMinutes;
  final String displayName, host;
  final int port;

  NetworkPrinterEndpoint get endpoint =>
      NetworkPrinterEndpoint.parse(host, port);
  bool get isValid {
    if (locationId.trim().isEmpty ||
        printerId.isEmpty ||
        scheduledLeadMinutes < 0 ||
        scheduledLeadMinutes > 1440) {
      return false;
    }
    if (transport == PrinterTransport.fake) return printerId == 'fake';
    if (transport != PrinterTransport.network) return false;
    try {
      return displayName.trim().isNotEmpty &&
          printerId == endpoint.printerId(locationId);
    } on FormatException {
      return false;
    }
  }

  PrinterSettings copyWith({
    bool? enabled,
    String? printerId,
    PrinterTransport? transport,
    bool? autoPrintRegularAsap,
    bool? autoPrintScheduled,
    int? scheduledLeadMinutes,
    String? displayName,
    String? host,
    int? port,
  }) => PrinterSettings(
    locationId: locationId,
    enabled: enabled ?? this.enabled,
    printerId: printerId ?? this.printerId,
    transport: transport ?? this.transport,
    autoPrintRegularAsap: autoPrintRegularAsap ?? this.autoPrintRegularAsap,
    autoPrintScheduled: autoPrintScheduled ?? this.autoPrintScheduled,
    scheduledLeadMinutes: scheduledLeadMinutes ?? this.scheduledLeadMinutes,
    displayName: displayName ?? this.displayName,
    host: host ?? this.host,
    port: port ?? this.port,
  );

  Map<String, dynamic> toJson() => {
    'locationId': locationId,
    'enabled': enabled,
    'printerId': printerId,
    'transport': transport.name,
    'autoPrintRegularAsap': autoPrintRegularAsap,
    'autoPrintScheduled': autoPrintScheduled,
    'scheduledLeadMinutes': scheduledLeadMinutes,
    'displayName': displayName,
    'host': host,
    'port': port,
  };
  factory PrinterSettings.fromJson(Map<String, dynamic> j) => PrinterSettings(
    locationId: j['locationId'] as String,
    enabled: j['enabled'] as bool,
    printerId: j['printerId'] as String,
    transport: PrinterTransport.values.byName(j['transport'] as String),
    autoPrintRegularAsap: j['autoPrintRegularAsap'] as bool,
    autoPrintScheduled: j['autoPrintScheduled'] as bool,
    scheduledLeadMinutes: j['scheduledLeadMinutes'] as int,
    displayName: j['displayName'] as String? ?? 'Epson TM-m30II',
    host: j['host'] as String? ?? '',
    port: j['port'] as int? ?? 9100,
  );
}
