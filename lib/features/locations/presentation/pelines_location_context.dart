import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pelines_tokens.dart';
import '../models/location.dart';
import '../providers/locations_providers.dart';

/// Header-only adapter for the API's scalar address. Strip a locality only
/// when both a numbered street and an explicit US city/state suffix match.
/// Unknown formats retain their original content; never split at the first comma.
String? compactLocationStreet(String? address) {
  final value = address?.trim();
  if (value == null || value.isEmpty) return value;
  final postal = RegExp(
    r'^(.+),\s*([A-Za-z][A-Za-z .\x27-]*),\s*'
    r'(AL|AK|AZ|AR|CA|CO|CT|DE|DC|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY)'
    r'(?:\s+\d{5}(?:-\d{4})?)?(?:,\s*(?:USA|United States))?$',
    caseSensitive: false,
  ).firstMatch(value);
  if (postal == null) return value;
  final street = postal.group(1)!.trim();
  final numberedStreet = RegExp(
    r'^\d+[A-Za-z]?(?:-\d+)?\s+[^,\n]+\s+'
    r'(?:St|Street|Ave|Avenue|Rd|Road|Blvd|Boulevard|Dr|Drive|Ln|Lane|Way|Ct|Court|Pl|Place|Pkwy|Parkway|Hwy|Highway|Ter|Terrace|Cir|Circle)\.?'
    r'(?:\s+(?:N|S|E|W|NE|NW|SE|SW))?'
    r'(?:,?\s+(?:Suite|Ste|Unit|Apt|#)\s*[-A-Za-z0-9]+)?$',
    caseSensitive: false,
  );
  return numberedStreet.hasMatch(street) ? street : value;
}

/// Section headers share the shell's selection; no requests or local cache.
class SectionLocationContext extends ConsumerWidget {
  const SectionLocationContext({super.key, this.bottomSpacing = 12});
  final double bottomSpacing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentLocationProvider);
    final location = current.isLoading || current.hasError
        ? null
        : current.value;
    if (location == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: PelinesLocationContext(location: location),
    );
  }
}

/// Read-only location context. Location changes belong to the shell selector.
class PelinesLocationContext extends StatelessWidget {
  const PelinesLocationContext({
    required this.location,
    this.maxLines,
    super.key,
  });

  final Location location;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final address = compactLocationStreet(location.address);
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
            maxLines: maxLines,
            overflow: maxLines == null
                ? TextOverflow.clip
                : TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
