import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nova_companion/main.dart';

void main() {
  testWidgets('NOVA app boots to welcome', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: NovaApp()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('NOVA'), findsOneWidget);
    expect(find.text('Find my Deskbot'), findsOneWidget);
  });
}
