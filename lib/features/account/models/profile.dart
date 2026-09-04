enum ProfileRole {
  customer,
  admin;

  static ProfileRole fromJson(Object? value) {
    return switch (value) {
      'admin' => ProfileRole.admin,
      'customer' => ProfileRole.customer,
      _ => throw FormatException('Unsupported profile role: $value'),
    };
  }
}

class Profile {
  const Profile({
    required this.id,
    required this.role,
    required this.createdAt,
    required this.updatedAt,
    this.fullName,
    this.phone,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      role: ProfileRole.fromJson(json['role']),
      fullName: json['fullName'] as String?,
      phone: json['phone'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  final String id;
  final ProfileRole role;
  final String? fullName;
  final String? phone;
  final DateTime createdAt;
  final DateTime updatedAt;
}
