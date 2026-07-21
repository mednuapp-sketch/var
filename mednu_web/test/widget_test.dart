import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mednu_web/main.dart';

void main() {
  testWidgets('App builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MednuWebApp()));
    await tester.pump();

    expect(find.byType(MednuWebApp), findsOneWidget);
  });
}
