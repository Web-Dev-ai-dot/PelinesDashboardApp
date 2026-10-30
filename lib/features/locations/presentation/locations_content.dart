part of 'store_operations_screen.dart';

/// Location-only composition; editors and mutations remain in Operations.
class _LocationsContent extends StatelessWidget {
  const _LocationsContent({required this.location, required this.onlineOrders});
  final Location location;
  final Widget onlineOrders;

  @override
  Widget build(BuildContext context) => PelinesPageBody(
    width: PelinesPageWidth.dashboard,
    child: ListView(
      key: const Key('locations-content'),
      padding: const EdgeInsets.all(PelinesSpacing.lg),
      children: [
        Text(
          tr(
            context,
            'Manage restaurant location details, addresses, and contact information.',
          ),
        ),
        const SizedBox(height: 24),
        OperationsGrid(
          children: [
            OperationsCard(
              key: const Key('location-information'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CircleAvatar(
                          radius: 24,
                          backgroundColor: PelinesColors.brandPrimarySoft,
                          child: Icon(
                            Icons.location_on_outlined,
                            color: PelinesColors.brandPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              PelinesSectionHeading(location.name),
                              Text(
                                location.slug,
                                style: PelinesTypography.smallLabel,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: PelinesStateBadge(
                        label: tr(
                          context,
                          location.isActive ? 'Active' : 'Inactive',
                        ),
                        foreground: location.isActive
                            ? PelinesColors.successForeground
                            : PelinesColors.textSecondary,
                        background: location.isActive
                            ? PelinesColors.successBackground
                            : PelinesColors.mutedSurface,
                      ),
                    ),
                    for (final item in [
                      ('Location Name', location.name),
                      ('Address', location.address ?? '—'),
                      ('Contact Phone', location.phone ?? '—'),
                    ])
                      _LocationInfo(
                        label: tr(context, item.$1),
                        value: item.$2,
                      ),
                    const SizedBox(height: 12),
                    Text(
                      tr(context, 'Location details are read-only.'),
                      style: const TextStyle(
                        color: PelinesColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            onlineOrders,
          ],
        ),
        const SizedBox(height: 4),
        PelinesSectionHeading(tr(context, 'Business Hours & Closures')),
        const SizedBox(height: 8),
        Text(
          tr(
            context,
            'Manage standard business hours, temporary closures, and holiday schedules. These hours control regular ordering in Pacific Time.',
          ),
        ),
        const SizedBox(height: 16),
        OperationsGrid(
          children: [
            _BusinessHoursCard(location: location, locationsStyle: true),
            _TemporaryClosuresCard(location: location, locationsStyle: true),
          ],
        ),
        const SizedBox(height: 24),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: HolidaysSection(
              key: ValueKey('holidays-${location.id}'),
              location: location,
              locationsLayout: true,
            ),
          ),
        ),
      ],
    ),
  );
}

class _LocationInfo extends StatelessWidget {
  const _LocationInfo({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: PelinesTypography.smallLabel),
        const SizedBox(height: 6),
        Semantics(
          label: label,
          child: TextFormField(
            key: ValueKey('location-info-$label-$value'),
            initialValue: value,
            readOnly: true,
            maxLines: null,
            decoration: PelinesControlStyles.input().copyWith(
              fillColor: PelinesColors.mutedSurface,
              filled: true,
            ),
          ),
        ),
      ],
    ),
  );
}
