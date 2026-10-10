import '../../../app/theme/app_theme.dart';
import 'operations_parity_widgets.dart';

import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../models/location.dart';
import '../models/temporary_closure.dart';
import '../models/business_hours.dart';
import '../models/regular_delivery.dart';
import '../models/catering_delivery.dart';
import '../models/auto_accept.dart';
import '../../orders/presentation/order_ui_helpers.dart';
import 'business_hours_screen.dart';
import 'regular_delivery_screen.dart';
import 'catering_delivery_screen.dart';
import 'auto_accept_screen.dart';
import 'closure_form_screen.dart';
import 'pickup_service_card.dart';
import '../models/auto_cancellation.dart';
import '../providers/locations_providers.dart';
import '../providers/store_operations_controller.dart';

part 'locations_content.dart';
part 'pickup_settings_screen.dart';

enum StoreOperationsSection { all, locations, pickup, delivery }

class StoreOperationsScreen extends ConsumerWidget {
  const StoreOperationsScreen({
    this.section = StoreOperationsSection.all,
    super.key,
  });
  final StoreOperationsSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<StoreOperationState>(storeOperationsProvider, (
      StoreOperationState? previous,
      StoreOperationState next,
    ) {
      if (next.message == null || next.message == previous?.message) return;
      final bool failed = next.phase == StoreOperationPhase.error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next.message!),
          backgroundColor: failed ? Theme.of(context).colorScheme.error : null,
        ),
      );
    });

    final AsyncValue<Location?> current = ref.watch(currentLocationProvider);
    final StoreOperationState operation = ref.watch(storeOperationsProvider);
    return AdminSectionScaffold(
      showLocation: section == StoreOperationsSection.locations,
      appBar: AdminAppBar(
        title: Text(
          tr(context, switch (section) {
            StoreOperationsSection.all => 'Store Operations',
            StoreOperationsSection.locations => 'Locations',
            StoreOperationsSection.pickup => 'Pickup Settings',
            StoreOperationsSection.delivery => 'Delivery Settings',
          }),
          style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
        ),
      ),
      body: current.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error.toString(), textAlign: TextAlign.center),
          ),
        ),
        data: (Location? location) => location == null
            ? Center(
                child: Text(
                  tr(context, 'Choose a location to manage store operations.'),
                ),
              )
            : _OperationsContent(
                location: location,
                operation: operation,
                section: section,
              ),
      ),
    );
  }
}

class _OperationsContent extends ConsumerWidget {
  const _OperationsContent({
    required this.location,
    required this.operation,
    required this.section,
  });
  final StoreOperationsSection section;

  final Location location;
  final StoreOperationState operation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (section == StoreOperationsSection.locations) {
      return _LocationsContent(
        location: location,
        onlineOrders: _onlineOrders(context, ref),
      );
    }
    return PelinesPageBody(
      width: PelinesPageWidth.dashboard,
      child: ListView(
        padding: const EdgeInsets.all(PelinesSpacing.lg),
        children: <Widget>[
          OperationsCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PelinesSectionHeading(tr(context, 'Location')),
                  PelinesStateBadge(
                    label: location.name,
                    foreground: PelinesColors.brandPrimary,
                    background: PelinesColors.brandPrimarySoft,
                    icon: Icons.storefront_outlined,
                  ),
                  if (location.address?.trim().isNotEmpty ?? false) ...<Widget>[
                    const SizedBox(height: PelinesSpacing.xs),
                    Text(
                      location.address!,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: PelinesColors.textSecondary),
                    ),
                  ],
                  if (location.phone?.trim().isNotEmpty ?? false) ...[
                    const SizedBox(height: 8),
                    Text(location.phone!),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: PelinesSpacing.xl),
          OperationsGrid(
            children: [
              if (section == StoreOperationsSection.all ||
                  section == StoreOperationsSection.locations)
                _onlineOrders(context, ref),
              if (section == StoreOperationsSection.all ||
                  section == StoreOperationsSection.locations)
                _TemporaryClosuresCard(location: location),
              if (section != StoreOperationsSection.delivery)
                _BusinessHoursCard(location: location),
              if (section == StoreOperationsSection.all ||
                  section == StoreOperationsSection.delivery) ...[
                _RegularDeliveryCard(location: location),
                _CateringDeliveryCard(location: location),
              ],
              if (section == StoreOperationsSection.all ||
                  section == StoreOperationsSection.pickup)
                _AutoAcceptCard(location: location),
            ],
          ),
        ],
      ),
    );
  }

  Widget _onlineOrders(BuildContext context, WidgetRef ref) {
    final accepting = location.isAcceptingOrders;
    return OperationsCard(
      child: Padding(
        padding: const EdgeInsets.all(PelinesSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              tr(
                context,
                section == StoreOperationsSection.locations
                    ? 'Online Ordering'
                    : 'Online Orders',
              ),
              style: PelinesTypography.sectionTitle(
                Theme.of(context).textTheme,
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              label: 'Accepting online orders for ${location.name}',
              toggled: accepting,
              child: SwitchListTile(
                key: const Key('accepting-orders-switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  accepting
                      ? tr(context, 'Accepting online orders')
                      : tr(context, 'Online orders paused'),
                ),
                subtitle: Text(
                  accepting
                      ? tr(context, 'Orders can be placed online.')
                      : tr(context, 'New online orders are currently blocked.'),
                ),
                value: accepting,
                onChanged: operation.isBusy
                    ? null
                    : (bool requested) =>
                          _confirmChange(context, ref, location, requested),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                context,
                'When disabled, this location will stop accepting new online orders for both regular and catering orders. Existing orders are not cancelled.',
              ),
            ),
            if (operation.isBusy) ...<Widget>[
              const SizedBox(height: 16),
              const LinearProgressIndicator(
                key: Key('store-operation-progress'),
              ),
              const SizedBox(height: 8),
              Text(
                operation.phase == StoreOperationPhase.submitting
                    ? tr(context, 'Saving change…')
                    : tr(context, 'Checking the current server setting…'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmChange(
    BuildContext context,
    WidgetRef ref,
    Location captured,
    bool requested,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          section == StoreOperationsSection.locations
              ? tr(
                  context,
                  requested
                      ? 'Start accepting online orders for {location}?'
                      : 'Stop online orders for {location}?',
                ).replaceAll('{location}', captured.name)
              : requested
              ? 'Start accepting online orders for ${captured.name}?'
              : 'Stop online orders for ${captured.name}?',
        ),
        content: Text(
          requested
              ? tr(
                  context,
                  'This location will be allowed to receive new online orders again. Business hours and other availability rules still apply.',
                )
              : tr(
                  context,
                  'New regular and catering orders will be blocked for this location. Existing orders are not cancelled.',
                ),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('accepting-orders-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              requested
                  ? tr(context, 'Keep closed')
                  : tr(context, 'Keep accepting'),
            ),
          ),
          FilledButton(
            style: PelinesControlStyles.button(PelinesButtonVariant.primary),
            key: const Key('accepting-orders-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              requested
                  ? tr(context, 'Start orders')
                  : tr(context, 'Stop orders'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final Location? current = ref.read(currentLocationProvider).value;
    if (current?.id != captured.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(context, 'The selected location changed. Please confirm again.'),
          ),
        ),
      );
      return;
    }
    await ref
        .read(storeOperationsProvider.notifier)
        .setAcceptingOrders(
          locationId: captured.id,
          observedValue: captured.isAcceptingOrders,
          requestedValue: requested,
        );
  }
}

class _AutoAcceptCard extends StatelessWidget {
  const _AutoAcceptCard({required this.location});
  final Location location;

  @override
  Widget build(BuildContext context) {
    late final AutoAcceptSettings settings;
    try {
      settings = AutoAcceptSettings.fromJson(location.servicePrefsJson);
    } on UnsupportedAutoAcceptFormat catch (error) {
      return OperationsCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                tr(context, 'Auto-Accept Orders'),
                style: PelinesTypography.sectionTitle(
                  Theme.of(context).textTheme,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                error.toString(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ),
      );
    }
    return OperationsCard(
      key: const Key('auto-accept-card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              tr(context, 'Auto-Accept Orders'),
              style: PelinesTypography.sectionTitle(
                Theme.of(context).textTheme,
              ),
            ),
            const SizedBox(height: 12),
            Text(tr(context, 'Regular orders')),
            Text(
              settings.regular
                  ? tr(context, 'Automatically accepted after payment')
                  : tr(context, 'Manual acceptance'),
            ),
            const SizedBox(height: 10),
            Text(tr(context, 'Catering orders')),
            Text(
              settings.catering
                  ? tr(context, 'Automatically accepted after payment')
                  : tr(context, 'Manual acceptance'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: PelinesControlStyles.button(
                PelinesButtonVariant.secondary,
              ),
              key: const Key('edit-auto-accept'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AutoAcceptScreen(location: location),
                ),
              ),
              child: Text(tr(context, 'Edit auto-accept')),
            ),
          ],
        ),
      ),
    );
  }
}

class _CateringDeliveryCard extends StatelessWidget {
  const _CateringDeliveryCard({required this.location});
  final Location location;

  @override
  Widget build(BuildContext context) {
    late final CateringDeliverySettings settings;
    try {
      settings = CateringDeliverySettings.fromJson(
        location.cateringDeliveryJson,
      );
    } on UnsupportedCateringDeliveryFormat catch (error) {
      return OperationsCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                tr(context, 'Catering Delivery'),
                style: PelinesTypography.sectionTitle(
                  Theme.of(context).textTheme,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                error.toString(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ),
      );
    }
    return OperationsCard(
      key: const Key('catering-delivery-card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              tr(context, 'Catering Delivery'),
              style: PelinesTypography.sectionTitle(
                Theme.of(context).textTheme,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              settings.enabled
                  ? tr(context, 'Enabled')
                  : tr(context, 'Disabled'),
            ),
            if (settings.usesDefault)
              Text(tr(context, 'Using default setting')),
            const SizedBox(height: 12),
            Text('Delivery fee: ${money(location.deliveryFeeCents)}'),
            Text('Minimum order: ${money(location.deliveryMinimumCents)}'),
            const SizedBox(height: 12),
            OutlinedButton(
              style: PelinesControlStyles.button(
                PelinesButtonVariant.secondary,
              ),
              key: const Key('edit-catering-delivery'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CateringDeliveryScreen(location: location),
                ),
              ),
              child: Text(tr(context, 'Edit catering delivery')),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegularDeliveryCard extends StatelessWidget {
  const _RegularDeliveryCard({required this.location});
  final Location location;
  @override
  Widget build(BuildContext context) {
    late final RegularDeliverySettings settings;
    try {
      settings = RegularDeliverySettings.fromJson(location.regularDeliveryJson);
    } on UnsupportedRegularDeliveryFormat catch (error) {
      return OperationsCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                tr(context, 'Regular Delivery'),
                style: PelinesTypography.sectionTitle(
                  Theme.of(context).textTheme,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                error.toString(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ),
      );
    }
    return OperationsCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              tr(context, 'Regular Delivery'),
              style: PelinesTypography.sectionTitle(
                Theme.of(context).textTheme,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              settings.enabled
                  ? tr(context, 'Enabled')
                  : tr(context, 'Disabled'),
            ),
            const SizedBox(height: 12),
            Text('Delivery fee: ${money(settings.feeCents)}'),
            Text('Minimum order: ${money(settings.minimumCents)}'),
            const SizedBox(height: 12),
            OutlinedButton(
              style: PelinesControlStyles.button(
                PelinesButtonVariant.secondary,
              ),
              key: const Key('edit-regular-delivery'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => RegularDeliveryScreen(location: location),
                ),
              ),
              child: Text(tr(context, 'Edit regular delivery')),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessHoursCard extends StatelessWidget {
  const _BusinessHoursCard({
    required this.location,
    this.locationsStyle = false,
  });
  final Location location;
  final bool locationsStyle;

  @override
  Widget build(BuildContext context) {
    final BusinessHoursSchedule? schedule;
    try {
      schedule = location.hoursJson == null
          ? null
          : BusinessHoursSchedule.fromJson(location.hoursJson!);
    } on FormatException catch (error) {
      if (!locationsStyle) rethrow;
      return OperationsCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PelinesSectionHeading(tr(context, 'Business Hours')),
              const SizedBox(height: 12),
              Text(
                tr(context, error.message),
                style: const TextStyle(color: PelinesColors.destructive),
              ),
            ],
          ),
        ),
      );
    }
    return OperationsCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              tr(context, 'Business Hours'),
              style: PelinesTypography.sectionTitle(
                Theme.of(context).textTheme,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                context,
                'Business hours affect regular online ordering. Catering availability is handled separately.',
              ),
            ),
            const SizedBox(height: 12),
            if (schedule == null)
              Text(tr(context, 'Business hours are not configured.'))
            else
              for (int index = 0; index < 7; index++)
                if (locationsStyle)
                  _LocationDayRow(
                    day: index,
                    hours: schedule.days[index],
                    summary: _summary(context, schedule.days[index]),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 92,
                          child: Text(businessDayLabels[index].substring(0, 3)),
                        ),
                        Expanded(
                          child: Text(_summary(context, schedule.days[index])),
                        ),
                      ],
                    ),
                  ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: PelinesControlStyles.button(
                PelinesButtonVariant.secondary,
              ),
              key: const Key('edit-business-hours'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => BusinessHoursScreen(location: location),
                ),
              ),
              child: Text(tr(context, 'Edit business hours')),
            ),
          ],
        ),
      ),
    );
  }

  String _summary(BuildContext context, BusinessDayHours day) {
    if (day.closed) return tr(context, 'Closed');
    String display(String value) {
      final List<String> parts = value.split(':');
      return TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ).format(context);
    }

    return '${display(day.open)} – ${display(day.close)}';
  }
}

class _TemporaryClosuresCard extends StatelessWidget {
  const _TemporaryClosuresCard({
    required this.location,
    this.locationsStyle = false,
  });
  final Location location;
  final bool locationsStyle;

  @override
  Widget build(BuildContext context) {
    late final List<TemporaryClosure> closures;
    try {
      closures = closuresFromExtras(location.hoursExtrasJson).toList()
        ..sort(
          (TemporaryClosure a, TemporaryClosure b) =>
              a.start.compareTo(b.start),
        );
    } on UnsupportedClosureFormat catch (error) {
      return OperationsCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                tr(context, 'Temporary Closures'),
                style: PelinesTypography.sectionTitle(
                  Theme.of(context).textTheme,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                error.toString(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ),
      );
    }
    return OperationsCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              tr(context, 'Temporary Closures'),
              style: PelinesTypography.sectionTitle(
                Theme.of(context).textTheme,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                context,
                'Temporary closures affect regular online ordering. Catering availability is handled separately by the current backend.',
              ),
            ),
            const SizedBox(height: 12),
            if (closures.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(tr(context, 'No temporary closures.')),
              )
            else
              for (final TemporaryClosure closure in closures)
                ListTile(
                  key: Key('closure-${closure.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    closure.reason.isEmpty
                        ? tr(context, 'Temporary closure')
                        : closure.reason,
                  ),
                  subtitle: Text(
                    '${_dateRange(closure, locationsStyle ? Localizations.localeOf(context).toLanguageTag() : null)}${locationsStyle && closure.notes.trim().isNotEmpty ? '\n${closure.notes}' : ''}\n${closure.active ? tr(context, 'Active') : tr(context, 'Inactive')}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openForm(context, closure),
                ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: PelinesControlStyles.button(
                PelinesButtonVariant.secondary,
              ),
              key: const Key('add-closure'),
              onPressed: () => _openForm(context, null),
              icon: const Icon(Icons.add),
              label: Text(tr(context, 'Add closure')),
            ),
          ],
        ),
      ),
    );
  }

  String _dateRange(TemporaryClosure closure, [String? locale]) {
    final DateFormat format = DateFormat.yMMMd(locale);
    final String start = format.format(parseCalendarDate(closure.start)!);
    final String end = format.format(parseCalendarDate(closure.end)!);
    return closure.start == closure.end ? start : '$start – $end';
  }

  Future<void> _openForm(BuildContext context, TemporaryClosure? closure) =>
      Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              ClosureFormScreen(location: location, closure: closure),
        ),
      );
}
