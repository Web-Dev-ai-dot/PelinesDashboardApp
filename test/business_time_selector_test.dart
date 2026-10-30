import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';

import 'dart:math' as math;

import 'package:pelines_admin_app/features/locations/presentation/business_hours_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/features/locations/models/business_hours.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/presentation/business_time_selector.dart';

import 'catering_category_section_test.dart' show show;
import 'locations_parity_test.dart' as locations;

class SavingLocations extends locations.Repo {
  int saves = 0;
  bool reject = false;
  BusinessHoursSchedule? submitted;
  @override
  Future<Location> saveBusinessHours({
    required String locationId,
    required DateTime originalUpdatedAt,
    required BusinessHoursSchedule schedule,
  }) async {
    saves++;
    submitted = schedule;
    if (reject) throw ArgumentError('Test save rejected');
    final old = value;
    return value = Location(
      id: old.id,
      name: old.name,
      slug: old.slug,
      address: old.address,
      phone: old.phone,
      isActive: old.isActive,
      isAcceptingOrders: old.isAcceptingOrders,
      deliveryFeeCents: old.deliveryFeeCents,
      deliveryMinimumCents: old.deliveryMinimumCents,
      createdAt: old.createdAt,
      updatedAt: old.updatedAt,
      hoursJson: schedule.toJson(),
      hoursExtrasJson: old.hoursExtrasJson,
    );
  }
}

Future<void> tap(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key));
  await show(t, f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  test('closed day equivalence ignores hidden hours; open day comparison stays strict', () {
    final source = BusinessHoursSchedule(
      List.generate(
        7,
        (_) =>
            const BusinessDayHours(open: '09:15', close: '18:20', closed: true),
      ),
    );
    expect(
      source.sameAs(BusinessHoursSchedule.fromJson(source.toJson())),
      true,
    );
    final open = source.replaceDay(
      0,
      const BusinessDayHours(open: '09:15', close: '18:20', closed: false),
    );
    expect(open.sameAs(source), false);
    expect(
      open.sameAs(open.replaceDay(0, open.days[0].copyWith(close: '18:21'))),
      false,
    );
  });

  testWidgets(
    'dial edits Opens and Closes independently; Save stages then weekly Save persists only changed day',
    (t) async {
      final repo = SavingLocations();
      await locations.mount(t, repo);
      await locations.reveal(t, find.byKey(const Key('location-edit-time-0')));
      await t.tap(find.byKey(const Key('location-edit-time-0')));
      await t.pumpAndSettle();
      await tap(t, 'dial-hour-10');
      await tap(t, 'dial-minute-15');
      final dial = t.getRect(find.byKey(const ValueKey('business-time-dial')));
      final gesture = await t.startGesture(dial.center);
      await gesture.moveTo(
        dial.center +
            Offset(math.sin(17 * math.pi / 30), -math.cos(17 * math.pi / 30)) *
                (dial.width / 2 - 28),
      );
      await gesture.up();
      await t.pumpAndSettle();
      await tap(t, 'time-closes');
      await tap(t, 'dial-hour-6');
      await tap(t, 'dial-minute-30');
      await tap(t, 'business-time-save');
      expect(repo.saves, 0);
      expect(find.byKey(const Key('business-hours-unsaved')), findsOneWidget);
      await locations.reveal(t, find.byKey(const Key('business-hours-save')));
      await t.tap(find.byKey(const Key('business-hours-save')));
      await t.pumpAndSettle();
      expect(repo.saves, 1);
      expect(repo.submitted!.days[0].open, '10:17');
      expect(repo.submitted!.days[0].close, '18:30');
      expect(repo.submitted!.days[1].open, '09:00');
      expect(repo.submitted!.days[6].closed, true);
      expect(find.byKey(const Key('business-hours-unsaved')), findsNothing);
    },
  );
  testWidgets(
    'Closed retains draft on rejected weekly save; retry is possible',
    (t) async {
      final repo = SavingLocations()..reject = true;
      await locations.mount(t, repo);
      await locations.reveal(t, find.byKey(const Key('location-closed-0')));
      await t.tap(find.byKey(const Key('location-closed-0')));
      await t.pumpAndSettle();
      expect(repo.saves, 0);
      await locations.reveal(t, find.byKey(const Key('business-hours-save')));
      await t.tap(find.byKey(const Key('business-hours-save')));
      await t.pumpAndSettle();
      expect(repo.saves, 1);
      expect(find.byKey(const Key('business-hours-unsaved')), findsOneWidget);
      expect(
        t.widget<Checkbox>(find.byKey(const Key('location-closed-0'))).value,
        true,
      );
      repo.reject = false;
      await t.tap(find.byKey(const Key('business-hours-save')));
      await t.pumpAndSettle();
      expect(repo.saves, 2);
      expect(repo.submitted!.days[0].closed, true);
      expect(find.byKey(const Key('business-hours-unsaved')), findsNothing);
    },
  );
  testWidgets(
    'existing full weekly editor confirms Closed through canonical null hours',
    (t) async {
      final repo = SavingLocations();
      await locations.mount(t, repo);
      Navigator.of(t.element(find.byKey(const Key('locations-content')))).push(
        MaterialPageRoute<void>(
          builder: (_) => BusinessHoursScreen(location: repo.value),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('business-day-0')));
      await t.pumpAndSettle();
      await show(t, find.byKey(const Key('business-hours-save')));
      await t.tap(find.byKey(const Key('business-hours-save')));
      await t.pumpAndSettle();
      expect(repo.saves, 1);
      expect(repo.submitted!.days[0].closed, true);
      expect(find.byKey(const Key('business-day-0')), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  for (final viewport in [
    for (final width in [320.0, 390.0, 900.0])
      for (final scale in [1.0, 2.0]) (width, scale),
  ]) {
    final width = viewport.$1;
    final scale = viewport.$2;
    for (final lang in ['en', 'es']) {
      testWidgets(
        'time selector responsive $width $lang ${scale}x, numeric validation and draft handling',
        (t) async {
          t.view.physicalSize = Size(width, 600);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          BusinessDayHours? result;
          await t.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              locale: Locale(lang),
              supportedLocales: AdminLocalizations.supportedLocales,
              localizationsDelegates: const [
                AdminLocalizations.delegate,
                ...GlobalMaterialLocalizations.delegates,
              ],
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(
                builder: (c) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      result = await showBusinessTimeSelector(
                        c,
                        const BusinessDayHours(
                          open: '09:00',
                          close: '17:00',
                          closed: false,
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await t.tap(find.text('Open'));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          final opens = find.byKey(const ValueKey('time-opens'));
          final closes = find.byKey(const ValueKey('time-closes'));
          expect(t.getSize(opens).width, t.getSize(closes).width);
          expect(find.byType(ChoiceChip), findsNothing);
          expect(
            (t
                        .widget<Container>(
                          find.byKey(const ValueKey('time-range-segments')),
                        )
                        .decoration
                    as BoxDecoration)
                .color,
            PelinesColors.mutedSurface,
          );
          final am = find.byKey(const ValueKey('time-am')),
              pm = find.byKey(const ValueKey('time-pm'));
          expect(t.getTopLeft(am).dx, t.getTopLeft(pm).dx);
          expect(t.getRect(am).bottom, lessThanOrEqualTo(t.getRect(pm).top));
          expect(t.getSize(am).height, greaterThanOrEqualTo(48));
          expect(find.byKey(const ValueKey('time-colon')), findsOneWidget);
          final hour = find.byKey(const ValueKey('time-hour'));
          expect(
            t.widget<OutlinedButton>(hour).style!.foregroundColor!.resolve({}),
            PelinesColors.brandPrimary,
          );
          if (scale == 1 && width >= 390) {
            expect(t.getRect(am).top, closeTo(t.getRect(hour).top, 3));
          }
          final alternative = find.byKey(
            const ValueKey('business-time-keyboard'),
          );
          expect(
            t
                .widget<TextButton>(alternative)
                .style!
                .foregroundColor!
                .resolve({}),
            PelinesColors.textSecondary,
          );
          final dial = find.byKey(const ValueKey('business-time-dial'));
          expect(t.getSize(dial).width, lessThanOrEqualTo(280));
          await tap(t, 'dial-hour-12');
          await tap(t, 'dial-minute-0');
          await tap(t, 'time-pm');
          await tap(t, 'time-closes');
          await tap(t, 'dial-hour-12');
          await tap(t, 'dial-minute-30');
          // Noon/midnight are independent; invalid overnight ranges must not close.
          await tap(t, 'time-am');
          await tap(t, 'business-time-save');
          expect(find.byKey(const Key('business-time-save')), findsOneWidget);
          expect(result, isNull);
          await tap(t, 'business-time-keyboard');
          expect(
            find.byKey(const ValueKey('business-time-number-hour')),
            findsOneWidget,
          );
          await t.enterText(
            find.byKey(const ValueKey('business-time-number-hour')),
            '13',
          );
          await tap(t, 'business-time-save');
          expect(
            find.byKey(const ValueKey('business-time-save')),
            findsOneWidget,
          );
          t.view.viewInsets = const FakeViewPadding(bottom: 260);
          addTearDown(t.view.resetViewInsets);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          t.view.resetViewInsets();
          await t.pumpAndSettle();
          if (width == 390 && lang == 'en') {
            await t.enterText(
              find.byKey(const ValueKey('business-time-number-hour')),
              '12',
            );
            await t.enterText(
              find.byKey(const ValueKey('business-time-number-minute')),
              '30',
            );
            await tap(t, 'time-pm');
            await tap(t, 'time-opens');
            await tap(t, 'business-time-keyboard');
            await t.enterText(
              find.byKey(const ValueKey('business-time-number-hour')),
              '12',
            );
            await t.enterText(
              find.byKey(const ValueKey('business-time-number-minute')),
              '5',
            );
            await tap(t, 'time-am');
            await tap(t, 'business-time-save');
            expect(result!.open, '00:05');
            expect(result!.close, '12:30');
            expect(t.takeException(), isNull);
            return;
          }
          await tap(t, 'business-time-keyboard');
          await show(t, find.byTooltip(lang == 'en' ? 'Close' : 'Cerrar'));
          await t.tap(find.byTooltip(lang == 'en' ? 'Close' : 'Cerrar'));
          await t.pumpAndSettle();
          expect(result, isNull);
          expect(find.byKey(const Key('business-time-save')), findsNothing);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
