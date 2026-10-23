enum PasswordChangeError {
  sessionExpired,
  incorrectCurrent,
  rejected,
  reauthenticationRequired,
  invalidCode,
  rateLimited,
  unavailable,
  uncertain,
}

class PasswordChangeFailure implements Exception {
  const PasswordChangeFailure(this.reason);
  final PasswordChangeError reason;

  String get message => switch (reason) {
    PasswordChangeError.sessionExpired =>
      'Your session changed or expired. Please sign in again.',
    PasswordChangeError.incorrectCurrent =>
      'The current password is incorrect.',
    PasswordChangeError.rejected =>
      'The new password was rejected. Choose a stronger, different password.',
    PasswordChangeError.reauthenticationRequired =>
      'Verification is required before changing your password.',
    PasswordChangeError.invalidCode =>
      'The verification code is invalid or expired.',
    PasswordChangeError.rateLimited =>
      'Too many attempts. Please wait before trying again.',
    PasswordChangeError.unavailable =>
      'The authentication service could not be reached. Please try again.',
    PasswordChangeError.uncertain => 'The password change could not be confirmed. Do not retry automatically; sign in again to check.',
  };

  @override
  String toString() => 'PasswordChangeFailure(${reason.name})';
}

/// A capability of the existing auth repository, independent of profile drafts.
abstract interface class PasswordAuthRepository {
  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
    String? nonce,
  });
  Future<void> requestPasswordVerification({required String userId});
}
