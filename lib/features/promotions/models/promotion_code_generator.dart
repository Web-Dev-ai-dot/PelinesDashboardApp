import 'dart:math';

/// Local candidate only. Uniqueness is enforced by the server on creation.
String generatePromotionCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  return List.generate(
    12,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}
