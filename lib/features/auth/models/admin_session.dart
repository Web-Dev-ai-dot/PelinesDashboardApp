import '../../account/models/profile.dart';

class AdminSession {
  const AdminSession({required this.profile, this.email});

  final Profile profile;
  final String? email;
}
