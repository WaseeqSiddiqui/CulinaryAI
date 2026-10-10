class HouseholdModel {
  final String id;
  final String name;
  final String ownerId;
  final List<String> memberIds;
  final String inviteCode;
  final DateTime createdAt;

  HouseholdModel({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.memberIds,
    required this.inviteCode,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'owner_id': ownerId,
      'member_ids': memberIds,
      'invite_code': inviteCode,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory HouseholdModel.fromMap(Map<String, dynamic> map, String id) {
    final rawCreatedAt = map['created_at'];
    DateTime createdAt = DateTime.now();
    if (rawCreatedAt is String) {
      createdAt = DateTime.tryParse(rawCreatedAt) ?? createdAt;
    } else if (rawCreatedAt is DateTime) {
      createdAt = rawCreatedAt;
    } else if (rawCreatedAt != null) {
      try {
        createdAt = (rawCreatedAt as dynamic).toDate() as DateTime;
      } catch (_) {}
    }

    return HouseholdModel(
      id: id,
      name: map['name'] ?? 'My Kitchen',
      ownerId: map['owner_id'] ?? '',
      memberIds: List<String>.from(map['member_ids'] ?? []),
      inviteCode: map['invite_code'] ?? '',
      createdAt: createdAt,
    );
  }
}
