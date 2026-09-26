import 'package:flutter/material.dart';

import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../app/l10n/admin_localizations.dart';

class OperationsStatus extends StatelessWidget {
  const OperationsStatus({required this.enabled, super.key});
  final bool enabled;
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: PelinesStateBadge(
      label: tr(context, enabled ? 'Enabled' : 'Disabled'),
      foreground: enabled
          ? PelinesColors.successForeground
          : PelinesColors.textSecondary,
      background: enabled
          ? PelinesColors.successBackground
          : PelinesColors.mutedSurface,
    ),
  );
}

/// Settings surfaces keep Material directly behind interactive rows.
class OperationsCard extends StatelessWidget {
  const OperationsCard({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => PelinesCard(
    padding: EdgeInsets.zero,
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class OperationsFormList extends StatelessWidget {
  const OperationsFormList({
    required this.children,
    this.padding = const EdgeInsets.all(24),
    super.key,
  });
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => ListView(
    padding: padding,
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: OperationsCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class OperationsGrid extends StatelessWidget {
  const OperationsGrid({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >=
              720 * MediaQuery.textScalerOf(context).scale(1)
          ? 2
          : 1;
      return Column(
        key: ValueKey('operations-grid-$columns'),
        children: [
          for (int index = 0; index < children.length; index += columns)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int col = 0; col < columns; col++) ...[
                    if (col > 0) const SizedBox(width: 20),
                    Expanded(
                      child: index + col < children.length
                          ? children[index + col]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
    },
  );
}
