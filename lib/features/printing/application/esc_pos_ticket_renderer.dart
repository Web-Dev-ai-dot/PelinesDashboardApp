import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../../../core/time/pelines_time.dart';
import '../../orders/models/order_models.dart';
import '../models/ticket_document.dart';

/// Conservative Font A layout fitting both TM-m30II 48/35 and 42/32 modes.
enum EscPosPaperProfile {
  paper80(42),
  paper58(32);

  const EscPosPaperProfile(this.columns);
  final int columns;
}

class TicketEncodingException implements Exception {
  const TicketEncodingException();
}

/// Epson page 16 (Windows-1252). Unsupported Unicode or printer control
/// characters fail the entire render before a socket is opened.
Uint8List encodePrinterText(String text) {
  const extended = <int, int>{
    0x20ac: 0x80,
    0x201a: 0x82,
    0x0192: 0x83,
    0x201e: 0x84,
    0x2026: 0x85,
    0x2020: 0x86,
    0x2021: 0x87,
    0x02c6: 0x88,
    0x2030: 0x89,
    0x0160: 0x8a,
    0x2039: 0x8b,
    0x0152: 0x8c,
    0x017d: 0x8e,
    0x2018: 0x91,
    0x2019: 0x92,
    0x201c: 0x93,
    0x201d: 0x94,
    0x2022: 0x95,
    0x2013: 0x96,
    0x2014: 0x97,
    0x02dc: 0x98,
    0x2122: 0x99,
    0x0161: 0x9a,
    0x203a: 0x9b,
    0x0153: 0x9c,
    0x017e: 0x9e,
    0x0178: 0x9f,
  };
  var normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  const composed = {
    'a\u0301': 'á',
    'e\u0301': 'é',
    'i\u0301': 'í',
    'o\u0301': 'ó',
    'u\u0301': 'ú',
    'n\u0303': 'ñ',
    'u\u0308': 'ü',
    'A\u0301': 'Á',
    'E\u0301': 'É',
    'I\u0301': 'Í',
    'O\u0301': 'Ó',
    'U\u0301': 'Ú',
    'N\u0303': 'Ñ',
    'U\u0308': 'Ü',
  };
  for (final entry in composed.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return Uint8List.fromList(
    normalized.runes.map((rune) {
      if (rune == 10 ||
          (rune >= 32 && rune <= 126) ||
          (rune >= 160 && rune <= 255)) {
        return rune;
      }
      final byte = extended[rune];
      if (byte == null) throw const TicketEncodingException();
      return byte;
    }).toList(),
  );
}

class EscPosTicketRenderer {
  const EscPosTicketRenderer({this.profile = EscPosPaperProfile.paper80});
  final EscPosPaperProfile profile;

  Uint8List render(TicketDocument ticket) {
    final out = BytesBuilder(copy: false);
    void command(List<int> bytes) => out.add(bytes);
    void line(
      String text, {
      bool large = false,
      bool bold = false,
      bool center = false,
    }) {
      final encoded = encodePrinterText(text);
      final width = profile.columns ~/ (large ? 2 : 1);
      command([
        27,
        97,
        center ? 1 : 0,
        27,
        69,
        bold ? 1 : 0,
        29,
        33,
        large ? 17 : 0,
      ]);
      // Wrap encoded characters, not UTF-16 units. No content is truncated.
      for (final paragraph in _splitLines(encoded)) {
        var start = 0;
        while (paragraph.length - start > width) {
          var end = start + width;
          final space = paragraph.lastIndexOf(32, end);
          if (space > start) end = space;
          out.add(paragraph.sublist(start, end));
          command([10]);
          start = end;
          if (start < paragraph.length && paragraph[start] == 32) start++;
        }
        out.add(paragraph.sublist(start));
        command([10]);
      }
    }

    void optional(String label, String? value) {
      if (value != null && value.isNotEmpty) line('$label$value');
    }

    String money(int cents) =>
        '${cents < 0 ? '-' : ''}\$${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';
    void amount(String label, int cents, {bool bold = false}) {
      final value = money(cents);
      final spaces = profile.columns - label.length - value.length;
      line('$label${' ' * (spaces > 0 ? spaces : 1)}$value', bold: bold);
    }

    String time(DateTime value) =>
        '${DateFormat('yyyy-MM-dd HH:mm').format(PelinesTime.inPacific(value))} Pacific';
    void separator() => line('-' * profile.columns);

    command([27, 64]); // Initialize; does not reset persistent device settings.
    command([
      28,
      40,
      67,
      2,
      0,
      48,
      1,
    ]); // Character-code-table mode (not UTF-8).
    command([28, 46, 27, 82, 0, 27, 116, 16]); // Cancel Kanji; USA; WPC1252.
    command([27, 77, 0, 27, 32, 0]); // Font A, no extra character spacing.
    line('PELINES', bold: true, center: true);
    optional('Location: ', ticket.locationName);
    line(ticket.orderNumber, large: true, bold: true, center: true);
    line(
      '${ticket.orderType.name.toUpperCase()} / ${ticket.fulfillmentType.name.toUpperCase()}',
    );
    final catering = ticket.orderType == OrderType.catering;
    if (catering) line('CATERING', large: true, bold: true, center: true);
    optional('Customer: ', ticket.customerName);
    optional('Phone: ', ticket.phone);
    line('Placed: ${time(ticket.placedAt)}');
    line(
      ticket.isAsap
          ? (catering ? 'Event time unavailable' : 'ASAP')
          : '${catering ? 'Event' : 'Scheduled'}: ${time(ticket.scheduledFor!)}',
      bold: true,
    );
    if (ticket.deliveryAddress != null) {
      line('Delivery: ${jsonEncode(ticket.deliveryAddress)}');
    }
    if (ticket.eventDetails != null) {
      line('Event: ${jsonEncode(ticket.eventDetails)}');
    }
    separator();
    for (final item in ticket.items) {
      line('${item.quantity} x ${item.name}', bold: true);
      line('Unit: ${money(item.baseUnitPriceCents)}');
      for (final modifier in item.modifiers) {
        line(
          '  ${modifier.groupName}: ${modifier.optionName} (${money(modifier.priceAdjustmentCents)})',
        );
      }
      optional('Instructions: ', item.instructions);
      amount('Item total', item.lineTotalCents);
    }
    optional('Notes: ', ticket.notes);
    separator();
    final totals = ticket.totals;
    amount('Subtotal', totals.subtotalCents);
    amount('Service fee', totals.serviceFeeCents);
    amount('Tip', totals.tipCents);
    amount('Delivery fee', totals.deliveryFeeCents);
    amount('Discount', -totals.discountCents);
    optional('Discount code: ', ticket.discountCode);
    amount('Tax', totals.taxCents);
    amount('Total', totals.totalCents, bold: true);
    if (totals.amountPaidCents case final int paid) {
      amount('Amount paid', paid, bold: true);
    } else {
      line('Amount paid: Unknown');
    }
    line('Payment: ${ticket.payment.name}');
    optional('Card: ', ticket.cardBrand);
    optional('Card ending: ', ticket.cardLast4);
    command([27, 69, 0, 29, 33, 0, 27, 97, 0]);
    command([
      27,
      100,
      3,
      29,
      86,
      66,
      0,
    ]); // Feed, then feed to cutter + partial cut.
    return out.takeBytes();
  }
}

Iterable<List<int>> _splitLines(List<int> bytes) sync* {
  var start = 0;
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] == 10) {
      yield bytes.sublist(start, i);
      start = i + 1;
    }
  }
  yield bytes.sublist(start);
}
