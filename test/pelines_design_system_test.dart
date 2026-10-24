import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/app/theme/pelines_components.dart';
import 'package:pelines_admin_app/app/theme/pelines_order_badges.dart';
import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';

Widget app(Widget child, {double scale = 1}) => MaterialApp(
  theme: AppTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  for (final width in [320.0, 390.0, 768.0, 1400.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final hint in [
        'Search customer, event or order #',
        'Buscar cliente, evento o número de orden',
      ]) {
        testWidgets('outlined search long hint $width/$scale/$hint', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            app(
              Padding(
                padding: const EdgeInsets.all(16),
                child: PelinesInput(
                  variant: PelinesInputVariant.search,
                  hint: '$hint · $hint',
                ),
              ),
              scale: scale,
            ),
          );
          final field = tester.widget<TextField>(find.byType(TextField));
          final decoration = field.decoration!;
          final border = decoration.enabledBorder! as OutlineInputBorder;
          expect(
            border.borderSide,
            const BorderSide(color: PelinesColors.border, width: 1),
          );
          expect(
            border.borderRadius,
            BorderRadius.circular(PelinesRadius.pill),
          );
          expect(decoration.fillColor, PelinesColors.card);
          expect(decoration.hintStyle!.color, PelinesColors.textSecondary);
          expect(decoration.hintMaxLines, 1);
          expect(find.byIcon(Icons.search), findsOneWidget);
          expect(
            tester.getSize(find.byType(TextField)).height,
            greaterThanOrEqualTo(48),
          );
          expect(tester.getSize(find.byType(TextField)).width, width - 32);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  testWidgets(
    'search preserves focus, typing, clearing, disabled and error states',
    (tester) async {
      final controller = TextEditingController();
      final changes = <String>[];
      Widget search({bool enabled = true, String? error}) => app(
        PelinesInput(
          controller: controller,
          variant: PelinesInputVariant.search,
          hint: 'Search',
          enabled: enabled,
          error: error,
          onChanged: changes.add,
        ),
      );
      await tester.pumpWidget(search());
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(
        tester.widget<InputDecorator>(find.byType(InputDecorator)).isFocused,
        isTrue,
      );
      final focused =
          tester
                  .widget<TextField>(find.byType(TextField))
                  .decoration!
                  .focusedBorder!
              as OutlineInputBorder;
      expect(
        focused.borderSide,
        const BorderSide(color: PelinesColors.brandPrimary, width: 2),
      );
      await tester.enterText(find.byType(TextField), 'Tualatin');
      expect(changes, ['Tualatin']);
      expect(controller.text, 'Tualatin');
      await tester.enterText(find.byType(TextField), '');
      expect(changes, ['Tualatin', '']);
      await tester.pumpWidget(search(enabled: false));
      final disabled = tester.widget<TextField>(find.byType(TextField));
      expect(disabled.enabled, isFalse);
      expect(
        (disabled.decoration!.disabledBorder! as OutlineInputBorder).borderSide,
        const BorderSide(color: PelinesColors.border),
      );
      await tester.pumpWidget(search(error: 'Search unavailable'));
      final error = tester
          .widget<TextField>(find.byType(TextField))
          .decoration!;
      expect(error.errorText, 'Search unavailable');
      expect(
        (error.errorBorder! as OutlineInputBorder).borderSide.color,
        PelinesColors.destructive,
      );
      expect(
        (error.focusedErrorBorder! as OutlineInputBorder).borderSide.width,
        2,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets('card borders and shadows are explicit and KPI wraps', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        Column(
          children: [
            for (final variant in PelinesCardVariant.values)
              PelinesCard(variant: variant, child: Text(variant.name)),
            const PelinesKpiCard(
              label: 'Ventas del período seleccionado',
              value: r'$123,456.00',
              description: 'Comparación con el período anterior',
              icon: Icons.trending_up,
            ),
          ],
        ),
        scale: 2,
      ),
    );
    for (final variant in PelinesCardVariant.values) {
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.widgetWithText(PelinesCard, variant.name),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(18));
      expect(decoration.border, Border.all(color: PelinesColors.border));
      expect(
        decoration.boxShadow != null,
        variant == PelinesCardVariant.raised,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('select and pills expose working callbacks and selected state', (
    tester,
  ) async {
    var selection = 1;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              PelinesSelect<int>(
                value: selection,
                label: 'Type',
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Regular')),
                  DropdownMenuItem(value: 2, child: Text('Catering')),
                ],
                onChanged: (value) => setState(() => selection = value!),
              ),
              PelinesSegmentedControl<int>(
                value: selection,
                segments: const [
                  PelinesSegment(1, 'Day'),
                  PelinesSegment(2, 'Week'),
                ],
                onChanged: (value) => setState(() => selection = value),
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(DropdownButton<int>)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Catering').last);
    await tester.pumpAndSettle();
    expect(selection, 2);
    await tester.tap(find.text('Day'));
    await tester.pump();
    expect(selection, 1);
    final selected = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.selected == true,
    );
    expect(
      find.descendant(of: selected, matching: find.text('Day')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  test('web typography is explicit, responsive and preserves body family', () {
    final theme = AppTheme.light.textTheme;
    for (final (width, page, section) in [
      (320.0, 24.0, 18.0),
      (768.0, 30.0, 20.0),
      (1200.0, 36.0, 24.0),
    ]) {
      final title = PelinesTypography.pageTitle(theme, width: width)!;
      expect(title.fontFamily, 'Bree Serif');
      expect(title.fontWeight, FontWeight.w400);
      expect(title.fontSize, page);
      expect(
        PelinesTypography.sectionTitle(theme, width: width)!.fontSize,
        section,
      );
    }
    expect(theme.bodyMedium!.fontFamily, 'Work Sans');
    expect(PelinesRadius.pageCard, 18);
  });

  test('form, search, login and select decorations have distinct borders', () {
    for (final variant in PelinesInputVariant.values) {
      final style = PelinesControlStyles.input(variant: variant);
      final border = style.enabledBorder! as OutlineInputBorder;
      final pill =
          variant == PelinesInputVariant.search ||
          variant == PelinesInputVariant.login;
      expect(border.borderRadius, BorderRadius.circular(pill ? 999 : 8));
      expect(
        border.borderSide.style,
        variant == PelinesInputVariant.login
            ? BorderStyle.none
            : BorderStyle.solid,
      );
      expect(
        style.fillColor,
        variant == PelinesInputVariant.login
            ? PelinesColors.mutedSurface
            : PelinesColors.card,
      );
      expect(style.constraints!.minHeight, 48);
      expect((style.focusedBorder! as OutlineInputBorder).borderSide.width, 2);
      expect(
        (style.errorBorder! as OutlineInputBorder).borderSide.color,
        PelinesColors.destructive,
      );
    }
  });

  testWidgets('semantic buttons preserve actions, busy and disabled states', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      app(
        Column(
          children: [
            for (final variant in PelinesButtonVariant.values)
              PelinesButton(
                label: variant.name,
                variant: variant,
                onPressed: () => taps++,
              ),
            PelinesButton(label: 'Saving', busy: true, onPressed: () => taps++),
            const PelinesButton(label: 'Disabled', onPressed: null),
          ],
        ),
      ),
    );
    for (final variant in PelinesButtonVariant.values) {
      final finder = find.widgetWithText(FilledButton, variant.name);
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
      final style = tester.widget<FilledButton>(finder).style!;
      final expected = switch (variant) {
        PelinesButtonVariant.accept => PelinesColors.successForeground,
        PelinesButtonVariant.preparing => PelinesColors.preparing,
        PelinesButtonVariant.complete => PelinesColors.blue,
        PelinesButtonVariant.secondary ||
        PelinesButtonVariant.cancel => PelinesColors.card,
        _ => PelinesColors.brandPrimary,
      };
      expect(style.backgroundColor!.resolve({}), expected);
      await tester.tap(finder);
    }
    expect(taps, PelinesButtonVariant.values.length);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Disabled'))
          .onPressed,
      isNull,
    );
    expect(find.text('Saving'), findsOneWidget);
  });

  testWidgets('badges retain every Flutter enum and caller supplied labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Wrap(
          children: [
            for (final status in OrderStatus.values)
              PelinesOrderBadges.status(status: status, label: status.name),
            for (final type in OrderType.values)
              PelinesOrderBadges.type(type: type, label: 'type ${type.name}'),
            for (final value in FulfillmentType.values)
              PelinesOrderBadges.fulfillment(
                fulfillment: value,
                label: 'fulfillment ${value.name}',
              ),
            for (final payment in PaymentStatus.values)
              PelinesOrderBadges.payment(
                payment: payment,
                label: 'payment ${payment.name}',
              ),
          ],
        ),
      ),
    );
    for (final status in OrderStatus.values) {
      expect(find.text(status.name), findsOneWidget);
      final badge = tester.widget<PelinesStateBadge>(
        find.widgetWithText(PelinesStateBadge, status.name),
      );
      expect(badge.dot, isTrue);
    }
    expect(find.text('TYPE CATERING'), findsOneWidget);
    expect(find.text('fulfillment delivery'), findsOneWidget);
    expect(find.text('payment refunded'), findsOneWidget);
    expect(find.text('payment unknown'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (width, scale) in [
    (320.0, 1.0),
    (320.0, 2.0),
    (768.0, 1.0),
    (768.0, 2.0),
    (1180.0, 1.0),
    (1440.0, 2.0),
  ]) {
    testWidgets('primitives fit phone/tablet/wide at $width x $scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        app(
          PelinesPageBody(
            width: PelinesPageWidth.dashboard,
            responsivePadding: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PelinesPageHeader(
                  title: 'Configuración de la ubicación seleccionada',
                  subtitle:
                      'Información y acciones disponibles para esta ubicación.',
                  location: const Text('Troutdale — Dirección de la ubicación'),
                  actions: [
                    PelinesButton(
                      label: 'Actualizar información',
                      onPressed: () {},
                    ),
                  ],
                ),
                const PelinesSectionHeading('Preferencias de servicio'),
                PelinesFilterBar(
                  search: const PelinesInput(
                    variant: PelinesInputVariant.search,
                    hint: 'Buscar pedidos',
                  ),
                  filters: [
                    PelinesSelect<int>(
                      value: 1,
                      label: 'Tipo de pedido',
                      items: const [
                        DropdownMenuItem(
                          value: 1,
                          child: Text('Todos los tipos de pedido'),
                        ),
                      ],
                      onChanged: (_) {},
                    ),
                  ],
                ),
                PelinesSegmentedControl(
                  value: 1,
                  segments: const [
                    PelinesSegment(1, 'Esperando aprobación'),
                    PelinesSegment(2, 'Confirmados'),
                  ],
                  onChanged: (_) {},
                ),
                PelinesCard(
                  child: Column(
                    children: [
                      const PelinesInput(label: 'Nombre del formulario'),
                      PelinesOrderBadges.status(
                        status: OrderStatus.pending,
                        label: 'Esperando aprobación del restaurante',
                      ),
                      PelinesButton(
                        label: 'Confirmar los cambios seleccionados',
                        variant: PelinesButtonVariant.accept,
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          scale: scale,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final headerText = tester.widget<Text>(
        find.text('Configuración de la ubicación seleccionada'),
      );
      expect(headerText.style!.fontFamily, 'Bree Serif');
    });
  }

  testWidgets('filter order and wrapping follow available width', (
    tester,
  ) async {
    for (final width in [320.0, 1200.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        app(
          PelinesFilterBar(
            search: const PelinesInput(key: Key('search')),
            filters: [
              PelinesButton(
                key: const Key('filter'),
                label: 'Type',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      final search = tester.getTopLeft(find.byKey(const Key('search')));
      final filter = tester.getTopLeft(find.byKey(const Key('filter')));
      if (width < 1024) {
        expect(filter.dy, greaterThan(search.dy));
      } else {
        expect(filter.dx, greaterThan(search.dx));
      }
      expect(tester.takeException(), isNull);
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('search-only filter fills its surface on wide screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        const PelinesFilterBar(search: PelinesInput(key: Key('only-search'))),
      ),
    );
    // 16 px padding plus 1 px border on each side, with no empty filter column.
    expect(tester.getSize(find.byKey(const Key('only-search'))).width, 1166);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page widths and optional padding do not accumulate', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final variant in PelinesPageWidth.values) {
      await tester.pumpWidget(
        app(
          PelinesPageBody(
            width: variant,
            child: const SizedBox(
              key: Key('content'),
              width: double.infinity,
              height: 20,
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const Key('content'))).width,
        variant == PelinesPageWidth.dashboard ? 1400 : 760,
      );
    }
    for (final width in [320.0, 768.0, 1200.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        app(
          const PelinesPageBody(
            width: PelinesPageWidth.dashboard,
            responsivePadding: true,
            child: SizedBox(
              key: Key('content'),
              width: double.infinity,
              height: 20,
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('content'))).dx,
        PelinesLayout.pagePadding(width),
      );
    }
  });

  testWidgets('table switches to cards for narrow width and enlarged text', (
    tester,
  ) async {
    var views = 0;
    for (final (width, scale, table) in [
      (320.0, 1.0, false),
      (768.0, 2.0, false),
      (1200.0, 1.0, true),
    ]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        app(
          PelinesAdaptiveTable<int>(
            rows: const [1],
            columns: [
              PelinesTableColumn(label: 'Order', cell: (row) => Text('#$row')),
              PelinesTableColumn(
                label: 'Total',
                numeric: true,
                cell: (_) => const Text(r'$125.00'),
              ),
              PelinesTableColumn(
                label: 'Actions',
                cell: (_) => PelinesViewAction(
                  label: 'View order',
                  onPressed: () => views++,
                ),
              ),
            ],
            cardBuilder: (_, row) => PelinesCard(
              child: Column(
                children: [
                  Text('#$row'),
                  PelinesViewAction(
                    label: 'View order',
                    onPressed: () => views++,
                  ),
                ],
              ),
            ),
            empty: const Text('No orders'),
          ),
          scale: scale,
        ),
      );
      expect(find.byType(DataTable), table ? findsOneWidget : findsNothing);
      if (table) {
        expect(
          tester.widget<DataTable>(find.byType(DataTable)).columns[1].numeric,
          isTrue,
        );
      }
      expect(
        tester.getSize(find.byType(IconButton)).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.byTooltip('View order'));
      expect(tester.takeException(), isNull);
    }
    expect(views, 3);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
