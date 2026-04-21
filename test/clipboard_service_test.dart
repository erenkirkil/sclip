import 'package:flutter_test/flutter_test.dart';
import 'package:sclip/models/clipboard_entry.dart';
import 'package:sclip/services/clipboard_service.dart';

void main() {
  group('ClipboardService', () {
    test('emits entry when mock reader returns new value', () async {
      ClipboardEntry? next;
      final service = ClipboardService(
        interval: const Duration(milliseconds: 20),
        entryReader: () async => next,
      );

      final received = <ClipboardEntry>[];
      final sub = service.entries.listen(received.add);

      service.start();
      await Future.delayed(const Duration(milliseconds: 60));
      expect(received, isEmpty);

      next = ClipboardEntry.text('hello');
      await Future.delayed(const Duration(milliseconds: 80));

      expect(received.length, 1);
      expect(received.first.text, 'hello');

      await sub.cancel();
      await service.dispose();
    });

    test('does not re-emit identical content', () async {
      final entry = ClipboardEntry.text('same');
      final service = ClipboardService(
        interval: const Duration(milliseconds: 20),
        entryReader: () async => entry,
      );

      final received = <ClipboardEntry>[];
      final sub = service.entries.listen(received.add);

      service.start();
      await Future.delayed(const Duration(milliseconds: 120));

      expect(received.length, 1);

      await sub.cancel();
      await service.dispose();
    });

    test('stop halts emissions', () async {
      var counter = 0;
      final service = ClipboardService(
        interval: const Duration(milliseconds: 20),
        entryReader: () async => ClipboardEntry.text('v${counter++}'),
      );

      final received = <ClipboardEntry>[];
      final sub = service.entries.listen(received.add);

      service.start();
      await Future.delayed(const Duration(milliseconds: 80));
      service.stop();
      // Drain any in-flight tick that was awaiting before stop.
      await Future.delayed(const Duration(milliseconds: 40));
      final countAtStop = received.length;
      await Future.delayed(const Duration(milliseconds: 120));

      expect(received.length, countAtStop);

      await sub.cancel();
      await service.dispose();
    });
  });
}
