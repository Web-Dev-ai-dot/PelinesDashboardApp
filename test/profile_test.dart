import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/account/models/profile.dart';

void main() {
  test('parses the real camelCase /me profile contract', () {
    final Profile profile = Profile.fromJson(<String, dynamic>{
      'id': '10cebd42-65df-46a8-b0bf-6aeaf02bc33f',
      'role': 'admin',
      'fullName': 'Pelines Admin',
      'phone': null,
      'createdAt': '2026-05-02T10:00:00.000Z',
      'updatedAt': '2026-09-03T10:00:00.000Z',
    });

    expect(profile.role, ProfileRole.admin);
    expect(profile.fullName, 'Pelines Admin');
    expect(profile.phone, isNull);
    expect(profile.createdAt.isUtc, isTrue);
  });

  test('rejects an unknown role instead of granting access', () {
    expect(() => ProfileRole.fromJson('owner'), throwsFormatException);
  });
}
