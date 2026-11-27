import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/printing/application/esc_pos_ticket_renderer.dart';
import 'package:pelines_admin_app/features/printing/application/ticket_builder.dart';

import 'order_test_data.dart';

typedef _Line = ({String text, int size, bool bold, bool center});

/// Read emitted text with its actual printer state, skipping the raster payload.
List<_Line> _lines(List<int> bytes) {
  final lines = <_Line>[];
  final text = <int>[];
  var size = 0;
  var bold = false;
  var center = false;
  for (var i = 0; i < bytes.length;) {
    final byte = bytes[i];
    switch ((byte, bytes[i + 1 < bytes.length ? i + 1 : i])) {
      case (29, 118):
        final width = bytes[i + 4] + 256 * bytes[i + 5];
        final height = bytes[i + 6] + 256 * bytes[i + 7];
        expect(width, greaterThan(0));
        expect(height, greaterThan(0));
        expect(
          bytes.skip(i + 8).take(width * height).any((b) => b != 0),
          isTrue,
        );
        expect(center, isTrue);
        i += 8 + width * height;
      case (29, 33):
        size = bytes[i + 2];
        i += 3;
      case (27, 97):
        center = bytes[i + 2] == 1;
        i += 3;
      case (27, 69):
        bold = bytes[i + 2] == 1;
        i += 3;
      case (27, 64) || (28, 46):
        i += 2;
      case (28, 40):
        i += 7;
      case (29, 86):
        expect((size, bold, center), (0, false, false));
        i += 4;
      case (27, _):
        i += 3;
      case (10, _):
        lines.add((
          text: latin1.decode(text),
          size: size,
          bold: bold,
          center: center,
        ));
        text.clear();
        i++;
      default:
        text.add(byte);
        i++;
    }
  }
  expect(text, isEmpty);
  return lines;
}

void main() {
  const builder = TicketBuilder();
  test('Test Print totals already include the modifier adjustment', () {
    final ticket = builder.buildTest(
      id: 'test-fixture',
      placedAt: DateTime.utc(2026, 11, 26),
      printerLabel: 'Epson TM-m30II',
      simulated: false,
    );
    final first = ticket.items.first;
    expect(
      first.lineTotalCents,
      first.quantity *
          (first.baseUnitPriceCents +
              first.modifiers.single.priceAdjustmentCents),
    );
    final totals = ticket.totals;
    expect(
      ticket.items.map((item) => item.lineTotalCents).reduce((a, b) => a + b),
      totals.subtotalCents,
    );
    expect(
      [
        totals.subtotalCents,
        totals.serviceFeeCents,
        totals.tipCents,
        totals.discountCents,
        totals.totalCents,
      ],
      [1420, 50, 150, 200, 1420],
    );
    expect(
      totals.subtotalCents +
          totals.serviceFeeCents +
          totals.tipCents -
          totals.discountCents,
      totals.totalCents,
    );
    expect(totals.amountPaidCents, totals.totalCents);
  });
  List<_Line> render(Map<String, dynamic> json, EscPosPaperProfile profile) =>
      _lines(
        EscPosTicketRenderer(profile: profile)
            .render(builder.build(OrderDetail.fromJson(json))),
      );
  for (final profile in EscPosPaperProfile.values) {
    test(
      'pickup and paid layout preserve wrapped content in ${profile.columns} columns',
      () {
        const customer = 'MaríaAlejandraFernándezDelRíoIninterrumpido';
        const number = 'FICTICIO-ORDEN-IDENTIFICADOR-MUY-LARGO-4021';
        const product = 'TortillaDeChampiñónConVerdurasExtraGrande';
        final lines = render(
          orderJson()..addAll({
            'orderNumber': number,
            'contactName': customer,
            'location': {'name': 'Sucursal Ficticia'},
            'notes': 'Incluir cubiertos.',
            'discountCode': 'PRUEBA-LARGA-DE-DESCUENTO-2026',
            'discountCents': 100,
            'taxCents': 0,
            'cardBrand': 'Visa',
            'cardLast4': '1234',
            'items': [
              {
                'id': 'test-item',
                'productName': product,
                'quantity': 2,
                'unitPriceCents': 600,
                'lineTotalCents': 1200,
                'notes': 'Sin cebolla.',
                'modifiers': [
                  {
                    'id': 'extra',
                    'groupName': 'Extras',
                    'optionName': 'Piña',
                    'priceDeltaCents': 100,
                  },
                ],
              },
            ],
          }),
          profile,
        );
        final paper = lines.map((r) => r.text).join('\n');
        final compact = paper.replaceAll(RegExp(r'-?\$\d+\.\d\d|\s+'), '');
        expect(compact, contains(customer));
        expect(compact, contains('#$number'));
        expect(compact, contains(product));
        expect(compact, contains('Discount(PRUEBA-LARGA-DE-DESCUENTO-2026)'));
        expect(paper, contains('TO-GO ORDER'));
        expect(paper, contains('Pickup ASAP'));
        expect(paper, contains('Extras: Piña (+\$1.00)'));
        expect(paper, contains('NOTE\nIncluir cubiertos.'));
        expect(paper, contains('Paid with Visa ending in 1234'));
        expect(paper, contains('[ PAID ]\nPAGADO'));
        expect(paper, isNot(contains('Tax')));
        expect(paper, isNot(contains('Pelines Service Fee')));
        expect(paper, isNot(contains('Delivery Fee')));
        for (final row in lines) {
          expect(
            row.text.length * ((row.size & 16) == 0 ? 1 : 2),
            lessThanOrEqualTo(profile.columns),
            reason: row.text,
          );
        }
        for (final label in ['2 x ', 'Subtotal', 'Discount', 'Amount Paid']) {
          final row = lines.firstWhere((r) => r.text.startsWith(label));
          expect(row.text.length, profile.columns);
          expect(row.text, matches(RegExp(r'\$\d+\.\d\d$')));
        }
        final paid = lines.firstWhere((r) => r.text.startsWith('Amount Paid'));
        expect((paid.size, paid.bold, paid.center), (1, true, false));
        final stamp = lines.firstWhere((r) => r.text == '[ PAID ]');
        expect((stamp.size, stamp.bold, stamp.center), (17, true, true));
        final payment = lines.firstWhere((r) => r.text.startsWith('Paid with'));
        expect((payment.size, payment.bold, payment.center), (0, false, true));
        expect(lines.last, (
          text: 'pelinesmexicanrestaurant.com',
          size: 0,
          bold: false,
          center: true,
        ));
      },
    );

    test('scheduled pickup, delivery and catering retain modality and Pacific time', () {
      final pickup = orderJson()..['scheduledFor'] = '2026-11-01T08:30:00Z';
      final delivery = orderJson(fulfillment: 'delivery')
        ..addAll({
          'deliveryAddress': {
            'line1': '123 Calle Ficticia',
            'city': 'Ciudad Ejemplo',
            'state': 'OR',
            'zip': '97000',
            'internal': 'hidden',
          },
        });
      final catering = orderJson(fulfillment: 'delivery')
        ..addAll({
          'orderType': 'catering',
          'scheduledFor': '2026-11-01T09:30:00Z',
          'eventDetails': {
            'eventName': 'Comida de ensayo',
            'attendees': 35,
            'extra': {'ignored': true},
          },
        });
      String paper(Map<String, dynamic> json) =>
          render(json, profile).map((r) => r.text).join('\n');
      expect(paper(pickup), contains('Pickup scheduled\n2026-11-01 01:30 PDT'));
      expect(
        paper(delivery),
        allOf(
          contains('DELIVERY ORDER'),
          contains('Delivery ASAP'),
          contains('Deliver to: 123 Calle Ficticia'),
          isNot(contains('hidden')),
        ),
      );
      expect(
        paper(catering),
        allOf(
          contains('CATERING'),
          contains('Delivery / Event\n2026-11-01 01:30 PST'),
          contains('Event: Comida de ensayo'),
          contains('Attendees: 35'),
          isNot(contains('{')),
        ),
      );
    });

    test('unpaid and optional data absent never imply a captured payment', () {
      final lines = render(
        orderJson(payment: 'unpaid')..['contactPhone'] = '',
        profile,
      );
      final paper = lines.map((r) => r.text).join('\n');
      expect(paper, allOf(contains('Total'), contains('Payment: unpaid')));
      for (final value in [
        'Phone:',
        'Amount Paid',
        '[ PAID ]',
        'PAGADO',
        'Discount',
        'Deliver to:',
        'ending in',
        'NOTE',
      ]) {
        expect(paper, isNot(contains(value)));
      }
    });
  }
}
