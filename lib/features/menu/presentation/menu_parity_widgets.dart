import 'package:flutter/material.dart';

import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';

/// Shared, wrapping card/header actions with accessible touch targets.
class MenuActions extends StatelessWidget {
  const MenuActions({required this.children, super.key});
  final List<Widget> children;

  static ButtonStyle style({bool destructive = false}) => TextButton.styleFrom(
    minimumSize: const Size(48, 48),
    shape: const StadiumBorder(),
    foregroundColor: destructive
        ? PelinesColors.destructive
        : PelinesColors.textPrimary,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );

  @override
  Widget build(BuildContext context) => TextButtonTheme(
    data: TextButtonThemeData(style: style()),
    child: Wrap(spacing: 8, runSpacing: 8, children: children),
  );
}

/// Content-sized rows avoid fixed card heights when text wraps or scales.
class MenuCardGrid extends StatelessWidget {
  const MenuCardGrid({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = constraints.maxWidth >= 1080 * scale
          ? 3
          : constraints.maxWidth >= 640 * scale
          ? 2
          : 1;
      return Column(
        key: ValueKey('menu-grid-$columns'),
        children: [
          for (var row = 0; row < children.length; row += columns)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var col = 0; col < columns; col++) ...[
                    if (col > 0) const SizedBox(width: 16),
                    Expanded(
                      child: row + col < children.length
                          ? children[row + col]
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

class MenuFormList extends StatelessWidget {
  const MenuFormList({
    required this.children,
    this.padding = const EdgeInsets.all(16),
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
          constraints: const BoxConstraints(maxWidth: 800),
          child: PelinesCard(
            padding: const EdgeInsets.all(16),
            child: Material(
              type: MaterialType.transparency,
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

class MenuFieldPair extends StatelessWidget {
  const MenuFieldPair({required this.first, required this.second, super.key});
  final Widget first, second;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        constraints.maxWidth >= 540 * MediaQuery.textScalerOf(context).scale(1)
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 16),
              Expanded(child: second),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, second],
          ),
  );
}

class MenuPhoto extends StatelessWidget {
  const MenuPhoto({required this.url, this.height = 180, super.key});
  final String? url;
  final double height;
  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      key: const Key('menu-image-fallback'),
      height: height,
      width: double.infinity,
      color: PelinesColors.mutedSurface,
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: PelinesColors.textSecondary,
        size: 40,
      ),
    );
    final uri = url == null ? null : Uri.tryParse(url!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: uri == null || !['http', 'https'].contains(uri.scheme)
          ? fallback
          : Image.network(
              url!,
              key: const Key('menu-product-image'),
              width: double.infinity,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}
