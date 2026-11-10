import 'package:culinary_ai/services/store_location_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () =>
        messenger.setMockMethodCallHandler(StoreLocationService.channel, null),
  );

  test('uses the resolved address returned for the current GPS fix', () async {
    messenger.setMockMethodCallHandler(StoreLocationService.channel, (
      call,
    ) async {
      expect(call.method, 'getCurrentLocationAddress');
      return {
        'latitude': 31.5,
        'longitude': 74.3,
        'accuracy': 25.0,
        'address': 'Gulberg, Lahore',
      };
    });
    final location = await StoreLocationService().currentAddress();
    expect(location.address, 'Gulberg, Lahore');
    expect(location.latitude, 31.5);
    expect(location.accuracy, 25);
  });

  test('does not invent an address when GPS is disabled', () async {
    messenger.setMockMethodCallHandler(StoreLocationService.channel, (_) async {
      throw PlatformException(
        code: 'location_disabled',
        message: 'Turn on Location',
      );
    });
    await expectLater(
      StoreLocationService().currentAddress(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'location_disabled',
        ),
      ),
    );
  });

  test('rejects an empty address and invalid coordinates instead of using old location', () {
    for (final value in [
      {'latitude': 31.5, 'longitude': 74.3, 'accuracy': 20, 'address': ''},
      {'latitude': 91, 'longitude': 74.3, 'accuracy': 20, 'address': 'Lahore'},
      {
        'latitude': 31.5,
        'longitude': double.nan,
        'accuracy': 20,
        'address': 'Lahore',
      },
      {
        'latitude': 31.5,
        'longitude': 74.3,
        'accuracy': -1,
        'address': 'Lahore',
      },
    ]) {
      expect(() => StoreLocation.fromMap(value), throwsFormatException);
    }
  });
}
