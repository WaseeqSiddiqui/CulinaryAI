import 'package:culinary_ai/models/user_model.dart';
import 'package:culinary_ai/services/session_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('authenticated user survives a new session service instance', () async {
    SharedPreferences.setMockInitialValues({});
    final user = UserModel(id: 'user-1', name: 'Sam', email: 'sam@example.com');

    await SessionService().saveUser(user);
    final restored = await SessionService().loadUser();

    expect(restored?.id, user.id);
    expect(restored?.name, user.name);
    expect(restored?.email, user.email);
  });

  test('clearing a session removes the persisted user', () async {
    SharedPreferences.setMockInitialValues({});
    final service = SessionService();
    await service.saveUser(
      UserModel(id: 'user-1', name: 'Sam', email: 'sam@example.com'),
    );

    await service.clear();

    expect(await service.loadUser(), isNull);
  });
}
