import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/navigation/admin_navigation.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/locations/presentation/pelines_location_context.dart';

Location headerLocation({
  String name = 'Tualatin',
  String? address = '7670 SW Nyberg St, Tualatin, OR 97062',
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
  test(
    'header street extraction preserves uncertain and incomplete addresses',
    () {
      for (final entry in <String, String>{
        '7670 SW Nyberg St, Tualatin, OR 97062': '7670 SW Nyberg St',
        '25627 SE Stark St, Troutdale, OR 97060': '25627 SE Stark St',
        '123 Main St, Suite 4, Portland, OR 97201': '123 Main St, Suite 4',
        '123 Main Street, Portland, OR': '123 Main Street',
        '123 Main St, Portland, OR 97201-1234, USA': '123 Main St',
        '7670 SW Nyberg St': '7670 SW Nyberg St',
        '7670 SW Nyberg St, Tualatin': '7670 SW Nyberg St, Tualatin',
        'Unknown, extra context': 'Unknown, extra context',
        '123 Main St, Building A, Portland, OR 97201':
            '123 Main St, Building A, Portland, OR 97201',
        '123 Main St, Portland, ZZ 97201': '123 Main St, Portland, ZZ 97201',
        '': '',
      }.entries) {
        expect(compactLocationStreet(entry.key), entry.value);
      }
      expect(compactLocationStreet(null), isNull);
      expect(compactLocationStreet('   '), '');
    },
  );
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
          var refreshes = 0;
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
                      actions: [
                        AdminHeaderRefresh(onPressed: () => refreshes++),
                      ],
                    ),
                    body: ListView(
                      children: [
                        const Text('Approved description'),
                        const TextField(key: Key('section-controls')),
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
          expect(find.text('Tualatin · 7670 SW Nyberg St'), findsOneWidget);
          expect(find.byType(PelinesLocationContext), findsOneWidget);
          final heading = find.byKey(const Key('persistent-section-header'));
          final title = find.text(
            lang == 'en' ? 'Catering Menu' : 'Menú de catering',
          );
          expect(title, findsOneWidget);
          final locationText = tester.widget<Text>(
            find.descendant(
              of: find.byType(PelinesLocationContext),
              matching: find.byType(Text),
            ),
          );
          final locationParagraph = tester.renderObject<RenderParagraph>(
            find
                .descendant(
                  of: find.byType(PelinesLocationContext),
                  matching: find.byType(RichText),
                )
                .first,
          );
          expect(locationParagraph.didExceedMaxLines, isFalse);
          expect(
            locationText.textSpan!.toPlainText(),
            'Tualatin \u00b7 7670 SW Nyberg St',
          );
          expect(
            find.descendant(
              of: find.byType(PelinesLocationContext),
              matching: find.byType(InkWell),
            ),
            findsNothing,
          );
          final locationRect = tester.getRect(
            find.byType(PelinesLocationContext),
          );
          final titleRect = tester.getRect(title);
          final refreshRect = tester.getRect(find.byType(AdminHeaderRefresh));
          expect(locationRect.top, greaterThanOrEqualTo(titleRect.bottom));
          if (width < 360 * scale) {
            expect(refreshRect.top, greaterThanOrEqualTo(titleRect.bottom));
          } else {
            expect(refreshRect.left, greaterThanOrEqualTo(titleRect.right));
            expect(
              (refreshRect.center.dy - titleRect.center.dy).abs(),
              lessThan(1),
            );
          }
          expect(
            tester.getRect(find.text('Approved description')).top,
            greaterThanOrEqualTo(locationRect.bottom),
          );
          expect(
            tester.getRect(find.byKey(const Key('section-controls'))).top,
            greaterThanOrEqualTo(
              tester.getRect(find.text('Approved description')).bottom,
            ),
          );
          expect(find.byType(AdminHeaderRefresh), findsOneWidget);
          await tester.tap(find.byType(AdminHeaderRefresh));
          expect(refreshes, 1);
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
              name: 'Troutdale',
              address: '25627 SE Stark St, Troutdale, OR 97060',
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Troutdale · 25627 SE Stark St'), findsOneWidget);
          expect(find.textContaining('Tualatin'), findsNothing);
          expect(find.textContaining('97060'), findsNothing);
          expect(find.textContaining(', OR'), findsNothing);
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
