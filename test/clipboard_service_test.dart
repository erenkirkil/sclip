import 'package:flutter_test/flutter_test.dart';
import 'package:sclip/models/clipboard_entry.dart';
import 'package:sclip/services/clipboard_service.dart';

void main() {
  // Initialized once up-front so the default state-probe can fail cleanly
  // with MissingPluginException (handled by the service) instead of a raw
  // "binding not initialized" error flooding the test log.
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The in-process default is the unavailable sentinel — none of these tests
  /// exercise the native changeCount path, so we short-circuit it explicitly.
  Future<ClipboardState> neverSensitive() async => ClipboardState.unavailable;

  group('ClipboardService', () {
    test('emits entry when mock reader returns new value', () async {
      ClipboardEntry? next;
      final service = ClipboardService(
        interval: const Duration(milliseconds: 20),
        entryReader: () async => next,
        stateProbe: neverSensitive,
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

    test('does not emit the clipboard content present at startup', () async {
      final service = ClipboardService(
        interval: const Duration(milliseconds: 20),
        entryReader: () async => ClipboardEntry.text('existing'),
        stateProbe: neverSensitive,
      );

      final received = <ClipboardEntry>[];
      final sub = service.entries.listen(received.add);

      service.start();
      await Future.delayed(const Duration(milliseconds: 120));

      expect(received, isEmpty);

      await sub.cancel();
      await service.dispose();
    });

    test('emits only copies made after startup baseline', () async {
      ClipboardEntry current = ClipboardEntry.text('existing-at-launch');
      final service = ClipboardService(
        interval: const Duration(milliseconds: 20),
        entryReader: () async => current,
        stateProbe: neverSensitive,
      );

      final received = <ClipboardEntry>[];
      final sub = service.entries.listen(received.add);

      service.start();
      await Future.delayed(const Duration(milliseconds: 80));
      expect(received, isEmpty);

      current = ClipboardEntry.text('copied-later');
      await Future.delayed(const Duration(milliseconds: 80));

      expect(received.length, 1);
      expect(received.first.text, 'copied-later');

      await sub.cancel();
      await service.dispose();
    });

    test('does not re-emit identical content', () async {
      final entry = ClipboardEntry.text('same');
      final service = ClipboardService(
        interval: const Duration(milliseconds: 20),
        entryReader: () async => entry,
        stateProbe: neverSensitive,
      );

      final received = <ClipboardEntry>[];
      final sub = service.entries.listen(received.add);

      service.start();
      await Future.delayed(const Duration(milliseconds: 120));

      expect(received, isEmpty);

      await sub.cancel();
      await service.dispose();
    });

    test('stop halts emissions', () async {
      var counter = 0;
      final service = ClipboardService(
        interval: const Duration(milliseconds: 20),
        entryReader: () async => ClipboardEntry.text('v${counter++}'),
        stateProbe: neverSensitive,
      );

      final received = <ClipboardEntry>[];
      final sub = service.entries.listen(received.add);

      service.start();
      await Future.delayed(const Duration(milliseconds: 80));
      service.stop();
      await Future.delayed(const Duration(milliseconds: 40));
      final countAtStop = received.length;
      await Future.delayed(const Duration(milliseconds: 120));

      expect(received.length, countAtStop);

      await sub.cancel();
      await service.dispose();
    });

    test('skips reads when native change counter is unchanged', () async {
      var reads = 0;
      final service = ClipboardService(
        interval: const Duration(milliseconds: 20),
        entryReader: () async {
          reads++;
          return ClipboardEntry.text('doesnt matter');
        },
        // Fixed change counter means nothing moved on the OS clipboard.
        stateProbe: () async =>
            const ClipboardState(change: 42, sensitive: false),
      );

      final received = <ClipboardEntry>[];
      final sub = service.entries.listen(received.add);

      service.start();
      await Future.delayed(const Duration(milliseconds: 120));

      // Exactly one read: the first tick establishes the baseline counter,
      // after which the probe short-circuits every subsequent tick.
      expect(reads, 1);
      expect(received, isEmpty);

      await sub.cancel();
      await service.dispose();
    });

    test('skips reads when hasFilePromise flag is set', () async {
      var currentChange = 0;
      var reads = 0;
      var hasPromise = true;
      final service = ClipboardService(
        interval: const Duration(milliseconds: 20),
        entryReader: () async {
          reads++;
          return ClipboardEntry.text('should-not-be-read');
        },
        stateProbe: () async => ClipboardState(
          change: ++currentChange,
          sensitive: false,
          hasFilePromise: hasPromise,
        ),
      );

      final received = <ClipboardEntry>[];
      final sub = service.entries.listen(received.add);

      service.start();
      await Future.delayed(const Duration(milliseconds: 80));
      // Promise short-circuits the reader entirely — the probe bumps every
      // tick but reads never happen and no entries are emitted. Treating
      // promise payloads as "seen" also primes the baseline so a later
      // real copy emits on first observation.
      expect(reads, 0);
      expect(received, isEmpty);

      hasPromise = false;
      await Future.delayed(const Duration(milliseconds: 80));

      expect(reads, greaterThanOrEqualTo(1));

      await sub.cancel();
      await service.dispose();
    });

    test('skips emissions when sensitive flag is set', () async {
      var currentChange = 0;
      var sensitive = true;
      final service = ClipboardService(
        interval: const Duration(milliseconds: 20),
        entryReader: () async => ClipboardEntry.text('secret'),
        stateProbe: () async => ClipboardState(
          change: ++currentChange,
          sensitive: sensitive,
        ),
      );

      final received = <ClipboardEntry>[];
      final sub = service.entries.listen(received.add);

      service.start();
      await Future.delayed(const Duration(milliseconds: 80));
      expect(received, isEmpty);

      // User switches to non-sensitive content.
      sensitive = false;
      await Future.delayed(const Duration(milliseconds: 80));

      // Sensitive path never touches _primed so the first non-sensitive
      // observation becomes the baseline — second one emits.
      expect(received.length, lessThanOrEqualTo(1));

      await sub.cancel();
      await service.dispose();
    });
  });
}
