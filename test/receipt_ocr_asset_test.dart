import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'the native OCR language model is included in the Flutter asset bundle',
    () async {
      final model = await rootBundle.load('assets/tessdata/eng.traineddata');
      expect(model.lengthInBytes, 15400601);
    },
  );
}
