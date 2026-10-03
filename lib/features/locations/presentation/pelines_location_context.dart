import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pelines_tokens.dart';
import '../models/location.dart';
import '../providers/locations_providers.dart';

/// Section headers share the shell's selection; no requests or local cache.
class SectionLocationContext extends ConsumerWidget {
  const SectionLocationContext({super.key, this.bottomSpacing = 12});
  final double bottomSpacing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(currentLocationProvider).value;
    if (location == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: PelinesLocationContext(location: location),
    );
  }
}

/// Read-only location context. Location changes belong to the shell selector.
class PelinesLocationContext extends StatelessWidget {
  const PelinesLocationContext({required this.location, super.key});

  final Location location;

  @override
  Widget build(BuildContext context) {
    final address = location.address?.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.location_on_outlined,
            size: 16,
            color: PelinesColors.brandPrimary,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: location.name,
                  style: const TextStyle(
                    color: PelinesColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (address != null && address.isNotEmpty)
                  TextSpan(text: ' · $address'),
              ],
            ),
            style: const TextStyle(
              fontFamily: PelinesTypography.bodyFamily,
              fontSize: 14,
              height: 1.4,
              color: PelinesColors.textSecondary,
            ),
            softWrap: true,
          ),
        ),
      ],
    );
  }
}
