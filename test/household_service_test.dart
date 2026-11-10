import 'package:culinary_ai/services/household_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('creates a household and joins it with its invite code', () async {
    SharedPreferences.setMockInitialValues({});
    final service = HouseholdService();

    final created = await service.create(
      name: 'Family Kitchen',
      userId: 'owner-1',
    );
    final joined = await service.join(
      inviteCode: created.inviteCode.toLowerCase(),
      userId: 'member-2',
    );

    expect(created.inviteCode, hasLength(6));
    expect(created.inviteExpiresAt, isNotNull);
    expect(created.memberRoles['owner-1'], 'owner');
    expect(joined.id, created.id);
    expect(joined.memberIds, containsAll(['owner-1', 'member-2']));
    expect(joined.memberRoles['member-2'], 'member');
    expect((await service.loadForUser('member-2'))?.id, created.id);
  });

  test('owner can assign roles and remove a member', () async {
    SharedPreferences.setMockInitialValues({});
    final service = HouseholdService();
    final created = await service.create(
      name: 'Family Kitchen',
      userId: 'owner-1',
    );
    final joined = await service.join(
      inviteCode: created.inviteCode,
      userId: 'member-2',
    );

    final promoted = await service.setMemberRole(
      household: joined,
      actorId: 'owner-1',
      memberId: 'member-2',
      role: 'admin',
    );
    expect(promoted.memberRoles['member-2'], 'admin');

    final removed = await service.removeMember(
      household: promoted,
      actorId: 'owner-1',
      memberId: 'member-2',
    );
    expect(removed.memberIds, isNot(contains('member-2')));
    expect(removed.memberRoles, isNot(contains('member-2')));
  });
}
