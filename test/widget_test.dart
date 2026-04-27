import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sclip/main.dart';
import 'package:sclip/providers/settings_provider.dart';
import 'package:sclip/services/settings_service.dart';

void main() {
  testWidgets('app boots with empty state message', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = await SettingsService.load();
    final settings = SettingsProvider(service);
    await tester.pumpWidget(SclipApp(settings: settings));
    await tester.pump();

    expect(find.bySemanticsLabel('sclip'), findsOneWidget);
    expect(find.textContaining('Henüz içerik yok'), findsOneWidget);
  });
}
