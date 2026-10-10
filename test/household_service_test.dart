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
    expect(joined.id, created.id);
    expect(joined.memberIds, containsAll(['owner-1', 'member-2']));
    expect((await service.loadForUser('member-2'))?.id, created.id);
  });
}
