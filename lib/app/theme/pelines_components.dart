import 'package:flutter/material.dart';

import 'pelines_tokens.dart';
import 'app_theme.dart';

enum PelinesCardVariant { page, compact, raised }

class PelinesKpiCard extends StatelessWidget {
  const PelinesKpiCard({
    required this.label,
    required this.value,
    this.description,
    this.icon,
    super.key,
  });
  final String label, value;
  final String? description;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => PelinesCard(
    variant: PelinesCardVariant.compact,
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: PelinesTypography.smallLabel,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 12),
                Icon(icon, size: 20, color: PelinesColors.brandPrimary),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: PelinesTypography.pageTitle(
              Theme.of(context).textTheme,
              width: constraints.maxWidth,
            )?.copyWith(fontSize: constraints.maxWidth < 320 ? 24 : 30),
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
    ),
  );
}

/// PageShell/FilterBar/KpiCard surfaces; shadows are explicitly opt-in.
class PelinesCard extends StatelessWidget {
  const PelinesCard({
    required this.child,
    this.variant = PelinesCardVariant.page,
    this.padding,
    super.key,
  });
  final Widget child;
  final PelinesCardVariant variant;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding:
        padding ??
        EdgeInsets.all(variant == PelinesCardVariant.compact ? 20 : 24),
    decoration: BoxDecoration(
      color: PelinesColors.card,
      border: Border.all(color: PelinesColors.border),
      borderRadius: BorderRadius.circular(PelinesRadius.pageCard),
      boxShadow: variant == PelinesCardVariant.raised
          ? PelinesShadows.subtle
          : null,
    ),
    child: child,
  );
}

class PelinesButton extends StatelessWidget {
  const PelinesButton({
    required this.label,
    required this.onPressed,
    this.variant = PelinesButtonVariant.primary,
    this.busy = false,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final PelinesButtonVariant variant;
  final bool busy;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: PelinesControlStyles.button(variant),
    onPressed: busy ? null : onPressed,
    child: PelinesButtonLabel(label: label, busy: busy),
  );
}

/// Caller owns validation, controllers, keyboard configuration and localization.
class PelinesInput extends StatelessWidget {
  const PelinesInput({
    this.controller,
    this.onChanged,
    this.label,
    this.hint,
    this.error,
    this.variant = PelinesInputVariant.form,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    super.key,
  });
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String? label, hint, error;
  final PelinesInputVariant variant;
  final bool enabled, obscureText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    enabled: enabled,
    obscureText: obscureText,
    keyboardType: keyboardType,
    decoration: PelinesControlStyles.input(
      variant: variant,
      label: label,
      hint: hint,
      error: error,
    ),
  );
}

class PelinesSelect<T> extends StatelessWidget {
  const PelinesSelect({
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    super.key,
  });
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: PelinesControlStyles.input(
      variant: PelinesInputVariant.select,
      label: label,
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        items: [
          for (final item in items)
            DropdownMenuItem<T>(
              value: item.value,
              enabled: item.enabled,
              onTap: item.onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: item.child,
                ),
              ),
            ),
        ],
        onChanged: onChanged,
        isExpanded: true,
        isDense: false,
        itemHeight: null,
        icon: const Icon(Icons.expand_more, size: 20),
        dropdownColor: PelinesColors.card,
        selectedItemBuilder: (context) => items
            .map(
              (item) => ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: item.child,
                ),
              ),
            )
            .toList(),
      ),
    ),
  );
}

class PelinesPageHeader extends StatelessWidget {
  const PelinesPageHeader({
    required this.title,
    this.subtitle,
    this.location,
    this.actions = const [],
    super.key,
  });
  final String title;
  final String? subtitle;
  final Widget? location;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: PelinesTypography.pageTitle(
              Theme.of(context).textTheme,
              width: width,
            ),
          ),
          if (location != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: location),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: PelinesColors.textSecondary),
              ),
            ),
        ],
      );
      if (actions.isEmpty) return heading;
      final controls = PelinesActionBar(children: actions);
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (width < PelinesLayout.webLarge * scale) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [heading, const SizedBox(height: 16), controls],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: heading),
          const SizedBox(width: 24),
          Expanded(flex: 2, child: controls),
        ],
      );
    },
  );
}

/// Search remains first in reading/focus order, including wrapped layouts.
class PelinesFilterBar extends StatelessWidget {
  const PelinesFilterBar({this.search, this.filters = const [], super.key});
  final Widget? search;
  final List<Widget> filters;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final wide = constraints.maxWidth >= PelinesLayout.webLarge * scale;
      final filterControls = LayoutBuilder(
        builder: (context, inner) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in filters)
              SizedBox(
                width: inner.maxWidth < 640 * scale
                    ? inner.maxWidth
                    : 220 * scale,
                child: filter,
              ),
          ],
        ),
      );
      return PelinesCard(
        padding: EdgeInsets.all(constraints.maxWidth < 640 ? 12 : 16),
        child: wide && search != null && filters.isNotEmpty
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: search!),
                  const SizedBox(width: 12),
                  Expanded(child: filterControls),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?search,
                  if (search != null && filters.isNotEmpty)
                    const SizedBox(height: 12),
                  filterControls,
                ],
              ),
      );
    },
  );
}

class PelinesSegment<T> {
  const PelinesSegment(this.value, this.label);
  final T value;
  final String label;
}

/// Wrapping pills with native button keyboard/focus behavior (no hover dependency).
class PelinesSegmentedControl<T> extends StatelessWidget {
  const PelinesSegmentedControl({
    required this.value,
    required this.segments,
    required this.onChanged,
    super.key,
  });
  final T value;
  final List<PelinesSegment<T>> segments;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final segment in segments)
        Semantics(
          selected: segment.value == value,
          child: PelinesButton(
            label: segment.label,
            variant: segment.value == value
                ? PelinesButtonVariant.primary
                : PelinesButtonVariant.secondary,
            onPressed: onChanged == null
                ? null
                : () => onChanged!(segment.value),
          ),
        ),
    ],
  );
}

class PelinesTableColumn<T> {
  const PelinesTableColumn({
    required this.label,
    required this.cell,
    this.numeric = false,
  });
  final String label;
  final Widget Function(T row) cell;
  final bool numeric;
}

/// Visual foundation only: caller owns ordering, empty states and actions.
/// A compact card builder is mandatory, so information is never silently hidden.
class PelinesAdaptiveTable<T> extends StatelessWidget {
  const PelinesAdaptiveTable({
    required this.rows,
    required this.columns,
    required this.cardBuilder,
    required this.empty,
    super.key,
  });
  final List<T> rows;
  final List<PelinesTableColumn<T>> columns;
  final Widget Function(BuildContext context, T row) cardBuilder;
  final Widget empty;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (rows.isEmpty) return empty;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (constraints.maxWidth < 840 * scale) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: cardBuilder(context, row),
              ),
          ],
        );
      }
      return PelinesCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(PelinesRadius.pageCard),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth - 2),
              child: DataTable(
                headingRowColor: const WidgetStatePropertyAll(
                  PelinesColors.tableHeader,
                ),
                headingTextStyle: PelinesTypography.smallLabel.copyWith(
                  fontSize: 11,
                ),
                dataTextStyle: Theme.of(context).textTheme.bodyMedium,
                headingRowHeight: 48 * scale,
                dataRowMinHeight: 56 * scale,
                dataRowMaxHeight: double.infinity,
                dividerThickness: 1,
                horizontalMargin: 12,
                columnSpacing: 24,
                columns: [
                  for (final column in columns)
                    DataColumn(
                      label: Text(column.label.toUpperCase()),
                      numeric: column.numeric,
                    ),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        for (final column in columns)
                          DataCell(column.cell(row)),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class PelinesViewAction extends StatelessWidget {
  const PelinesViewAction({
    required this.label,
    required this.onPressed,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton.outlined(
    tooltip: label,
    onPressed: onPressed,
    icon: const Icon(Icons.visibility_outlined, size: 18),
    style: IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      side: const BorderSide(color: PelinesColors.border),
    ),
  );
}

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
enum PelinesPageWidth { detail, dashboard }

class PelinesPageBody extends StatelessWidget {
  const PelinesPageBody({
    required this.child,
    this.width = PelinesPageWidth.detail,
    this.responsivePadding = false,
    super.key,
  });

  final Widget child;
  final PelinesPageWidth width;
  // Off by default for existing callers that already own their padding.
  final bool responsivePadding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width == PelinesPageWidth.dashboard
              ? PelinesLayout.dashboardMaxWidth
              : PelinesLayout.contentMaxWidth,
        ),
        child: Padding(
          padding: responsivePadding
              ? EdgeInsets.all(PelinesLayout.pagePadding(constraints.maxWidth))
              : EdgeInsets.zero,
          child: child,
        ),
      ),
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
    child: LayoutBuilder(
      builder: (context, constraints) => Text(
        label,
        style: PelinesTypography.sectionTitle(
          Theme.of(context).textTheme,
          width: constraints.maxWidth,
        ),
      ),
    ),
  );
}

class PelinesStateBadge extends StatelessWidget {
  const PelinesStateBadge({
    required this.label,
    required this.foreground,
    required this.background,
    this.icon,
    this.dot = false,
    this.outlined = false,
    super.key,
  });

  final String label;
  final Color foreground;
  final Color background;
  final IconData? icon;
  final bool dot;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: PelinesSpacing.sm,
      vertical: PelinesSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(PelinesRadius.pill),
      border: outlined ? Border.all(color: foreground) : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (dot) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: foreground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (icon != null) ...<Widget>[
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: PelinesSpacing.xxs),
        ],
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
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
