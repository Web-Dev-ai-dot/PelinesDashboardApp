import 'dart:math';

final RegExp _dollars = RegExp(r'^\d+(\.\d{1,2})?$');

/// "12", "12.5", "12.50", "$12.50" -> cents with integer math only.
/// Anything else (more than 2 decimals, signs, separators) -> null.
int? parseDollarsToCents(String input) {
  String value = input.trim();
  if (value.startsWith(r'$')) value = value.substring(1).trim();
  if (!_dollars.hasMatch(value)) return null;
  final List<String> parts = value.split('.');
  // Long digit strings must not overflow into a "valid" amount.
  if (parts[0].length > 12) return null;
  final int? whole = int.tryParse(parts[0]);
  final int? fraction = int.tryParse(
    parts.length > 1 ? parts[1].padRight(2, '0') : '0',
  );
  if (whole == null || fraction == null) return null;
  return whole * 100 + fraction;
}

/// Plain "12.50" (no symbol, no grouping) for prefilling an amount field.
String centsToDollarInput(int cents) {
  final int abs = cents.abs();
  final String sign = cents < 0 ? '-' : '';
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}

/// RFC 4122 version 4 UUID from a secure random source.
String newIdempotencyKey([Random? random]) {
  final Random source = random ?? Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final String hex = bytes
      .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
