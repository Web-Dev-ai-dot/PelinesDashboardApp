import 'package:flutter/material.dart';

import 'pelines_components.dart';

/// Settings presentation only; callers retain their own state and callbacks.
class PelinesSettingsCard extends StatelessWidget {
  const PelinesSettingsCard({required this.children, this.title, super.key});
  final String? title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => PelinesCard(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 400 ? 16 : 24),
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            PelinesSectionHeading(title!),
            const SizedBox(height: 16),
          ],
          ...children,
        ],
      ),
    ),
  );
}

class PelinesSettingsForm extends StatelessWidget {
  const PelinesSettingsForm({
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
          child: PelinesSettingsCard(children: children),
        ),
      ),
    ],
  );
}

class PelinesSettingsFields extends StatelessWidget {
  const PelinesSettingsFields({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >=
              620 * MediaQuery.textScalerOf(context).scale(1)
          ? 2
          : 1;
      return Column(
        key: ValueKey('settings-fields-$columns'),
        children: [
          for (var i = 0; i < children.length; i += columns)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var col = 0; col < columns; col++) ...[
                    if (col > 0) const SizedBox(width: 20),
                    Expanded(
                      child: i + col < children.length
                          ? children[i + col]
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
