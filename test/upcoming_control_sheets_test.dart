import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/models/orders_date_filter.dart';
import 'package:pelines_admin_app/features/orders/models/upcoming_filters.dart';
import 'package:pelines_admin_app/features/orders/presentation/upcoming_control_sheets.dart';

import 'order_test_data.dart';
import 'upcoming_sheet_helpers.dart';

Future<void> mount(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  String language = 'en',
  OrderType? type,
  UpcomingFilters filters = const UpcomingFilters(),
  ValueChanged<UpcomingTypeSelection?>? onType,
  ValueChanged<UpcomingFilters?>? onFilters,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 850));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: Locale(language),
      supportedLocales: AdminLocalizations.supportedLocales,
      localizationsDelegates: const [
        AdminLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                key: const Key('upcoming-sort'),
                onPressed: () async {
                  final result = await showUpcomingSort(context, type);
                  onType?.call(result);
                },
                child: const Text('Open sort'),
              ),
              TextButton(
                key: const Key('upcoming-filters'),
                onPressed: () async {
                  final result = await showUpcomingFilters(context, filters);
                  onFilters?.call(result);
                },
                child: const Text('Open filters'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

OrderType? selectedType(WidgetTester tester) => tester
    .widget<RadioGroup<OrderType?>>(find.byType(RadioGroup<OrderType?>))
    .groupValue;
OrderStatus? selectedStatus(WidgetTester tester) => tester
    .widget<RadioGroup<OrderStatus?>>(find.byType(RadioGroup<OrderStatus?>))
    .groupValue;

void main() {
  testWidgets(
    'Sort has only real types, red radio, isolated draft and Apply All',
    (tester) async {
      UpcomingTypeSelection? result;
      await mount(
        tester,
        type: OrderType.catering,
        onType: (value) => result = value,
      );
      await upcomingTap(tester, 'upcoming-sort');
      expect(selectedType(tester), OrderType.catering);
      expect(find.byType(RadioListTile<OrderType?>), findsNWidgets(3));
      expect(
        tester
            .widget<RadioListTile<OrderType?>>(
              find.byKey(const Key('upcoming-type-catering')),
            )
            .activeColor,
        PelinesColors.brandPrimary,
      );
      await upcomingTap(tester, 'upcoming-type-online');
      expect(result, isNull);
      await upcomingDismiss(tester);
      expect(result, isNull);
      await upcomingTap(tester, 'upcoming-sort');
      expect(selectedType(tester), OrderType.catering);
      await upcomingTap(tester, 'upcoming-type-all');
      await upcomingTap(tester, 'upcoming-sheet-apply');
      expect(result, isNotNull);
      expect(result!.type, isNull);
    },
  );

  testWidgets(
    'Filter Reset is draft only; Back/outside/swipe discard; Apply resets',
    (tester) async {
      UpcomingFilters? result;
      final applied = UpcomingFilters(
        from: DateTime.utc(2030, 5, 2),
        to: DateTime.utc(2030, 5, 4),
        status: OrderStatus.confirmed,
      );
      await mount(
        tester,
        filters: applied,
        onFilters: (value) => result = value,
      );
      for (final close in ['back', 'outside', 'swipe']) {
        await upcomingTap(tester, 'upcoming-filters');
        expect(selectedStatus(tester), OrderStatus.confirmed);
        await upcomingTap(tester, 'upcoming-filter-reset');
        expect(selectedStatus(tester), isNull);
        expect(result, isNull);
        if (close == 'back') {
          await upcomingDismiss(tester);
        } else if (close == 'outside') {
          await tester.tapAt(const Offset(5, 5));
          await tester.pumpAndSettle();
        } else {
          final sheet = tester.getRect(find.byType(BottomSheet));
          await tester.flingFrom(
            Offset(sheet.center.dx, sheet.top + 12),
            const Offset(0, 700),
            1600,
          );
          await tester.pumpAndSettle();
        }
        expect(find.byType(BottomSheet), findsNothing);
        expect(result, isNull);
      }
      await upcomingTap(tester, 'upcoming-filters');
      expect(selectedStatus(tester), OrderStatus.confirmed);
      await upcomingTap(tester, 'upcoming-filter-reset');
      await upcomingTap(tester, 'upcoming-sheet-apply');
      expect(result!.isDefault, isTrue);
    },
  );

  testWidgets(
    'inclusive From/To validate before Apply; status maps terminal to delivered',
    (tester) async {
      UpcomingFilters? result;
      await mount(tester, onFilters: (value) => result = value);
      await upcomingTap(tester, 'upcoming-filters');
      expect(find.byType(RadioListTile<OrderStatus?>), findsNWidgets(6));
      await upcomingDate(tester, 'from', DateTime(2030, 5, 4));
      await upcomingDate(tester, 'to', DateTime(2030, 5, 2));
      await upcomingTap(tester, 'upcoming-sheet-apply');
      expect(result, isNull);
      expect(find.text('From must be on or before To.'), findsOneWidget);
      await upcomingDate(tester, 'to', DateTime(2030, 5, 4));
      await upcomingTap(tester, 'upcoming-status-delivered');
      expect(find.text('Picked up / Delivered'), findsOneWidget);
      expect(selectedStatus(tester), OrderStatus.delivered);
      await upcomingTap(tester, 'upcoming-sheet-apply');
      expect(result!.from, DateTime.utc(2030, 5, 4));
      expect(result!.to, DateTime.utc(2030, 5, 4));
      expect(result!.status, OrderStatus.delivered);
    },
  );

  for (final width in [320.0, 390.0, 768.0, 1400.0]) {
    for (final language in ['en', 'es']) {
      testWidgets('sheets accessible and scrollable $width/$language/2x', (
        tester,
      ) async {
        await mount(tester, width: width, scale: 2, language: language);
        for (final control in ['sort', 'filters']) {
          await upcomingTap(tester, 'upcoming-$control');
          expect(
            tester
                .getSize(find.byKey(const Key('upcoming-sheet-scroll')))
                .width,
            lessThanOrEqualTo(640),
          );
          expect(
            tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
            isTrue,
          );
          expect(
            find.text(
              language == 'es'
                  ? (control == 'sort' ? 'Ordenar' : 'Filtros')
                  : (control == 'sort' ? 'Sort' : 'Filters'),
            ),
            findsOneWidget,
          );
          await upcomingTap(
            tester,
            control == 'sort'
                ? 'upcoming-type-catering'
                : 'upcoming-status-delivered',
          );
          expect(
            tester
                .getSize(find.byKey(const Key('upcoming-sheet-apply')))
                .height,
            greaterThanOrEqualTo(48),
          );
          await upcomingTap(tester, 'upcoming-sheet-apply');
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  test(
    'Pacific range includes entire DST days and intersects future scope',
    () {
      for (final (day, start, end, previous, next) in [
        (
          DateTime.utc(2026, 3, 8),
          '2026-03-08T08:00:00Z',
          '2026-03-09T06:59:59Z',
          '2026-03-08T07:59:59Z',
          '2026-03-09T07:00:00Z',
        ),
        (
          DateTime.utc(2026, 11, 1),
          '2026-11-01T07:00:00Z',
          '2026-11-02T07:59:59Z',
          '2026-11-01T06:59:59Z',
          '2026-11-02T08:00:00Z',
        ),
      ]) {
        final range = UpcomingFilters(from: day, to: day);
        final orders = [previous, start, end, next]
            .map(
              (at) =>
                  OrderSummary.fromJson({...orderJson(), 'scheduledFor': at}),
            )
            .toList();
        expect(
          orders
              .where(range.matches)
              .map((o) => o.scheduledFor!.toIso8601String()),
          [
            DateTime.parse(start).toIso8601String(),
            DateTime.parse(end).toIso8601String(),
          ],
        );
        final future = filterOrdersByDate(
          orders,
          OrdersDateFilter.upcoming,
          now: DateTime.parse(start),
        );
        expect(future.where(range.matches), isEmpty);
      }
    },
  );
}
