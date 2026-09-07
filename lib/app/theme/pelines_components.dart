import 'package:flutter/material.dart';

import 'pelines_tokens.dart';

class PelinesSectionHeading extends StatelessWidget {
  const PelinesSectionHeading(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      left: PelinesSpacing.xxs,
      top: PelinesSpacing.xs,
      bottom: PelinesSpacing.xs,
    ),
    child: Text(label, style: Theme.of(context).textTheme.headlineSmall),
  );
}

class PelinesStateBadge extends StatelessWidget {
  const PelinesStateBadge({
    required this.label,
    required this.foreground,
    required this.background,
    this.icon,
    super.key,
  });

  final String label;
  final Color foreground;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: PelinesSpacing.sm,
      vertical: PelinesSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(PelinesRadius.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: PelinesSpacing.xxs),
        ],
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class PelinesReadOnlyField extends StatelessWidget {
  const PelinesReadOnlyField({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(PelinesSpacing.md),
    decoration: BoxDecoration(
      color: PelinesColors.mutedSurface,
      border: Border.all(color: PelinesColors.border),
      borderRadius: BorderRadius.circular(PelinesRadius.control),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(
          Icons.lock_outline,
          size: 20,
          color: PelinesColors.textSecondary,
        ),
        const SizedBox(width: PelinesSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: PelinesColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: PelinesSpacing.xxs),
              Text(value),
              const SizedBox(height: PelinesSpacing.xxs),
              Text(
                'Read-only',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: PelinesColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
