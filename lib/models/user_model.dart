class UserModel {
  final String id;
  final String name;
  final String email;
  final String? householdId;
  final String? phoneNumber;
  final DateTime? dateOfBirth;
  final String? location;
  final String? bio;
  final String? dietaryPreference;
  final String? photoUrl;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.householdId,
    this.phoneNumber,
    this.dateOfBirth,
    this.location,
    this.bio,
    this.dietaryPreference,
    this.photoUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'household_id': householdId,
      'phone_number': phoneNumber,
      'date_of_birth': dateOfBirth?.toIso8601String(),
      'location': location,
      'bio': bio,
      'dietary_preference': dietaryPreference,
      'photo_url': photoUrl,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    return UserModel(
      id: id,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      householdId: map['household_id'],
      phoneNumber: map['phone_number'],
      dateOfBirth: map['date_of_birth'] is String
          ? DateTime.tryParse(map['date_of_birth'])
          : null,
      location: map['location'],
      bio: map['bio'],
      dietaryPreference: map['dietary_preference'],
      photoUrl: map['photo_url'],
    );
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? householdId,
    String? phoneNumber,
    DateTime? dateOfBirth,
    String? location,
    String? bio,
    String? dietaryPreference,
    String? photoUrl,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      householdId: householdId ?? this.householdId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      location: location ?? this.location,
      bio: bio ?? this.bio,
      dietaryPreference: dietaryPreference ?? this.dietaryPreference,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }
}
