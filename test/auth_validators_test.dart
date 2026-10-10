import 'package:culinary_ai/core/utils/auth_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthValidators', () {
    test('accepts valid email addresses and rejects malformed ones', () {
      expect(AuthValidators.email('chef@example.com'), isNull);
      expect(AuthValidators.email(' chef@example.com '), isNull);
      expect(AuthValidators.email('chef@invalid'), isNotNull);
      expect(AuthValidators.email(''), isNotNull);
    });

    test('requires a strong password for signup', () {
      expect(AuthValidators.signupPassword('Kitchen9'), isNull);
      expect(AuthValidators.signupPassword('password9'), isNotNull);
      expect(AuthValidators.signupPassword('PASSWORD9'), isNotNull);
      expect(AuthValidators.signupPassword('Kitchen'), isNotNull);
      expect(AuthValidators.signupPassword('Kit9'), isNotNull);
    });

    test('keeps login compatible with existing six-character passwords', () {
      expect(AuthValidators.loginPassword('123456'), isNull);
      expect(AuthValidators.loginPassword('12345'), isNotNull);
    });

    test('checks password confirmation and optional phone numbers', () {
      expect(AuthValidators.confirmPassword('Kitchen9', 'Kitchen9'), isNull);
      expect(AuthValidators.confirmPassword('Kitchen8', 'Kitchen9'), isNotNull);
      expect(AuthValidators.phone(''), isNull);
      expect(AuthValidators.phone('+92 300 1234567'), isNull);
      expect(AuthValidators.phone('123'), isNotNull);
    });
  });
}
