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
            'Location details, business hours and temporary closures.',
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
                              PelinesSectionHeading(tr(context, 'Location')),
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
                    if (location.phone?.trim().isNotEmpty == true)
                      _LocationInfo(
                        label: tr(context, 'Phone'),
                        value: location.phone!,
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
        Text(value),
      ],
    ),
  );
}

class _LocationDayRow extends StatelessWidget {
  const _LocationDayRow({
    required this.day,
    required this.hours,
    required this.summary,
  });
  final int day;
  final BusinessDayHours hours;
  final String summary;
  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('location-hours-${businessDayKeys[day]}'),
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: PelinesColors.border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              tr(context, businessDayLabels[day]),
              style: PelinesTypography.smallLabel,
            ),
            PelinesStateBadge(
              label: tr(context, hours.closed ? 'Closed' : 'Open'),
              foreground: hours.closed
                  ? PelinesColors.textSecondary
                  : PelinesColors.successForeground,
              background: hours.closed
                  ? PelinesColors.mutedSurface
                  : PelinesColors.successBackground,
            ),
          ],
        ),
        if (!hours.closed) ...[const SizedBox(height: 8), Text(summary)],
      ],
    ),
  );
}
