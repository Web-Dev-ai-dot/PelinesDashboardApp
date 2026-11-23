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
    this.scheduledLeadMinutes = 30,
    this.autoPrintAccount,
    this.autoPrintCatering = false,
    this.asapSince,
    this.scheduledSince,
    this.cateringSince,
    this.displayName = 'Epson TM-m30II',
    this.host = '',
    this.port = 9100,
  });
  final String locationId, printerId;
  final bool enabled, autoPrintRegularAsap, autoPrintScheduled;
  final PrinterTransport transport;
  final int scheduledLeadMinutes;
  final bool autoPrintCatering;
  final String? autoPrintAccount;
  final DateTime? asapSince, scheduledSince, cateringSince;
  bool get autoPrintRequested =>
      autoPrintRegularAsap || autoPrintScheduled || autoPrintCatering;
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
    bool? autoPrintCatering,
    String? autoPrintAccount,
    DateTime? asapSince,
    DateTime? scheduledSince,
    DateTime? cateringSince,
    bool resetActivation = false,
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
    autoPrintCatering: autoPrintCatering ?? this.autoPrintCatering,
    autoPrintAccount: autoPrintAccount ?? this.autoPrintAccount,
    asapSince: asapSince ?? (resetActivation ? null : this.asapSince),
    scheduledSince:
        scheduledSince ?? (resetActivation ? null : this.scheduledSince),
    cateringSince:
        cateringSince ?? (resetActivation ? null : this.cateringSince),
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
    'autoPrintCatering': autoPrintCatering,
    'autoPrintAccount': autoPrintAccount,
    'asapSince': asapSince?.toIso8601String(),
    'scheduledSince': scheduledSince?.toIso8601String(),
    'cateringSince': cateringSince?.toIso8601String(),
    'displayName': displayName,
    'host': host,
    'port': port,
  };
  factory PrinterSettings.fromJson(Map<String, dynamic> j) => PrinterSettings(
    locationId: j['locationId'] as String,
    enabled: j['enabled'] as bool,
    printerId: j['printerId'] as String,
    transport: PrinterTransport.values.byName(j['transport'] as String),
    // Pre-auto-print builds saved switches as preferences only.
    autoPrintRegularAsap:
        j.containsKey('autoPrintAccount') && j['autoPrintRegularAsap'] == true,
    autoPrintScheduled:
        j.containsKey('autoPrintAccount') && j['autoPrintScheduled'] == true,
    scheduledLeadMinutes: j['scheduledLeadMinutes'] as int,
    autoPrintCatering: j['autoPrintCatering'] as bool? ?? false,
    autoPrintAccount: j['autoPrintAccount'] as String?,
    asapSince: DateTime.tryParse(j['asapSince'] as String? ?? ''),
    scheduledSince: DateTime.tryParse(j['scheduledSince'] as String? ?? ''),
    cateringSince: DateTime.tryParse(j['cateringSince'] as String? ?? ''),
    displayName: j['displayName'] as String? ?? 'Epson TM-m30II',
    host: j['host'] as String? ?? '',
    port: j['port'] as int? ?? 9100,
  );
}
