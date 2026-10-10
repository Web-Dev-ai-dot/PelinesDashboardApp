import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_settings_content.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../orders/presentation/order_ui_helpers.dart';
import '../models/catering_delivery.dart';
import '../models/location.dart';
import '../models/regular_delivery.dart';
import '../providers/catering_delivery_controller.dart';
import '../providers/locations_providers.dart';
import '../providers/regular_delivery_controller.dart';
import 'catering_delivery_screen.dart';
import 'operations_parity_widgets.dart';
import 'regular_delivery_screen.dart';

class DeliverySettingsScreen extends ConsumerWidget {
  const DeliverySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => AdminSectionScaffold(
    key: const Key('delivery-settings-screen'),
    appBar: AdminAppBar(
      title: Text(
        tr(context, 'Delivery Settings'),
        style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
      ),
    ),
    body: ref
        .watch(currentLocationProvider)
        .when(
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
              ? Center(
                  child: Text(tr(context, 'Choose a location to continue.')),
                )
              : PelinesPageBody(
                  width: PelinesPageWidth.dashboard,
                  child: ListView(
                    padding: const EdgeInsets.all(PelinesSpacing.lg),
                    children: [
                      Text(
                        tr(
                          context,
                          'Configure flat-fee delivery for regular and catering orders at this location.',
                        ),
                      ),
                      const SizedBox(height: 24),
                      OperationsGrid(
                        children: [
                          _DeliverySummary(location: location, catering: false),
                          _DeliverySummary(location: location, catering: true),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
  );
}

/// Presentation is shared; each service reads only its own model and fee fields.
class _DeliverySummary extends ConsumerWidget {
  const _DeliverySummary({required this.location, required this.catering});
  final Location location;
  final bool catering;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = catering ? 'Catering Delivery' : 'Regular Delivery';
    final kind = catering ? 'catering' : 'regular';
    late final bool enabled;
    late final int fee;
    late final int minimum;
    var usesDefault = false;
    try {
      if (catering) {
        final settings = CateringDeliverySettings.fromJson(
          location.cateringDeliveryJson,
        );
        enabled = settings.enabled;
        usesDefault = settings.usesDefault;
        fee = location.deliveryFeeCents;
        minimum = location.deliveryMinimumCents;
      } else {
        final settings = RegularDeliverySettings.fromJson(
          location.regularDeliveryJson,
        );
        enabled = settings.enabled;
        fee = settings.feeCents;
        minimum = settings.minimumCents;
      }
    } on UnsupportedRegularDeliveryFormat catch (error) {
      return _error(context, title, error);
    } on UnsupportedCateringDeliveryFormat catch (error) {
      return _error(context, title, error);
    }
    final busy = catering
        ? ref.watch(cateringDeliveryProvider).isBusy
        : ref.watch(regularDeliveryProvider).isBusy;
    return PelinesSettingsCard(
      key: Key('$kind-delivery-summary'),
      title: tr(context, title),
      children: [
        OperationsStatus(enabled: enabled),
        if (usesDefault) ...[
          const SizedBox(height: 8),
          Text(tr(context, 'Using default setting')),
        ],
        const SizedBox(height: 16),
        Text(tr(context, 'Delivery fee')),
        Text(
          money(fee),
          key: Key('$kind-summary-fee'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(tr(context, 'Delivery Minimum')),
        Text(
          money(minimum),
          key: Key('$kind-summary-minimum'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            context,
            'This value is currently managed outside the mobile app.',
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          key: Key('edit-$kind-delivery'),
          style: PelinesControlStyles.button(PelinesButtonVariant.secondary),
          onPressed: busy
              ? null
              : () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => catering
                        ? CateringDeliveryScreen(location: location)
                        : RegularDeliveryScreen(location: location),
                  ),
                ),
          child: Text(
            tr(
              context,
              catering ? 'Edit catering delivery' : 'Edit regular delivery',
            ),
          ),
        ),
      ],
    );
  }

  Widget _error(BuildContext context, String title, Object error) =>
      PelinesSettingsCard(
        title: tr(context, title),
        children: [
          Text(
            tr(context, error.toString()),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      );
}
