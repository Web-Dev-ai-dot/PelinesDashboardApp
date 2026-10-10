import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/navigation/admin_navigation.dart';
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
  void loading() => state = const AsyncLoading<Location?>();
}

void main() {
  for (final (width, scale) in [
    (320.0, 1.0),
    (390.0, 1.0),
    (768.0, 1.0),
    (1400.0, 1.0),
    (320.0, 2.0),
    (390.0, 2.0),
    (768.0, 2.0),
    (1400.0, 2.0),
  ]) {
    for (final lang in ['en', 'es']) {
      testWidgets(
        'persistent header scrolls and switches $width $lang $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final container = ProviderContainer(
            overrides: [
              currentLocationProvider.overrideWith(HeaderLocation.new),
            ],
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
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Builder(
                  builder: (context) => AdminSectionScaffold(
                    appBar: AdminAppBar(
                      title: Text(tr(context, 'Catering Menu')),
                    ),
                    body: ListView(
                      children: [
                        for (var i = 0; i < 50; i++)
                          SizedBox(height: 80, child: Text('Row $i')),
                      ],
                    ),
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
          final heading = find.byKey(const Key('persistent-section-header'));
          final title = find.text(
            lang == 'en' ? 'Catering Menu' : 'Menú de catering',
          );
          expect(title, findsOneWidget);
          final before = tester.getRect(heading);
          await tester.drag(find.byType(ListView), const Offset(0, -700));
          await tester.pumpAndSettle();
          expect(tester.getRect(heading), before);
          expect(title.hitTestable(), findsOneWidget);
          expect(
            find.byType(PelinesLocationContext).hitTestable(),
            findsOneWidget,
          );
          final current = container.read(
            currentLocationProvider.notifier,
          ) as HeaderLocation;
          current.loading();
          await tester.pump();
          expect(find.textContaining('Tualatin'), findsNothing);
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
            current.replace(
              headerLocation(name: 'No address', address: address),
            );
            await tester.pumpAndSettle();
            expect(find.text('No address'), findsOneWidget);
            expect(find.textContaining('·'), findsNothing);
          }
          current.replace(null);
          await tester.pumpAndSettle();
          expect(find.byType(PelinesLocationContext), findsNothing);
        },
      );
    }
  }
}
