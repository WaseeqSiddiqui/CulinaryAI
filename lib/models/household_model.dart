class HouseholdModel {
  final String id;
  final String name;
  final String ownerId;
  final List<String> memberIds;
  final Map<String, String> memberRoles;
  final String inviteCode;
  final DateTime? inviteExpiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  HouseholdModel({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.memberIds,
    this.memberRoles = const {},
    required this.inviteCode,
    this.inviteExpiresAt,
    required this.createdAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'owner_id': ownerId,
      'member_ids': memberIds,
      'member_roles': memberRoles,
      'invite_code': inviteCode,
      'invite_expires_at': inviteExpiresAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
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

    final ownerId = map['owner_id']?.toString() ?? '';
    final memberIds = List<String>.from(map['member_ids'] ?? []);
    final memberRoles = Map<String, String>.from(
      map['member_roles'] ?? const {},
    );
    if (ownerId.isNotEmpty) memberRoles[ownerId] = 'owner';
    for (final memberId in memberIds) {
      memberRoles.putIfAbsent(memberId, () => 'member');
    }
    return HouseholdModel(
      id: id,
      name: map['name'] ?? 'My Kitchen',
      ownerId: ownerId,
      memberIds: memberIds,
      memberRoles: memberRoles,
      inviteCode: map['invite_code'] ?? '',
      inviteExpiresAt: _date(map['invite_expires_at']),
      createdAt: createdAt,
      updatedAt: _date(map['updated_at']) ?? createdAt,
    );
  }

  HouseholdModel copyWith({
    String? name,
    List<String>? memberIds,
    Map<String, String>? memberRoles,
    String? inviteCode,
    Object? inviteExpiresAt = _unset,
    DateTime? updatedAt,
  }) => HouseholdModel(
    id: id,
    name: name ?? this.name,
    ownerId: ownerId,
    memberIds: memberIds ?? this.memberIds,
    memberRoles: memberRoles ?? this.memberRoles,
    inviteCode: inviteCode ?? this.inviteCode,
    inviteExpiresAt: identical(inviteExpiresAt, _unset)
        ? this.inviteExpiresAt
        : inviteExpiresAt as DateTime?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static const Object _unset = Object();

  static DateTime? _date(Object? value) {
    if (value is String) return DateTime.tryParse(value);
    if (value is DateTime) return value;
    if (value != null) {
      try {
        return (value as dynamic).toDate() as DateTime;
      } catch (_) {}
    }
    return null;
  }
}
