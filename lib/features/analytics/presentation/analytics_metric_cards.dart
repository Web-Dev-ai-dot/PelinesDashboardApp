import 'package:flutter/material.dart';

import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';

class AnalyticsMetricCard extends StatelessWidget {
  const AnalyticsMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.description,
    this.completed = false,
  });
  final String label, value;
  final IconData icon;
  final String? description;
  final bool completed;
  @override
  Widget build(BuildContext context) => PelinesCard(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: PelinesTypography.smallLabel)),
            const SizedBox(width: 8),
            Icon(
              icon,
              size: 20,
              color: completed
                  ? PelinesColors.successForeground
                  : PelinesColors.brandPrimary,
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final line in value.split('\n'))
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              line,
              maxLines: 1,
              softWrap: false,
              style: PelinesTypography.pageTitle(Theme.of(context).textTheme)
                  ?.copyWith(fontSize: 30),
            ),
          ),
        if (description != null) ...[
          const SizedBox(height: 12),
          Text(
            description!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: PelinesColors.textSecondary),
          ),
        ],
      ],
    ),
  );
}

class AnalyticsMetricGrid extends StatelessWidget {
  const AnalyticsMetricGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >=
              1080 * MediaQuery.textScalerOf(context).scale(1)
          ? 4
          : 2;
      return Column(
        children: [
          for (var row = 0; row < children.length; row += columns)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var col = 0; col < columns; col++) ...[
                      if (col > 0) const SizedBox(width: 12),
                      Expanded(
                        child: row + col < children.length
                            ? children[row + col]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
