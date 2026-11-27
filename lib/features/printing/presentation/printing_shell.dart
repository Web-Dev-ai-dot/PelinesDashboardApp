import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../auth/models/admin_session.dart';
import '../../auth/providers/auth_providers.dart';
import '../../locations/models/location.dart';
import '../../locations/providers/locations_providers.dart';
import '../../orders/providers/orders_providers.dart';
import '../providers/printing_providers.dart';

/// Uses the authenticated shell's existing 15-second order refresh.
class PrintingShell extends ConsumerStatefulWidget {
  const PrintingShell({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<PrintingShell> createState() => _PrintingShellState();
}

class _PrintingShellState extends ConsumerState<PrintingShell>
    with WidgetsBindingObserver {
  PrintingRuntime? _runtime;
  StreamSubscription<void>? _queueEvents;
  bool _foreground = false;
  bool _failed = false;
  bool _coverageLimited = false;
  bool _running = false, _requested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    ref.listenManual<AsyncValue<AdminSession?>>(
      authControllerProvider,
      (_, _) => _update(),
    );
    ref.listenManual<AsyncValue<Location?>>(
      currentLocationProvider,
      (_, _) => _update(),
    );
    ref.listenManual<AsyncValue<TodayOrdersState>>(todayOrdersProvider, (
      _,
      next,
    ) {
      if (!next.isLoading && next.value?.isRefreshing != true) {
        _requestEvaluation();
      }
    });
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final runtime = await ref.read(printingRuntimeProvider.future);
      if (!mounted) return;
      _runtime = runtime;
      _queueEvents = runtime.queue.changes.listen((_) {
        if (mounted) setState(() {});
      });
      _update();
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _update() {
    final runtime = _runtime;
    if (runtime == null || !mounted) return;
    final auth = ref.read(authControllerProvider).asData?.value;
    final location = ref.read(currentLocationProvider).asData?.value;
    unawaited(_bind(runtime, auth, location));
  }

  Future<void> _bind(
    PrintingRuntime runtime,
    AdminSession? auth,
    Location? location,
  ) async {
    try {
      await runtime.updateScope(
        auth?.profile.id,
        location?.id,
        auth == null ? null : ref.read(ordersRepositoryProvider),
        foreground: _foreground,
      );
      _requestEvaluation();
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _requestEvaluation() {
    if (!mounted || !_foreground || _runtime?.active != true) return;
    _requested = true;
    if (!_running) unawaited(_evaluate());
  }

  Future<void> _evaluate() async {
    _running = true;
    try {
      while (mounted && _requested && _foreground && _runtime?.active == true) {
        _requested = false;
        final state = ref.read(todayOrdersProvider);
        final snapshot = state.asData?.value;
        final location = ref.read(currentLocationProvider).asData?.value?.id;
        if (location == null) continue;
        if (state.hasError || snapshot?.refreshError != null) {
          _runtime!.recordOrdersFailure(location);
          try {
            final enabled = await _runtime!.hasAutomaticPrinting(location);
            if (mounted) {
              setState(() {
                _failed = enabled;
                _coverageLimited = enabled;
              });
            }
          } on Object {
            if (mounted) setState(() => _failed = true);
          }
          continue;
        }
        if (snapshot == null ||
            snapshot.isRefreshing ||
            snapshot.snapshotLocationId != location ||
            snapshot.fullLocationSnapshot == null) {
          continue;
        }
        try {
          final limited = await _runtime!.evaluate(
            snapshot.fullLocationSnapshot!,
            location,
            refreshedAt: snapshot.refreshedAt,
          );
          if (mounted) {
            setState(() {
              _failed = false;
              _coverageLimited = limited;
            });
          }
        } on Object {
          if (mounted) setState(() => _failed = true);
        }
      }
    } finally {
      _running = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _update();
  }

  @override
  void dispose() {
    _runtime?.pause();
    unawaited(_queueEvents?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(printingRuntimeProvider);
    final warning =
        _failed ||
            _runtime?.validationFailed == true ||
            _runtime?.queue.lastError != null
        ? 'Printing needs attention. Check orders and Printer Settings.'
        : _runtime?.legacySimulationDisabled == true
        ? 'Printer simulation was disabled. Select a network printer in Printer Settings.'
        : null;
    final coverageWarning = _coverageLimited
        ? 'Auto-print checks the orders returned by the server. Complete coverage cannot be verified.'
        : null;
    return Column(
      children: [
        if (warning != null || coverageWarning != null)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  [
                    if (warning != null) tr(context, warning),
                    if (coverageWarning != null) tr(context, coverageWarning),
                  ].join('\n'),
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
