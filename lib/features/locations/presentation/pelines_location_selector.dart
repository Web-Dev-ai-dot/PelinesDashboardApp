import 'package:flutter/material.dart';

import '../../../app/theme/pelines_tokens.dart';

class PelinesLocationSelector extends StatelessWidget {
  const PelinesLocationSelector({
    required this.locationName,
    required this.onPressed,
    super.key,
  });
  final String locationName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: const Key('location-selector'),
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: PelinesColors.brandPrimary,
      backgroundColor: PelinesColors.brandPrimarySoft,
      padding: const EdgeInsets.symmetric(
        horizontal: PelinesSpacing.sm,
        vertical: PelinesSpacing.xs,
      ),
      minimumSize: const Size(48, 48),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.storefront_outlined),
        const SizedBox(width: PelinesSpacing.xs),
        Flexible(child: Text(locationName)),
        const SizedBox(width: PelinesSpacing.xs),
        const Icon(Icons.expand_more),
      ],
    ),
  );
}
