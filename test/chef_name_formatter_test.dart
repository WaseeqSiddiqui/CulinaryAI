import 'package:culinary_ai/core/utils/chef_name_formatter.dart';
import 'package:culinary_ai/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the first word of a saved profile name', () {
    final user = UserModel(
      id: 'user-1',
      name: 'Waseeq Saad',
      email: 'waseeqsaad@gmail.com',
    );

    expect(ChefNameFormatter.fromUser(user), 'Waseeq');
  });

  test('derives a readable first name from the email fallback', () {
    final user = UserModel(
      id: 'user-1',
      name: 'waseeqsaad',
      email: 'waseeqsaad@gmail.com',
    );

    expect(ChefNameFormatter.fromUser(user), 'Waseeq');
  });

  test('supports email addresses separated by punctuation', () {
    final user = UserModel(
      id: 'user-1',
      name: 'Chef',
      email: 'amna.khan@example.com',
    );

    expect(ChefNameFormatter.fromUser(user), 'Amna');
  });
}
