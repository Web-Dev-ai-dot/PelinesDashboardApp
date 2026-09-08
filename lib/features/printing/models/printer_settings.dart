import 'printer.dart';

class PrinterSettings {
  const PrinterSettings({
    required this.locationId,
    this.enabled = false,
    this.printerId = 'fake',
    this.transport = PrinterTransport.fake,
    this.autoPrintRegularAsap = false,
    this.autoPrintScheduled = false,
    this.scheduledLeadMinutes = 20,
  });
  final String locationId, printerId;
  final bool enabled, autoPrintRegularAsap, autoPrintScheduled;
  final PrinterTransport transport;
  final int scheduledLeadMinutes;

  PrinterSettings copyWith({
    bool? enabled,
    String? printerId,
    PrinterTransport? transport,
    bool? autoPrintRegularAsap,
    bool? autoPrintScheduled,
    int? scheduledLeadMinutes,
  }) => PrinterSettings(
    locationId: locationId,
    enabled: enabled ?? this.enabled,
    printerId: printerId ?? this.printerId,
    transport: transport ?? this.transport,
    autoPrintRegularAsap: autoPrintRegularAsap ?? this.autoPrintRegularAsap,
    autoPrintScheduled: autoPrintScheduled ?? this.autoPrintScheduled,
    scheduledLeadMinutes: scheduledLeadMinutes ?? this.scheduledLeadMinutes,
  );

  Map<String, dynamic> toJson() => {
    'locationId': locationId,
    'enabled': enabled,
    'printerId': printerId,
    'transport': transport.name,
    'autoPrintRegularAsap': autoPrintRegularAsap,
    'autoPrintScheduled': autoPrintScheduled,
    'scheduledLeadMinutes': scheduledLeadMinutes,
  };
  factory PrinterSettings.fromJson(Map<String, dynamic> j) => PrinterSettings(
    locationId: j['locationId'] as String,
    enabled: j['enabled'] as bool,
    printerId: j['printerId'] as String,
    transport: PrinterTransport.values.byName(j['transport'] as String),
    autoPrintRegularAsap: j['autoPrintRegularAsap'] as bool,
    autoPrintScheduled: j['autoPrintScheduled'] as bool,
    scheduledLeadMinutes: j['scheduledLeadMinutes'] as int,
  );
}
