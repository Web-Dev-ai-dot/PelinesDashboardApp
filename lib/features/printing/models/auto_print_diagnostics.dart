import '../application/auto_print_policy.dart';
import 'print_job.dart';

enum AutoPrintPause {
  inactive,
  configuring,
  printerUnavailable,
  ordersUnavailable,
  queueUnavailable,
}

enum AutoPrintMode { disabled, activationPending, active, paused }

enum AutoPrintEvaluation {
  waiting,
  noCandidates,
  evaluated,
  ordersUnavailable,
  incomplete,
}

typedef EffectiveAutoPrint = ({
  AutoPrintMode mode,
  DateTime? activatedAt,
  AutoPrintPause? pause,
});

typedef AutoPrintObservation = ({
  String orderNumber,
  AutoPrintDecision decision,
  String? jobId,
  PrintJobStatus? jobStatus,
  bool? automatic,
});

class AutoPrintDiagnostics {
  const AutoPrintDiagnostics({
    this.lastRefresh,
    this.lastRefreshError,
    this.evaluation = AutoPrintEvaluation.waiting,
    this.observations = const [],
  });

  final DateTime? lastRefresh;
  final DateTime? lastRefreshError;
  final AutoPrintEvaluation evaluation;
  final List<AutoPrintObservation> observations;

  AutoPrintDiagnostics copyWith({
    DateTime? lastRefresh,
    DateTime? lastRefreshError,
    AutoPrintEvaluation? evaluation,
    List<AutoPrintObservation>? observations,
  }) => AutoPrintDiagnostics(
    lastRefresh: lastRefresh ?? this.lastRefresh,
    lastRefreshError: lastRefreshError ?? this.lastRefreshError,
    evaluation: evaluation ?? this.evaluation,
    observations: observations ?? this.observations,
  );
}
