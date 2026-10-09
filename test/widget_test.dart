import 'package:flutter_test/flutter_test.dart';
import 'package:culinary_ai/main.dart';

void main() {
  testWidgets('CulinaryAI app boots to login screen test', (WidgetTester tester) async {
    await tester.pumpWidget(const CulinaryAiApp());
    await tester.pumpAndSettle();

    // Verify CulinaryAI brand header and Sign In are present
    expect(find.text('CulinaryAI'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
