import 'profile.dart';

class ProfileDraft {
  const ProfileDraft({required this.fullName, required this.phone});

  final String fullName;
  final String phone;

  ProfileDraftResult validate() {
    final String normalizedName = fullName.trim();
    final String normalizedPhone = phone.trim();
    if (normalizedName.length > 120) {
      return const ProfileDraftResult.error(
        'Full name must be 120 characters or fewer.',
      );
    }
    if (normalizedPhone.length > 40) {
      return const ProfileDraftResult.error(
        'Phone must be 40 characters or fewer.',
      );
    }
    return ProfileDraftResult.valid(
      fullName: normalizedName.isEmpty ? null : normalizedName,
      phone: normalizedPhone.isEmpty ? null : normalizedPhone,
    );
  }
}

class ProfileDraftResult {
  const ProfileDraftResult.valid({required this.fullName, required this.phone})
    : message = null;
  const ProfileDraftResult.error(this.message) : fullName = null, phone = null;

  final String? fullName;
  final String? phone;
  final String? message;
  bool get isValid => message == null;
}

Map<String, dynamic> profilePatch(
  Profile canonical,
  ProfileDraftResult desired,
) => <String, dynamic>{
  if (canonical.fullName != desired.fullName) 'fullName': desired.fullName,
  if (canonical.phone != desired.phone) 'phone': desired.phone,
};
