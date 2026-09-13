import 'package:flutter/material.dart';

import 'pelines_tokens.dart';

/// Uses the space left by the page, including split view and page padding.
class PelinesActionBar extends StatelessWidget {
  const PelinesActionBar({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final stacked = constraints.maxWidth < PelinesLayout.compactWidth * scale;
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: PelinesSpacing.sm),
              children[i],
            ],
          ],
        );
      }
      return Wrap(
        spacing: PelinesSpacing.sm,
        runSpacing: PelinesSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      );
    },
  );
}

class PelinesLabelValueRow extends StatelessWidget {
  const PelinesLabelValueRow({
    required this.label,
    required this.value,
    this.alignValueEnd = false,
    super.key,
  });

  final Widget label;
  final Widget value;
  final bool alignValueEnd;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (constraints.maxWidth < PelinesLayout.labelPairMinWidth * scale) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label,
            const SizedBox(height: PelinesSpacing.xxs),
            value,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: label),
          const SizedBox(width: PelinesSpacing.sm),
          Expanded(
            flex: 2,
            child: alignValueEnd
                ? Align(alignment: AlignmentDirectional.topEnd, child: value)
                : value,
          ),
        ],
      );
    },
  );
}

/// Constrains scrolling content without imposing a fixed height.
class PelinesPageBody extends StatelessWidget {
  const PelinesPageBody({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: PelinesLayout.contentMaxWidth,
      ),
      child: child,
    ),
  );
}

/// Keeps the action name readable while work is in progress.
class PelinesButtonLabel extends StatelessWidget {
  const PelinesButtonLabel({required this.label, this.busy = false, super.key});
  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (busy) ...[
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: PelinesSpacing.xs),
      ],
      Flexible(child: Text(label, textAlign: TextAlign.center)),
    ],
  );
}

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
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
          ),
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
