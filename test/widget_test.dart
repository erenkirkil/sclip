import 'package:flutter_test/flutter_test.dart';

import 'package:sclip/main.dart';

void main() {
  testWidgets('app boots with empty state message', (tester) async {
    await tester.pumpWidget(const SclipApp());
    await tester.pump();

    expect(find.text('sclip'), findsOneWidget);
    expect(find.textContaining('Henüz içerik yok'), findsOneWidget);
  });
}
