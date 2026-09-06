import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/account/models/profile.dart';
import 'package:pelines_admin_app/features/account/models/profile_edit.dart';

void main() {
  group('ProfileDraft', () {
    test('trims values and converts blanks to null', () {
      final ProfileDraftResult result = const ProfileDraft(
        fullName: '  Ada Lovelace  ',
        phone: '   ',
      ).validate();

      expect(result.isValid, isTrue);
      expect(result.fullName, 'Ada Lovelace');
      expect(result.phone, isNull);
    });

    test('enforces the backend field limits', () {
      expect(
        ProfileDraft(fullName: 'n' * 120, phone: 'p' * 40).validate().isValid,
        isTrue,
      );
      expect(
        ProfileDraft(fullName: 'n' * 121, phone: '').validate().message,
        contains('120'),
      );
      expect(
        ProfileDraft(fullName: '', phone: 'p' * 41).validate().message,
        contains('40'),
      );
    });
  });

  test('profilePatch sends only changed fields, including explicit nulls', () {
    final Profile canonical = _profile(fullName: 'Ada', phone: '555');

    expect(
      profilePatch(
        canonical,
        const ProfileDraft(fullName: ' Ada ', phone: '555').validate(),
      ),
      isEmpty,
    );
    expect(
      profilePatch(
        canonical,
        const ProfileDraft(fullName: 'Grace', phone: ' ').validate(),
      ),
      <String, dynamic>{'fullName': 'Grace', 'phone': null},
    );
  });
}

Profile _profile({String? fullName, String? phone}) => Profile(
  id: 'profile-id',
  role: ProfileRole.admin,
  fullName: fullName,
  phone: phone,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026, 1, 2),
);
