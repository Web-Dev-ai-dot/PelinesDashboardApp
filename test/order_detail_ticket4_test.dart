import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';
import 'package:pelines_admin_app/core/time/pelines_time.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_detail_screen.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_ui_helpers.dart';
import 'package:pelines_admin_app/app/l10n/catalog.dart';
import 'package:pelines_admin_app/features/orders/models/pickup_order_notes.dart';

import 'order_test_data.dart';

final _location = Location(
  id: 'location-id',
  name: 'Troutdale',
  slug: 'troutdale',
  isActive: true,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  isAcceptingOrders: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _Current extends CurrentLocationController {
  @override
  Future<Location?> build() async => _location;
}

class _Repo implements OrdersRepository {
  _Repo(this.json);
  final Map<String, dynamic> json;
  int writes = 0;
  @override
  Future<OrderDetail> getOrderById(String id) async =>
      OrderDetail.fromJson(json);
  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async => [];
  @override
  Future<OrderDetail> updateInternalNotes({
    required String orderId,
    required String internalNotes,
  }) async {
    writes++;
    json['internalNotes'] = internalNotes;
    return OrderDetail.fromJson(json);
  }

  @override
  Future<OrderDetail> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  }) async {
    writes++;
    json['status'] = status.name;
    return OrderDetail.fromJson(json);
  }
}

Map<String, dynamic> _data({
  String payment = 'paid',
  String status = 'confirmed',
  String fulfillment = 'pickup',
}) => {
  ...orderJson(payment: payment, status: status, fulfillment: fulfillment),
  'location': {'name': 'Troutdale', 'address': '123 Real Street'},
  'scheduledFor': '2026-09-05T02:30:00Z',
  'eventDetails': {'eventName': 'Birthday', 'attendees': 25},
  'deliveryAddress': {
    'line1': '42 Main St',
    'line2': 'Suite 9',
    'city': 'Portland',
    'state': 'OR',
    'zip': '97000',
  },
  'notes': 'Include forks: no\nKeep this customer note intact.',
  'internalNotes': 'Call the kitchen',
  'cardBrand': 'visa',
  'cardLast4': '4242',
  'subtotalCents': 4321,
  'serviceFeeCents': 234,
  'tipCents': 345,
  'discountCents': 123,
  'discountCode': 'SAVE',
  'deliveryFeeCents': 456,
  'taxCents': 567,
  'totalCents': 5800,
  'items': [
    {
      'id': 'item',
      'productName': 'Tacos',
      'unitPriceCents': 999,
      'quantity': 3,
      'lineTotalCents': 4321,
      'notes': 'No onions',
      'modifiers': [
        {
          'id': 'mod',
          'groupName': 'Extra',
          'optionName': 'Cheese',
          'priceDeltaCents': 111,
        },
      ],
    },
  ],
};

Future<void> _mount(
  WidgetTester tester,
  _Repo repo, {
  double width = 390,
  double scale = 1,
  String language = 'en',
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ordersRepositoryProvider.overrideWithValue(repo),
        currentLocationProvider.overrideWith(_Current.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: Locale(language),
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
        home: OrderDetailScreen(orderId: repo.json['id'] as String),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
  for (final language in ['en', 'es']) {
    for (final size in [
      (390.0, 1.0),
      (768.0, 1.0),
      (1400.0, 1.0),
      (320.0, 2.0),
    ]) {
      testWidgets('6B compact hierarchy/payment $language/$size', (
        tester,
      ) async {
        final data = _data()
          ..['source'] = 'web'
          ..['notes'] =
              'Included items (forks, napkins, etc.): yes\nCustomer note intact'
          ..['location'] = {
            'name': 'Tualatin',
            'address': '7670 SW Nyberg St, Tualatin, OR 97062',
          };
        final repo = _Repo(data);
        await _mount(
          tester,
          repo,
          width: size.$1,
          scale: size.$2,
          language: language,
        );
        expect(find.text('Tualatin · 7670 SW Nyberg St'), findsNWidgets(2));
        final instructions = find.byKey(
          const Key('detail-pickup-instructions'),
        );
        final utensils = find.byKey(const Key('detail-pickup-utensils'));
        await tester.ensureVisible(instructions);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(utensils).top,
          greaterThanOrEqualTo(tester.getRect(instructions).bottom),
        );
        final box =
            tester.widget<Container>(instructions).decoration! as BoxDecoration;
        expect((box.border! as Border).left.color, PelinesColors.brandPrimary);
        final section = find.byKey(const Key('detail-items-totals'));
        final payment = find.byKey(const Key('detail-payment'));
        expect(
          find.descendant(
            of: payment,
            matching: find.text(language == 'es' ? 'Pago' : 'Payment'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: payment,
            matching: find.text(language == 'es' ? 'Pagado' : 'Paid'),
          ),
          findsNothing,
        );
        final printButton = find.byKey(Key('todo-print-${repo.json['id']}'));
        final header = find.byKey(const Key('detail-header-card'));
        expect(
          tester.getRect(printButton).left,
          closeTo(tester.getRect(header).left, 1),
        );
        expect(
          tester.getRect(printButton).width,
          closeTo(tester.getRect(header).width, 1),
        );
        expect(
          tester.getRect(printButton).top,
          greaterThan(tester.getRect(header).bottom),
        );
        expect(
          tester.getRect(printButton).bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byKey(const Key('detail-progress'))).top,
          ),
        );
        expect(
          find.descendant(of: header, matching: printButton),
          findsNothing,
        );
        expect(
          find.descendant(
            of: header,
            matching: find.byKey(const Key('detail-back')),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: header,
            matching: find.byIcon(Icons.calendar_today_outlined),
          ),
          findsOneWidget,
        );
        final headerText = tester
            .widgetList<Text>(
              find.descendant(of: header, matching: find.byType(Text)),
            )
            .map((t) => t.data ?? '')
            .join(' ');
        expect(
          headerText.toUpperCase(),
          isNot(contains(language == 'es' ? 'ORIGEN' : 'ORIGIN')),
        );
        expect(
          headerText,
          isNot(contains(language == 'es' ? 'Realizada:' : 'Placed:')),
        );
        final calendar = find.descendant(
          of: header,
          matching: find.byIcon(Icons.calendar_today_outlined),
        );
        final locationIcon = find.descendant(
          of: header,
          matching: find.byIcon(Icons.location_on_outlined),
        );
        expect(tester.widget<Icon>(calendar).size, 20);
        expect(tester.widget<Icon>(locationIcon).size, 20);
        expect(tester.widget<Icon>(calendar).color, PelinesColors.textPrimary);
        expect(
          tester.widget<Icon>(locationIcon).color,
          PelinesColors.textPrimary,
        );
        expect(
          tester.getRect(calendar).left,
          tester.getRect(locationIcon).left,
        );
        final dateText = find.text(
          PelinesTime.formatDateTime(
            DateTime.parse(data['createdAt'] as String),
          ),
        );
        final locationText = find.descendant(
          of: header,
          matching: find.text('Tualatin · 7670 SW Nyberg St'),
        );
        expect(
          tester.getRect(dateText).left,
          tester.getRect(locationText).left,
        );
        expect(
          tester.getRect(locationIcon).top - tester.getRect(dateText).bottom,
          closeTo(14, 1),
        );
        expect(
          headerText,
          isNot(
            contains(language == 'es' ? 'Hora del Pacífico' : 'Pacific time'),
          ),
        );
        final theme = OutlinedButtonTheme.of(tester.element(printButton))
            .style!;
        expect(theme.backgroundColor!.resolve({}), PelinesColors.card);
        expect(
          theme.backgroundColor!.resolve({WidgetState.disabled}),
          PelinesColors.card,
        );
        expect(
          theme.side!.resolve({}),
          const BorderSide(color: PelinesColors.border),
        );
        expect(
          theme.side!.resolve({WidgetState.disabled}),
          const BorderSide(color: PelinesColors.border),
        );
        expect(theme.foregroundColor!.resolve({}), PelinesColors.textPrimary);
        expect(theme.shape!.resolve({}), isA<StadiumBorder>());
        if (size.$2 == 1) {
          expect(
            tester.getSize(printButton).width,
            closeTo(tester.getRect(header).width, 1),
          );
        }
        expect(find.descendant(of: section, matching: payment), findsOneWidget);
        expect(
          find.descendant(
            of: section,
            matching: find.byKey(const Key('detail-paid-card')),
          ),
          findsOneWidget,
        );
        final total = find.text(language == 'es' ? 'TOTAL' : 'TOTAL');
        await tester.ensureVisible(total);
        await tester.pumpAndSettle();
        final amount = find.text(r'$58.00');
        if (size.$2 == 1) {
          expect(
            tester.getRect(total).center.dy,
            closeTo(tester.getRect(amount).center.dy, 4),
          );
          expect(
            tester.getRect(total).right,
            lessThan(tester.getRect(amount).left),
          );
        }
        expect(
          tester.getRect(payment).top,
          greaterThan(tester.getRect(total).top),
        );
        expect(find.text('Customer note intact'), findsOneWidget);
        expect(find.textContaining('Extra: Cheese'), findsOneWidget);
        expect(repo.writes, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final fields in [
    <String, dynamic>{'cardBrand': null},
    <String, dynamic>{'cardLast4': null},
    <String, dynamic>{'cardBrand': '', 'cardLast4': ''},
  ]) {
    testWidgets('6B incomplete card data uses actual payment status $fields', (
      tester,
    ) async {
      final repo = _Repo(_data()..addAll(fields));
      await _mount(tester, repo);
      expect(find.byKey(const Key('detail-paid-card')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('detail-payment')),
          matching: find.text('Paid'),
        ),
        findsOneWidget,
      );
      expect(repo.writes, 0);
    });
  }
  for (final language in ['en', 'es']) {
    for (final width in [390.0, 800.0]) {
      for (final name in <String?>['Tualatin', 'Troutdale', null]) {
        testWidgets(
          'generated instructions $name $language $width 2x remain separate from notes',
          (tester) async {
            final json = _data()
              ..['source'] = 'web'
              ..['location'] = {'name': name, 'address': 'Real address'}
              ..['notes'] =
                  'Included items (forks, napkins, etc.): yes\nMy own pickup comment';
            await _mount(
              tester,
              _Repo(json),
              language: language,
              width: width,
              scale: 2,
            );
            final instructions = find.byKey(
              const Key('detail-pickup-instructions'),
            );
            final location = name ?? 'Pelines';
            final expected = language == 'en'
                ? '“Arrive at $location at your pickup time, head to the front counter, and let the team know you are picking up an online order.”'
                : '“Llega a $location a la hora de recogida, dirígete al mostrador e informa al equipo de que vienes a recoger un pedido en línea.”';
            expect(
              find.descendant(of: instructions, matching: find.text(expected)),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: instructions,
                matching: find.byType(TextField),
              ),
              findsNothing,
            );
            final customerNotes = find.byKey(
              const Key('detail-customer-notes'),
            );
            expect(
              find.descendant(
                of: customerNotes,
                matching: find.text('My own pickup comment'),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(of: customerNotes, matching: find.text(expected)),
              findsNothing,
            );
            expect(
              find.descendant(
                of: customerNotes,
                matching: find.textContaining('No onions'),
              ),
              findsNothing,
            );
            expect(
              find.descendant(
                of: find.byKey(const Key('detail-items-totals')),
                matching: find.textContaining('No onions'),
              ),
              findsOneWidget,
            );
            await tester.ensureVisible(instructions);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
    testWidgets(
      'unknown utensils has no false No and empty customer notes $language',
      (tester) async {
        await _mount(
          tester,
          _Repo(_data()..['notes'] = null),
          language: language,
        );
        expect(find.byKey(const Key('detail-pickup-utensils')), findsNothing);
        expect(find.byKey(const Key('detail-customer-notes')), findsOneWidget);
        expect(
          find.text(
            language == 'en' ? 'No customer notes' : 'Sin notas del cliente',
          ),
          findsOneWidget,
        );
      },
    );
  }
  const prefix = 'Included items (forks, napkins, etc.): ';
  for (final value in ['yes', 'no']) {
    test(
      'exact checkout $value line splits once without losing customer text',
      () {
        const customer =
            '  Free text\nIncluded items (forks, napkins, etc.): no\n';
        final json = _data()
          ..['source'] = 'web'
          ..['notes'] = '$prefix$value\n$customer';
        final order = OrderDetail.fromJson(json);
        final result = PickupOrderNotes.fromOrder(order);
        expect(result.includeUtensils, value == 'yes');
        expect(result.customerNotes, customer);
        expect(order.notes, '$prefix$value\n$customer');
        expect(order.items.single.notes, 'No onions');
      },
    );
    for (final language in ['en', 'es']) {
      testWidgets(
        'real checkout utensils $value $language displayed once, phone 2x',
        (tester) async {
          final json = _data()
            ..['source'] = 'web'
            ..['notes'] = '$prefix$value\nCustomer instructions intact';
          await _mount(tester, _Repo(json), language: language, scale: 2);
          final field = find.byKey(const Key('detail-pickup-utensils'));
          expect(field, findsOneWidget);
          expect(
            find.descendant(
              of: field,
              matching: find.text(
                value == 'yes'
                    ? language == 'es'
                          ? 'Sí'
                          : 'Yes'
                    : 'No',
              ),
            ),
            findsOneWidget,
          );
          expect(find.text('Customer instructions intact'), findsOneWidget);
          expect(find.textContaining(prefix), findsNothing);
          expect(
            find.byKey(const Key('detail-pickup-instructions')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: field, matching: find.byType(CircleAvatar)),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final notes in <String?>[
    null,
    '',
    'forks yes',
    '${prefix}Yes',
    ' $prefix'
        'yes',
    '${prefix}yes please',
    'Customer note\n${prefix}yes',
    '${prefix}yes\r\nText',
  ]) {
    test('unknown notes format preserved verbatim: $notes', () {
      final order = OrderDetail.fromJson(
        _data()
          ..['source'] = 'web'
          ..['notes'] = notes,
      );
      final result = PickupOrderNotes.fromOrder(order);
      expect(result.includeUtensils, isNull);
      expect(result.customerNotes, notes);
    });
  }
  for (final override in <Map<String, dynamic>>[
    {'source': null},
    {'source': 'android'},
    {'source': 'ios'},
    {'orderType': 'catering'},
    {'fulfillmentType': 'delivery'},
  ]) {
    test('unsupported origin/type/fulfillment preserves notes $override', () {
      final order = OrderDetail.fromJson({
        ..._data(),
        'source': 'web',
        'notes': '${prefix}yes',
        ...override,
      });
      final result = PickupOrderNotes.fromOrder(order);
      expect(result.includeUtensils, isNull);
      expect(result.customerNotes, '${prefix}yes');
    });
  }
  testWidgets('utensils-only note leaves a discreet independent empty state', (
    tester,
  ) async {
    await _mount(
      tester,
      _Repo(
        _data()
          ..['source'] = 'web'
          ..['notes'] = '${prefix}no',
      ),
    );
    expect(find.byKey(const Key('detail-pickup-utensils')), findsOneWidget);
    expect(find.byKey(const Key('detail-customer-notes')), findsOneWidget);
    expect(find.text('No customer notes'), findsOneWidget);
    expect(find.textContaining(prefix), findsNothing);
  });
  for (final language in ['en', 'es']) {
    for (final status in [
      'pending',
      'confirmed',
      'preparing',
      'ready',
      'delivered',
      'cancelled',
    ]) {
      testWidgets(
        'single header/status $status $language, phone 2x with context badges',
        (tester) async {
          final json = _data(status: status);
          if (status == 'delivered') {
            json['fulfillmentType'] = 'delivery';
            json['orderType'] = 'catering';
          }
          await _mount(tester, _Repo(json), scale: 2, language: language);
          String localized(String text) =>
              language == 'es' ? spanishCatalog[text] ?? text : text;
          expect(find.byType(AppBar), findsNothing);
          expect(find.byType(BackButton), findsNothing);
          expect(find.byIcon(Icons.arrow_back), findsOneWidget);
          expect(find.text(localized('Back to orders')), findsOneWidget);
          expect(find.text('ORD-1048'), findsOneWidget);
          final order = OrderDetail.fromJson(json);
          final statusText = localized(
            statusLabel(order.status, order.fulfillmentType, order.rawStatus),
          );
          expect(find.text(statusText), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(const Key('detail-progress')),
              matching: find.text(statusText),
            ),
            findsOneWidget,
          );
          expect(
            find.text(localized(fulfillmentLabel(order.fulfillmentType))),
            findsOneWidget,
          );
          expect(
            find.text(localized(orderTypeLabel(order.orderType)).toUpperCase()),
            findsOneWidget,
          );
          expect(find.text(json['notes'] as String), findsOneWidget);
          expect(
            find.byKey(const Key('detail-pickup-instructions')),
            order.fulfillmentType == FulfillmentType.pickup
                ? findsOneWidget
                : findsNothing,
          );
          expect(find.textContaining('INCLUDE FORKS, NAPKINS'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final language in ['en', 'es']) {
    for (final size in [(390.0, 1.0), (1440.0, 1.0), (320.0, 2.0)]) {
      testWidgets('polished header and progress layout $language/$size', (
        tester,
      ) async {
        final repo = _Repo(
          _data()..['orderNumber'] = 'TUA-2026-ORDER-12345678901234567890',
        );
        await _mount(
          tester,
          repo,
          width: size.$1,
          scale: size.$2,
          language: language,
        );
        final header = find.byKey(const Key('detail-header-card'));
        final number = find.byKey(const Key('detail-order-number'));
        expect(tester.widget<Text>(number).style!.fontSize, 40);
        expect(
          tester.getRect(number).left,
          greaterThanOrEqualTo(tester.getRect(header).left),
        );
        expect(
          tester.getRect(number).right,
          lessThanOrEqualTo(tester.getRect(header).right),
        );
        final progress = find.byKey(const Key('detail-progress'));
        await tester.ensureVisible(progress);
        await tester.pumpAndSettle();
        final title = find.descendant(
          of: progress,
          matching: find.text(
            language == 'es'
                ? spanishCatalog['Update Progress']!
                : 'Update Progress',
          ),
        );
        final badge = find.byKey(const Key('detail-progress-status'));
        expect(
          find.descendant(
            of: badge,
            matching: find.text(
              language == 'es' ? spanishCatalog['Confirmed']! : 'Confirmed',
            ),
          ),
          findsOneWidget,
        );
        if (size.$2 == 1) {
          expect(
            tester.getRect(title).center.dy,
            closeTo(tester.getRect(badge).center.dy, 1),
          );
          expect(
            tester.getRect(title).right,
            lessThan(tester.getRect(badge).left),
          );
        }
        final action = find.byKey(const Key('order-primary-action'));
        expect(action, findsOneWidget);
        expect(
          tester.getRect(action).top,
          greaterThan(tester.getRect(badge).bottom),
        );
        expect(
          find.byKey(Key('todo-print-${repo.json['id']}')),
          findsOneWidget,
        );
        expect(repo.writes, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final scenario in [
    ('pending', 'pickup', PelinesButtonVariant.accept, 'Accept order'),
    ('confirmed', 'pickup', PelinesButtonVariant.preparing, 'Start preparing'),
    ('preparing', 'pickup', PelinesButtonVariant.ready, 'Mark ready'),
    ('ready', 'pickup', PelinesButtonVariant.complete, 'Mark picked up'),
    ('ready', 'delivery', PelinesButtonVariant.complete, 'Mark delivered'),
  ]) {
    testWidgets(
      'progress uses To Do destination color and keeps action ${scenario.$1}/${scenario.$2}',
      (tester) async {
        final repo = _Repo(
          _data(status: scenario.$1, fulfillment: scenario.$2),
        );
        await _mount(tester, repo);
        final action = find.byKey(const Key('order-primary-action'));
        final button = tester.widget<FilledButton>(action);
        final sharedStyle = PelinesControlStyles.button(scenario.$3);
        expect(
          button.style!.backgroundColor!.resolve({}),
          sharedStyle.backgroundColor!.resolve({}),
        );
        expect(
          button.style!.foregroundColor!.resolve({}),
          sharedStyle.foregroundColor!.resolve({}),
        );
        expect(
          find.descendant(of: action, matching: find.text(scenario.$4)),
          findsOneWidget,
        );
        expect(button.onPressed, isNotNull);
        expect(repo.writes, 0);
      },
    );
  }
  for (final scenario in [
    ('delivered', 'pickup', 'paid'),
    ('cancelled', 'delivery', 'paid'),
    ('ready', 'unknown', 'paid'),
    ('confirmed', 'pickup', 'unpaid'),
  ]) {
    testWidgets('no forbidden progress action for $scenario', (tester) async {
      final repo = _Repo(
        _data(
          status: scenario.$1,
          fulfillment: scenario.$2,
          payment: scenario.$3,
        ),
      );
      await _mount(tester, repo);
      expect(find.byKey(const Key('order-primary-action')), findsNothing);
      expect(find.byKey(const Key('detail-progress-status')), findsOneWidget);
      expect(repo.writes, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'header, Pacific dates, canonical items/totals and intact notes',
    (tester) async {
      final repo = _Repo(_data());
      await _mount(tester, repo);
      expect(find.byKey(const Key('detail-order-number')), findsOneWidget);
      expect(
        find.textContaining(
          PelinesTime.formatDateTime(
            DateTime.parse(repo.json['createdAt'] as String),
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Troutdale · 123 Real Street'), findsNWidgets(2));
      expect(find.text('Customer'), findsNWidgets(2));
      expect(find.text('customer@example.test'), findsOneWidget);
      expect(find.text('555-0100'), findsOneWidget);
      expect(find.text('PICKUP TIME'), findsOneWidget);
      expect(find.textContaining('7:30'), findsOneWidget);
      expect(find.text('3× Tacos'), findsOneWidget);
      expect(find.textContaining('Extra: Cheese'), findsOneWidget);
      expect(find.text('Note: No onions'), findsOneWidget);
      for (final amount in [
        r'$43.21',
        r'$2.34',
        r'$3.45',
        r'-$1.23',
        r'$4.56',
        r'$5.67',
        r'$58.00',
      ]) {
        expect(find.text(amount), findsWidgets);
      }
      expect(
        find.text(r'$29.97'),
        findsNothing,
      ); // Do not recompute line totals.
      expect(find.text(repo.json['notes'] as String), findsOneWidget);
      expect(find.text('Paid with visa ending in 4242'), findsOneWidget);
      expect(find.textContaining('Include forks/napkins'), findsNothing);
      expect(repo.writes, 0);
    },
  );

  testWidgets(
    'Copy phone uses clipboard with accessible feedback, without mutation',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final repo = _Repo(_data());
      await _mount(tester, repo);
      final button = find.byKey(const Key('copy-order-phone'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(copied, '555-0100');
      expect(find.text('Phone copied'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Phone copied'),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsWidgets,
      );
      expect(repo.writes, 0);
    },
  );

  testWidgets('refunded active order never says Paid with but can Print', (
    tester,
  ) async {
    final repo = _Repo(_data(payment: 'refunded'));
    await _mount(tester, repo);
    expect(find.byKey(const Key('detail-paid-card')), findsNothing);
    expect(find.text('Payment not completed'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(Key('todo-print-${repo.json['id']}')),
          )
          .onPressed,
      isNotNull,
    );
  });
  for (final payment in ['unpaid', 'failed']) {
    testWidgets('$payment never says Paid with or enables Print', (
      tester,
    ) async {
      final repo = _Repo(_data(payment: payment));
      await _mount(tester, repo);
      expect(find.byKey(const Key('detail-paid-card')), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(Key('todo-print-${repo.json['id']}')),
            )
            .onPressed,
        isNull,
      );
    });
  }
  for (final status in [
    'pending',
    'confirmed',
    'preparing',
    'ready',
    'delivered',
    'cancelled',
  ]) {
    testWidgets('Print eligibility for $status', (tester) async {
      final repo = _Repo(_data(status: status));
      await _mount(tester, repo);
      final enabled =
          tester
              .widget<OutlinedButton>(
                find.byKey(Key('todo-print-${repo.json['id']}')),
              )
              .onPressed !=
          null;
      expect(enabled, ['confirmed', 'preparing', 'ready'].contains(status));
      expect(find.text('Change status'), findsNothing);
      expect(repo.writes, 0);
    });
  }

  for (final width in [390.0, 800.0, 1440.0]) {
    for (final language in ['en', 'es']) {
      testWidgets(
        '$language delivery/catering long content at $width, text scale 2',
        (tester) async {
          final json = _data(fulfillment: 'delivery')
            ..['orderType'] = 'catering'
            ..['contactName'] = 'Long customer name ' * 12
            ..['notes'] = 'Unmodified customer notes\n' * 30;
          await _mount(
            tester,
            _Repo(json),
            width: width,
            scale: 2,
            language: language,
          );
          expect(
            find.text(
              language == 'es' ? 'Detalles de entrega' : 'Delivery Details',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('42 Main St, Suite 9'), findsOneWidget);
          expect(find.text('25'), findsOneWidget);
          expect(find.text('Birthday'), findsWidgets);
          expect(find.text('Pickup Details'), findsNothing);
          expect(
            find.text(language == 'es' ? 'Copiar teléfono' : 'Copy phone'),
            findsOneWidget,
          );
          expect(
            find.text(
              language == 'es'
                  ? 'Cargo de servicio de Pelines'
                  : 'Pelines Service Fee',
            ),
            findsOneWidget,
          );
          await tester.ensureVisible(
            find.byKey(const Key('save-internal-notes')),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(language == 'es' ? 'Guardar nota' : 'Save Note'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'missing optional data uses ASAP without fabricated event or card',
    (tester) async {
      final json = _data()
        ..['scheduledFor'] = null
        ..['eventDetails'] = null
        ..['cardLast4'] = null;
      await _mount(tester, _Repo(json));
      expect(find.text('ASAP'), findsOneWidget);
      expect(find.text('ATTENDEES'), findsNothing);
      expect(find.byKey(const Key('detail-paid-card')), findsNothing);
    },
  );
}
