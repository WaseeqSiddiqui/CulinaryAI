class UserModel {
  final String id;
  final String name;
  final String email;
  final String? householdId;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.householdId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'household_id': householdId,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    return UserModel(
      id: id,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      householdId: map['household_id'],
    );
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? householdId,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      householdId: householdId ?? this.householdId,
    );
  }
}
