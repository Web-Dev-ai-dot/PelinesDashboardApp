import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../../../core/time/pelines_time.dart';
import '../../orders/models/order_models.dart';
import '../models/ticket_document.dart';
import 'thermal_logo.dart';

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
  static final _logo = base64Decode(thermalLogoBase64);

  Uint8List render(TicketDocument ticket) {
    final out = BytesBuilder(copy: false);
    void command(List<int> bytes) => out.add(bytes);

    void style({bool bold = false, bool center = false, int size = 0}) {
      command([27, 97, center ? 1 : 0, 27, 69, bold ? 1 : 0, 29, 33, size]);
    }

    void writeLine(List<int> bytes) {
      out.add(bytes);
      out.addByte(10);
    }

    void line(
      String text, {
      bool bold = false,
      bool center = false,
      int size = 0,
    }) {
      style(bold: bold, center: center, size: size);
      final width = profile.columns ~/ ((size & 16) == 0 ? 1 : 2);
      for (final row in _wrap(encodePrinterText(text), width)) {
        writeLine(row);
      }
    }

    void pair(String left, String right, {bool bold = false, int size = 0}) {
      final rightBytes = encodePrinterText(right);
      final leftWidth = profile.columns - rightBytes.length - 1;
      if (leftWidth < 8 || rightBytes.contains(10)) {
        line(left, bold: bold, size: size);
        for (final row in _wrap(rightBytes, profile.columns)) {
          style(bold: bold, size: size);
          writeLine([...List.filled(profile.columns - row.length, 32), ...row]);
        }
        return;
      }
      final rows = _wrap(encodePrinterText(left), leftWidth).iterator;
      rows.moveNext();
      style(bold: bold, size: size);
      writeLine([
        ...rows.current,
        ...List.filled(
          profile.columns - rows.current.length - rightBytes.length,
          32,
        ),
        ...rightBytes,
      ]);
      while (rows.moveNext()) {
        writeLine(rows.current);
      }
    }

    String money(int cents) =>
        '${cents < 0 ? '-' : ''}\$${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';
    void amount(String name, int cents) => pair(name, money(cents));
    void optionalAmount(String name, int cents) {
      if (cents != 0) amount(name, cents);
    }

    String time(DateTime value) {
      final pacific = PelinesTime.inPacific(value);
      return '${DateFormat('yyyy-MM-dd HH:mm').format(pacific)} ${pacific.timeZoneName}';
    }

    void separator({bool solid = false}) =>
        line((solid ? '=' : '-') * profile.columns);

    command([27, 64]); // Initialize without rewriting persistent settings.
    command([28, 40, 67, 2, 0, 48, 1]); // Character-code-table mode.
    command([28, 46, 27, 82, 0, 27, 116, 16]); // Cancel Kanji; USA; WPC1252.
    command([27, 77, 0, 27, 32, 0]); // Font A, no extra character spacing.
    style(center: true);
    command([29, 118, 48, 0, thermalLogoWidthBytes, 0, thermalLogoHeight, 0]);
    out.add(_logo);

    line('PELINES TEQUILA & MEZCAL', bold: true, center: true);
    final location = ticket.locationName?.trim() ?? '';
    if (location.isNotEmpty) line(location, center: true);
    separator(solid: true);

    final catering = ticket.orderType == OrderType.catering;
    final fulfillment = switch (ticket.fulfillmentType) {
      FulfillmentType.pickup => 'Pickup',
      FulfillmentType.delivery => 'Delivery',
      FulfillmentType.unknown => null,
    };
    if (ticket.isTest) {
      line('TEST / NOT A REAL ORDER', bold: true, center: true);
    }
    if (catering) line('CATERING', size: 17, bold: true, center: true);
    line(
      switch (fulfillment) {
        'Pickup' => 'TO-GO ORDER',
        'Delivery' => 'DELIVERY ORDER',
        _ => 'ORDER',
      },
      bold: true,
      center: true,
    );

    final number = ticket.orderNumber.startsWith('#')
        ? ticket.orderNumber
        : '#${ticket.orderNumber}';
    pair(ticket.customerName, number, bold: true, size: 1);

    final scheduled = ticket.scheduledFor;
    if (scheduled == null && !catering) {
      line(
        fulfillment == null ? 'ASAP' : '$fulfillment ASAP',
        size: 17,
        bold: true,
        center: true,
      );
    } else {
      line(
        catering
            ? [fulfillment, 'Event'].nonNulls.join(' / ')
            : [fulfillment, 'scheduled'].nonNulls.join(' '),
        bold: true,
        center: true,
        size: 1,
      );
      line(
        scheduled == null ? 'Event time unavailable' : time(scheduled),
        bold: true,
        center: true,
      );
    }
    if (ticket.phone.trim().isNotEmpty) {
      line('Phone: ${ticket.phone}', center: true);
    }
    line('Placed: ${time(ticket.placedAt)}', center: true);

    final address = [
      for (final key in ['line1', 'line2', 'city', 'state', 'zip'])
        if (_textField(ticket.deliveryAddress, key) case final String value)
          value,
    ];
    if (address.isNotEmpty) line('Deliver to: ${address.join(', ')}');
    if (catering) {
      if (_textField(ticket.eventDetails, 'eventName') case final String name) {
        line('Event: $name');
      }
      if (ticket.eventDetails?['attendees'] case final num count) {
        line('Attendees: $count');
      }
    }

    separator();
    for (final item in ticket.items) {
      pair(
        '${item.quantity} x ${item.name}',
        money(item.lineTotalCents),
        bold: true,
      );
      for (final modifier in item.modifiers) {
        final cents = modifier.priceAdjustmentCents;
        final adjustment = cents == 0
            ? ''
            : ' (${cents > 0 ? '+' : ''}${money(cents)})';
        line('  ${modifier.groupName}: ${modifier.optionName}$adjustment');
      }
      if (item.instructions?.trim() case final String instructions
          when instructions.isNotEmpty) {
        line('  Instructions: $instructions');
      }
    }
    if (ticket.notes?.trim() case final String notes when notes.isNotEmpty) {
      separator();
      line('NOTE', bold: true);
      line(notes);
    }

    separator();
    final totals = ticket.totals;
    amount('Subtotal', totals.subtotalCents);
    optionalAmount('Pelines Service Fee', totals.serviceFeeCents);
    optionalAmount('Delivery Fee', totals.deliveryFeeCents);
    optionalAmount('Tip', totals.tipCents);
    final discountCode = ticket.discountCode?.trim() ?? '';
    if (totals.discountCents != 0 || discountCode.isNotEmpty) {
      amount(
        discountCode.isEmpty ? 'Discount' : 'Discount ($discountCode)',
        -totals.discountCents,
      );
    }
    optionalAmount('Tax', totals.taxCents);
    separator(solid: true);

    if (ticket.payment == PaymentStatus.paid &&
        totals.amountPaidCents != null) {
      pair('Amount Paid', money(totals.amountPaidCents!), bold: true, size: 1);
    } else {
      pair('Total', money(totals.totalCents), bold: true, size: 1);
      line('Payment: ${ticket.payment.name}', center: true);
    }
    final brand = ticket.cardBrand?.trim() ?? '';
    final digits = ticket.cardLast4?.trim() ?? '';
    final last4 = RegExp(r'^[0-9]{4}$').hasMatch(digits) ? digits : '';
    if (!ticket.isTest && (brand.isNotEmpty || last4.isNotEmpty)) {
      line(
        [
          if (ticket.payment == PaymentStatus.paid) 'Paid with',
          brand.isEmpty ? 'card' : brand,
          if (last4.isNotEmpty) 'ending in $last4',
        ].join(' '),
        center: true,
      );
    }
    if (ticket.payment == PaymentStatus.paid) {
      if (ticket.isTest) {
        line('SIMULATED PAYMENT: card', bold: true, center: true);
      }
      line('[ PAID ]', size: 17, bold: true, center: true);
      line('PAGADO', bold: true, center: true);
    }

    separator(solid: true);
    line('Thank you for ordering from', center: true);
    line('Pelines Tequila & Mezcal', center: true);
    line('pelinesmexicanrestaurant.com', center: true);
    style();
    command([27, 100, 3, 29, 86, 66, 0]); // Feed and partial cut.
    return out.takeBytes();
  }
}

String? _textField(Map<String, dynamic>? fields, String key) {
  final value = fields?[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

/// Wrap in printer cells (encoded bytes), including unbroken identifiers.
Iterable<List<int>> _wrap(List<int> bytes, int width) sync* {
  var lineStart = 0;
  for (var i = 0; i <= bytes.length; i++) {
    if (i != bytes.length && bytes[i] != 10) continue;
    var start = lineStart;
    while (i - start > width) {
      final limit = start + width;
      var end = limit;
      while (end > start && bytes[end] != 32) {
        end--;
      }
      if (end == start) end = limit;
      yield bytes.sublist(start, end);
      start = end;
      if (bytes[start] == 32) start++;
    }
    yield bytes.sublist(start, i);
    lineStart = i + 1;
  }
}
