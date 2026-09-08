import 'ticket_document.dart';

enum PrintPurpose { initial, reprint, test }

enum PrintJobStatus {
  queued,
  sending,
  submitted,
  confirmed,
  failedBeforeSend,
  unknown,
  cancelled,
}

class PrintJob {
  const PrintJob({
    required this.id,
    required this.orderId,
    required this.locationId,
    required this.purpose,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.printerId,
    required this.ticket,
    this.attemptCount = 0,
    this.lastError,
    this.originalJobId,
  });
  final String id, orderId, locationId, printerId;
  final String? lastError, originalJobId;
  final PrintPurpose purpose;
  final PrintJobStatus status;
  final DateTime createdAt, updatedAt;
  final int attemptCount;
  final TicketDocument ticket;
  PrintJob transition(
    PrintJobStatus status, {
    String? error,
    bool attempt = false,
  }) => PrintJob(
    id: id,
    orderId: orderId,
    locationId: locationId,
    purpose: purpose,
    status: status,
    createdAt: createdAt,
    updatedAt: DateTime.now().toUtc(),
    printerId: printerId,
    ticket: ticket,
    attemptCount: attemptCount + (attempt ? 1 : 0),
    lastError: error,
    originalJobId: originalJobId,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'orderId': orderId,
    'locationId': locationId,
    'purpose': purpose.name,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'printerId': printerId,
    'ticket': ticket.toJson(),
    'attemptCount': attemptCount,
    'lastError': lastError,
    'originalJobId': originalJobId,
  };
  factory PrintJob.fromJson(Map<String, dynamic> j) => PrintJob(
    id: j['id'] as String,
    orderId: j['orderId'] as String,
    locationId: j['locationId'] as String,
    purpose: PrintPurpose.values.byName(j['purpose'] as String),
    status: PrintJobStatus.values.byName(j['status'] as String),
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    printerId: j['printerId'] as String,
    ticket: TicketDocument.fromJson(j['ticket'] as Map<String, dynamic>),
    attemptCount: j['attemptCount'] as int,
    lastError: j['lastError'] as String?,
    originalJobId: j['originalJobId'] as String?,
  );
}
