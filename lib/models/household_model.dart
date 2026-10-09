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
    return HouseholdModel(
      id: id,
      name: map['name'] ?? 'My Kitchen',
      ownerId: map['owner_id'] ?? '',
      memberIds: List<String>.from(map['member_ids'] ?? []),
      inviteCode: map['invite_code'] ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at']) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
