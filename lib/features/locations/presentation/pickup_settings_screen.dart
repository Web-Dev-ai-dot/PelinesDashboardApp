part of 'store_operations_screen.dart';

/// Dedicated pickup destination; operational controls retain their existing
/// confirmations, controllers and editors in the shared operations library.
class PickupSettingsScreen extends ConsumerWidget {
  const PickupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentLocationProvider);
    final operation = ref.watch(storeOperationsProvider);
    ref.listen<StoreOperationState>(storeOperationsProvider, (previous, next) {
      if (next.message == null || next.message == previous?.message) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, next.message!)),
          backgroundColor: next.phase == StoreOperationPhase.error
              ? Theme.of(context).colorScheme.error
              : null,
        ),
      );
    });
    return Scaffold(
      key: const Key('pickup-settings-screen'),
      appBar: AdminAppBar(
        title: Text(
          tr(context, 'Pickup Settings'),
          style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
        ),
      ),
      body: current.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr(context, error.toString()),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  style: PelinesControlStyles.button(
                    PelinesButtonVariant.secondary,
                  ),
                  onPressed: () {
                    ref.invalidate(locationsProvider);
                    ref.invalidate(currentLocationProvider);
                  },
                  child: Text(tr(context, 'Try again')),
                ),
              ],
            ),
          ),
        ),
        data: (location) => location == null
            ? Center(child: Text(tr(context, 'Choose a location to continue.')))
            : PelinesPageBody(
                width: PelinesPageWidth.dashboard,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(PelinesSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionLocationContext(),
                      Text(
                        tr(
                          context,
                          'Manage online ordering, automatic acceptance and cancellation for this location.',
                        ),
                      ),
                      const SizedBox(height: PelinesSpacing.lg),
                      PelinesSectionHeading(tr(context, 'General')),
                      // This is location-wide ordering, never a pickup-only flag.
                      _OperationsContent(
                        location: location,
                        operation: operation,
                        section: StoreOperationsSection.locations,
                      )._onlineOrders(context, ref),
                      const SizedBox(height: PelinesSpacing.lg),
                      OperationsCard(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              PelinesSectionHeading(
                                tr(context, 'Location active'),
                              ),
                              OperationsStatus(enabled: location.isActive),
                              const SizedBox(height: 12),
                              Text(
                                tr(
                                  context,
                                  'Read-only here. Manage location activation in the web admin.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: PelinesSpacing.lg),
                      OperationsGrid(
                        children: [
                          for (final kind in PickupOrderKind.values)
                            PickupServiceCard(
                              key: ValueKey('${location.id}-${kind.name}'),
                              location: location,
                              kind: kind,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
