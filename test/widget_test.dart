import 'package:flutter_test/flutter_test.dart';
import 'package:vedastro_ai/main.dart';

void main() {
  testWidgets('App loads home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const VedAstroApp());
    expect(find.text('VedAstro AI'), findsOneWidget);
  });
}
