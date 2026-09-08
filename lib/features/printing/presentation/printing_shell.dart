import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/printing_providers.dart';

/// Authenticated application lifetime, independent of Printer Settings.
class PrintingShell extends ConsumerStatefulWidget {
  const PrintingShell({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<PrintingShell> createState() => _PrintingShellState();
}

class _PrintingShellState extends ConsumerState<PrintingShell> {
  PrintingRuntime? _runtime;
  String? _activationError;
  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final runtime = await ref.read(printingRuntimeProvider.future);
      if (!mounted) return;
      _runtime = runtime;
      await runtime.activate();
    } on Object {
      if (mounted) {
        setState(
          () => _activationError =
              'Printing could not start. Open Printer Settings to review.',
        );
      }
    }
  }

  @override
  void dispose() {
    _runtime?.pause();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(printingRuntimeProvider);
    return Column(
      children: [
        if (_activationError != null)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_activationError!),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
