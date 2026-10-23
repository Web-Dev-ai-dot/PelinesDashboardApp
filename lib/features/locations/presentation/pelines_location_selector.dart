import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pelines_tokens.dart';
import '../../../app/l10n/admin_localizations.dart';
import '../models/location.dart';
import '../providers/locations_providers.dart';

/// Only show a locality when the existing address has an explicit city/state
/// suffix. Never substitute a street address or guess a location's state.
String? locationCityState(String? address) {
  if (address == null) return null;
  final match = RegExp(
    r'(?:^|[,\n])\s*([^,\n\d]+),\s*([A-Z]{2})(?:\s+\d{5}(?:-\d{4})?)?(?:\s*,?\s*(?:USA|United States))?\s*$',
    caseSensitive: false,
  ).firstMatch(address);
  return match == null
      ? null
      : '${match.group(1)!.trim()}, ${match.group(2)!.toUpperCase()}';
}

class PelinesLocationSelector extends StatelessWidget {
  const PelinesLocationSelector({
    required this.locationName,
    required this.onPressed,
    this.compact = false,
    this.shell = false,
    this.mobileCard = false,
    this.subtitle,
    this.expanded = false,
    super.key,
  });
  final String locationName;
  final VoidCallback? onPressed;
  final bool compact;
  final bool shell;
  final bool mobileCard;
  final String? subtitle;
  final bool expanded;

  @override
  Widget build(BuildContext context) => compact
      ? IconButton.outlined(
          key: const Key('location-selector'),
          tooltip: locationName,
          onPressed: onPressed,
          icon: const Icon(Icons.location_on_outlined, size: 18),
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: PelinesColors.brandPrimary,
            side: const BorderSide(color: PelinesColors.border),
          ),
        )
      : OutlinedButton(
          key: const Key('location-selector'),
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: shell
                ? PelinesColors.textPrimary
                : PelinesColors.brandPrimary,
            backgroundColor: shell
                ? PelinesColors.card
                : PelinesColors.brandPrimarySoft,
            shape: shell
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(mobileCard ? 16 : 18),
                  )
                : null,
            side: mobileCard
                ? const BorderSide(color: PelinesColors.border)
                : null,
            padding: EdgeInsets.symmetric(
              horizontal: mobileCard ? 12 : PelinesSpacing.sm,
              vertical: mobileCard ? 10 : PelinesSpacing.xs,
            ),
            minimumSize: const Size(48, 48),
          ),
          child: Row(
            mainAxisSize: mobileCard ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(
                shell ? Icons.location_on_outlined : Icons.storefront_outlined,
                size: mobileCard
                    ? 16
                    : shell
                    ? 18
                    : 24,
                color: PelinesColors.brandPrimary,
              ),
              const SizedBox(width: PelinesSpacing.xs),
              Flexible(
                fit: mobileCard ? FlexFit.tight : FlexFit.loose,
                child: mobileCard
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            locationName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.25,
                                fontWeight: FontWeight.w400,
                                color: PelinesColors.textSecondary,
                              ),
                            ),
                        ],
                      )
                    : Text(locationName),
              ),
              const SizedBox(width: PelinesSpacing.xs),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: mobileCard ? 16 : 24,
              ),
            ],
          ),
        );
}

/// Shared by the original Orders entry point and the shell. Selection and
/// persistence remain exclusively in CurrentLocationController.
Future<void> showPelinesLocationPicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final locations = ref.read(locationsProvider).value;
  if (locations == null) return;
  final selectedId = ref.read(currentLocationProvider).value?.id;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .8,
        ),
        child: PelinesLocationList(
          locations: locations,
          selectedId: selectedId,
          onSelected: (next) async {
            try {
              await ref.read(currentLocationProvider.notifier).select(next);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            } catch (_) {
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      tr(sheetContext, 'Location could not be selected.'),
                    ),
                  ),
                );
              }
            }
          },
        ),
      ),
    ),
  );
}

class PelinesLocationList extends StatelessWidget {
  const PelinesLocationList({
    required this.locations,
    required this.onSelected,
    this.selectedId,
    this.enabled = true,
    this.embedded = false,
    super.key,
  });
  final List<Location> locations;
  final String? selectedId;
  final bool enabled;
  final bool embedded;
  final Future<void> Function(Location) onSelected;
  @override
  Widget build(BuildContext context) => ListView.builder(
    shrinkWrap: true,
    primary: false,
    physics: embedded ? const NeverScrollableScrollPhysics() : null,
    padding: embedded
        ? EdgeInsets.zero
        : const EdgeInsets.symmetric(vertical: PelinesSpacing.xs),
    itemCount: locations.length,
    itemBuilder: (context, index) {
      final location = locations[index];
      return ListTile(
        dense: embedded,
        minTileHeight: embedded ? 48 : null,
        minVerticalPadding: embedded ? 0 : null,
        enabled: enabled && location.isActive,
        selected: selectedId == location.id,
        selectedTileColor: PelinesColors.brandPrimarySoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PelinesRadius.control),
        ),
        leading: Icon(
          location.isActive ? Icons.storefront_outlined : Icons.store_outlined,
        ),
        title: Text(
          location.name,
          maxLines: embedded ? 1 : null,
          overflow: embedded ? TextOverflow.ellipsis : null,
        ),
        subtitle: embedded
            ? null
            : Text(
                [
                  if (location.address != null) location.address!,
                  if (!location.isActive) tr(context, 'Inactive'),
                ].join('\n'),
              ),
        trailing: selectedId == location.id
            ? const Icon(Icons.check_circle, color: PelinesColors.brandPrimary)
            : null,
        onTap: enabled && location.isActive ? () => onSelected(location) : null,
      );
    },
  );
}
