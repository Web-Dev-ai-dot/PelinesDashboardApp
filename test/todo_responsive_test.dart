import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/app/theme/pelines_components.dart';
import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';
import 'package:pelines_admin_app/features/orders/presentation/todo_status_board.dart';

const _names = ['pending', 'confirmed', 'preparing', 'ready', 'delivered'];
final _board = find.byKey(const Key('todo-board-scroll'));
final _tabs = find.byKey(const Key('todo-tabs-scroll'));

ScrollController _controller(WidgetTester tester, Finder finder) =>
    tester.widget<SingleChildScrollView>(finder).controller!;

Future<void> _mount(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  String language = 'en',
}) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
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
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(scale),
          ),
          child: const TodoStatusBoard(orders: []),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _aligned(WidgetTester tester, int index) {
  final viewport = tester.getRect(_board);
  final column = tester.getRect(
    find.byKey(Key('todo-column-${_names[index]}')),
  );
  expect(column.left, closeTo(viewport.left, .1));
  expect(column.right, closeTo(viewport.right, .1));
  expect(
    _controller(tester, _board).offset,
    closeTo(index * viewport.width, .1),
  );
  final selected = tester.widget<OutlinedButton>(
    find.byKey(Key('todo-tab-${_names[index]}')),
  );
  expect(selected.style!.side!.resolve({})!.color, PelinesColors.textPrimary);
  for (final other in _names.where((name) => name != _names[index])) {
    final rect = tester.getRect(find.byKey(Key('todo-column-$other')));
    expect(
      rect.right <= viewport.left + .1 || rect.left >= viewport.right - .1,
      isTrue,
    );
  }
}

void _wholePills(WidgetTester tester) {
  final viewport = tester.getRect(_tabs);
  var visible = 0;
  for (final name in _names) {
    final rect = tester.getRect(find.byKey(Key('todo-tab-$name')));
    if (rect.right > viewport.left + .1 && rect.left < viewport.right - .1) {
      visible++;
      expect(rect.left, greaterThanOrEqualTo(viewport.left - .1));
      expect(rect.right, lessThanOrEqualTo(viewport.right + .1));
      expect(rect.height, greaterThanOrEqualTo(48));
    }
  }
  expect(visible, greaterThan(0));
}

void main() {
  setUpAll(() async {
    final font = FontLoader(PelinesTypography.bodyFamily)
      ..addFont(
        rootBundle.load(
          'assets/fonts/work_sans/WorkSans-VariableFont_wght.ttf',
        ),
      );
    await font.load();
  });
  testWidgets(
    'Pixel shows three equal pills and swipes through five whole columns',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _mount(tester, width: 393);
      final viewport = tester.getRect(_tabs);
      final initial = [
        for (final name in _names.take(3))
          tester.getRect(find.byKey(Key('todo-tab-$name'))),
      ];
      expect(initial[0].left, viewport.left);
      expect(initial[2].right, closeTo(viewport.right, .1));
      for (final rect in initial) {
        expect(rect.width, closeTo(initial.first.width, .1));
      }
      expect(initial[1].left - initial[0].right, closeTo(8, .1));
      expect(
        find.byKey(const Key('todo-tab-ready')).hitTestable(),
        findsNothing,
      );
      for (var index = 1; index < 5; index++) {
        await tester.fling(_board, const Offset(-100, 0), 1000);
        await tester.pumpAndSettle();
        _aligned(tester, index);
        _wholePills(tester);
      }
      expect(
        find.byKey(const Key('todo-tab-delivered')).hitTestable(),
        findsOneWidget,
      );
      final ready = tester.getRect(find.byKey(const Key('todo-tab-ready')));
      final picked = tester.getRect(
        find.byKey(const Key('todo-tab-delivered')),
      );
      expect(ready.left, closeTo(viewport.left, .1));
      expect(ready.width, closeTo(initial.first.width, .1));
      expect(picked.width, closeTo(initial.first.width, .1));
      expect(picked.left - ready.right, closeTo(8, .1));
      expect(
        viewport.right - picked.right,
        closeTo(initial.first.width + 8, .1),
      );
      final pill = tester.widget<OutlinedButton>(
        find.byKey(const Key('todo-tab-delivered')),
      );
      final heading = tester.widget<PelinesStateBadge>(
        find.byKey(const Key('todo-column-heading-delivered')),
      );
      expect(pill.onPressed, isNotNull);
      expect(pill.style!.backgroundColor!.resolve({}), PelinesColors.border);
      expect(
        pill.style!.foregroundColor!.resolve({}),
        PelinesColors.textPrimary,
      );
      expect(heading.background, PelinesColors.border);
      expect(heading.foreground, PelinesColors.textPrimary);
      expect(
        (PelinesColors.border.computeLuminance() + .05) /
            (PelinesColors.textPrimary.computeLuminance() + .05),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final language in ['en', 'es']) {
        testWidgets('complete columns and pills at $width/$scale/$language', (
          tester,
        ) async {
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await _mount(tester, width: width, scale: scale, language: language);
          _aligned(tester, 0);
          final initialHeight = tester.getSize(_board).height;
          _wholePills(tester);
          // Slow accidental movement returns to its original column.
          await tester.timedDrag(
            _board,
            const Offset(-30, 0),
            const Duration(seconds: 1),
          );
          await tester.pumpAndSettle();
          _aligned(tester, 0);
          // Deliberate distance advances one column.
          await tester.timedDrag(
            _board,
            Offset(-width * .6, 0),
            const Duration(seconds: 1),
          );
          await tester.pumpAndSettle();
          _aligned(tester, 1);
          _wholePills(tester);
          final active = tester.getRect(
            find.byKey(const Key('todo-tab-confirmed')),
          );
          expect(tester.getRect(_tabs).contains(active.center), isTrue);
          // A very large, fast gesture still advances only one column.
          await tester.fling(_board, Offset(-width * 3, 0), 3000);
          await tester.pumpAndSettle();
          _aligned(tester, 2);
          _wholePills(tester);
          expect(tester.getSize(_board).height, initialHeight);
          // Rebuild with new data (the Refresh path) retains the selection.
          await _mount(tester, width: width, scale: scale, language: language);
          _aligned(tester, 2);
          // Velocity can advance even below the distance threshold.
          await tester.fling(_board, const Offset(-70, 0), 1000);
          await tester.pumpAndSettle();
          _aligned(tester, 3);
          await tester.fling(_board, const Offset(70, 0), 1000);
          await tester.pumpAndSettle();
          _aligned(tester, 2);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
    'pill groups snap, all five columns are reachable, taps synchronize',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _mount(tester, width: 320, scale: 2, language: 'es');
      for (var i = 0; i < _names.length; i++) {
        _wholePills(tester);
        final target = find.byKey(Key('todo-tab-${_names[i]}'));
        if (target.hitTestable().evaluate().isEmpty) {
          await tester.fling(_tabs, const Offset(-90, 0), 1500);
          await tester.pumpAndSettle();
        }
        await tester.tap(target);
        await tester.pumpAndSettle();
        _aligned(tester, i);
      }
      await tester.timedDrag(
        _tabs,
        const Offset(30, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      _wholePills(tester);
      // Moving columns makes the active pill visible even from another group.
      await tester.fling(_board, const Offset(100, 0), 1500);
      await tester.pumpAndSettle();
      _aligned(tester, 3);
      _wholePills(tester);
      expect(
        find.byKey(const Key('todo-tab-ready')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tablet useful width accounts for rail and resize retains selection',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // 768px tablet minus the existing 76px navigation rail.
      await _mount(tester, width: 692);
      final viewport = tester.getRect(_board);
      final first = tester.getRect(
        find.byKey(const Key('todo-column-pending')),
      );
      final second = tester.getRect(
        find.byKey(const Key('todo-column-confirmed')),
      );
      expect(first.left, greaterThanOrEqualTo(viewport.left));
      expect(second.right, lessThanOrEqualTo(viewport.right));
      expect(first.width, second.width);
      final pills = [
        for (final name in _names)
          tester.getRect(find.byKey(Key('todo-tab-$name'))),
      ];
      final pillViewport = tester.getRect(_tabs);
      expect(pills.first.left, pillViewport.left);
      expect(pills.last.right, closeTo(pillViewport.right, .1));
      for (final rect in pills) {
        expect(rect.width, closeTo(pills.first.width, .1));
        expect(rect.center.dy, pills.first.center.dy);
      }
      expect(_controller(tester, _tabs).position.maxScrollExtent, 0);
      await tester.tap(find.byKey(const Key('todo-tab-confirmed')));
      await tester.pumpAndSettle();
      await _mount(tester, width: 320, scale: 2);
      _aligned(tester, 1);
      _wholePills(tester);
      await _mount(tester, width: 692);
      final selected = tester.widget<OutlinedButton>(
        find.byKey(const Key('todo-tab-confirmed')),
      );
      expect(
        selected.style!.side!.resolve({})!.color,
        PelinesColors.textPrimary,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rapid tab changes and resizing during animation stay synchronized',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _mount(tester, width: 320);
      tester
          .widget<OutlinedButton>(find.byKey(const Key('todo-tab-confirmed')))
          .onPressed!();
      await tester.pump(const Duration(milliseconds: 50));
      tester
          .widget<OutlinedButton>(find.byKey(const Key('todo-tab-ready')))
          .onPressed!();
      await tester.pumpAndSettle();
      _aligned(tester, 3);
      tester
          .widget<OutlinedButton>(find.byKey(const Key('todo-tab-pending')))
          .onPressed!();
      await tester.pump(const Duration(milliseconds: 50));
      await _mount(tester, width: 692);
      await _mount(tester, width: 390);
      _aligned(tester, 3);
      _wholePills(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
