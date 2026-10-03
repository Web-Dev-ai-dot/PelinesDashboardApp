import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/locations/presentation/pelines_location_context.dart';

Location headerLocation({
  String name = 'Pelines Tualatin',
  String? address = '7670 SW Nyberg St',
}) => Location(
  id: name,
  name: name,
  slug: name,
  address: address,
  isActive: true,
  isAcceptingOrders: true,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class HeaderLocation extends CurrentLocationController {
  @override
  Future<Location?> build() async => headerLocation();
  void replace(Location? location) => state = AsyncData(location);
}

void main() {
  for (final width in [320.0, 390.0, 768.0, 1400.0]) {
    for (final lang in ['en', 'es']) {
      testWidgets('section context wraps and switches $width $lang 2x', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer(
          overrides: [currentLocationProvider.overrideWith(HeaderLocation.new)],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: Locale(lang),
              supportedLocales: AdminLocalizations.supportedLocales,
              localizationsDelegates: const [
                AdminLocalizations.delegate,
                ...GlobalMaterialLocalizations.delegates,
              ],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(children: [SectionLocationContext()]),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Pelines Tualatin · 7670 SW Nyberg St'),
          findsOneWidget,
        );
        expect(find.byType(PelinesLocationContext), findsOneWidget);
        final current =
            container.read(currentLocationProvider.notifier) as HeaderLocation;
        current.replace(
          headerLocation(
            name: 'Portland',
            address: '123 Long Canonical Address Suite 456, Portland',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Portland · 123 Long Canonical Address Suite 456, Portland',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Tualatin'), findsNothing);
        expect(tester.takeException(), isNull);
        for (final address in [null, '', '   ']) {
          current.replace(headerLocation(name: 'No address', address: address));
          await tester.pumpAndSettle();
          expect(find.text('No address'), findsOneWidget);
          expect(find.textContaining('·'), findsNothing);
        }
        current.replace(null);
        await tester.pumpAndSettle();
        expect(find.byType(PelinesLocationContext), findsNothing);
      });
    }
  }
}
