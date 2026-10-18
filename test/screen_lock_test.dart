import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sclip/models/clipboard_entry.dart';
import 'package:sclip/services/clipboard_service.dart';

void main() {
  // The default state probe needs a binding to fail cleanly with
  // MissingPluginException instead of "binding not initialized".
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClipboardState.locked', () {
    test('defaults to false, unavailable sentinel is unlocked', () {
      const state = ClipboardState(change: 7, sensitive: false);
      expect(state.locked, isFalse);
      expect(ClipboardState.unavailable.locked, isFalse);
      expect(
        const ClipboardState(change: 7, sensitive: false, locked: true).locked,
        isTrue,
      );
    });

    test('a locked probe still ingests clipboard content', () async {
      ClipboardEntry current = ClipboardEntry.text('existing-at-launch');
      var change = 0;
      final service = ClipboardService(
        interval: const Duration(milliseconds: 20),
        entryReader: () async => current,
        stateProbe: () async =>
            ClipboardState(change: ++change, sensitive: false, locked: true),
      );

      final received = <ClipboardEntry>[];
      final sub = service.entries.listen(received.add);

      service.start();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(received, isEmpty);

      current = ClipboardEntry.text('copied-while-locked');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // The flag is carried, not acted on: read/dedup/baseline behaviour is
      // byte-for-byte what it was before the field existed.
      expect(received.length, 1);
      expect(received.first.text, 'copied-while-locked');

      await sub.cancel();
      await service.dispose();
    });
  });

  group('native currentState contract', () {
    String source(String relativePath) =>
        File('${Directory.current.path}/$relativePath').readAsStringSync();

    test('macOS currentState publishes the locked key', () {
      final swift = source('macos/Runner/MainFlutterWindow.swift');
      expect(
        swift.contains('CGSessionCopyCurrentDictionary'),
        isTrue,
        reason: 'macOS lock probe must use CGSessionCopyCurrentDictionary',
      );
      expect(
        swift.contains('CGSSessionScreenIsLocked'),
        isTrue,
        reason: 'macOS lock probe must read CGSSessionScreenIsLocked',
      );
      expect(
        swift.contains('"locked": locked'),
        isTrue,
        reason: 'currentState result map must carry the locked key',
      );
    });

    test('Windows currentState publishes the locked key', () {
      final cpp = source('windows/runner/flutter_window.cpp');
      // This leg cannot be compiled on macOS — see Faz 7. The grep gate is
      // the only regression net it has until then.
      expect(
        cpp.contains('OpenInputDesktop('),
        isTrue,
        reason: 'Windows lock probe must use OpenInputDesktop',
      );
      expect(
        cpp.contains('CloseDesktop('),
        isTrue,
        reason: 'a successfully opened desktop handle must be closed',
      );
      expect(
        cpp.contains('flutter::EncodableValue("locked")'),
        isTrue,
        reason: 'currentState result map must carry the locked key',
      );
    });

    test('lock state rides the existing channels, no new ones', () {
      final swift = source('macos/Runner/MainFlutterWindow.swift');
      final cpp = source('windows/runner/flutter_window.cpp');
      final channelName = RegExp(r'"sclip/\w+"');
      expect(swift.contains('EventChannel'), isFalse);
      expect(cpp.contains('EventChannel'), isFalse);
      expect(
        channelName.allMatches(swift).length,
        2,
        reason: 'exactly sclip/clipboard + sclip/window, nothing new',
      );
      expect(
        channelName.allMatches(cpp).length,
        2,
        reason: 'exactly sclip/clipboard + sclip/window, nothing new',
      );
    });
  });

  group('screen-lock edge trigger', () {
    test('consecutive locked ticks fire exactly one event', () async {
      var locked = false;
      var change = 0;
      final service = ClipboardService(
        interval: const Duration(milliseconds: 20),
        entryReader: () async => null,
        stateProbe: () async =>
            ClipboardState(change: ++change, sensitive: false, locked: locked),
      );

      var events = 0;
      final lockSub = service.screenLocks.listen((_) {
        events++;
      });

      service.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(events, 0, reason: 'unlocked ticks must stay silent');

      locked = true;
      // Long enough for several ticks. The level stays true the whole
      // time; only the transition into it counts.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(
        events,
        1,
        reason: 'clearing must run once per lock, not once per tick',
      );

      locked = false;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(events, 1, reason: 'unlocking is not an edge');

      locked = true;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(events, 2, reason: 'a second lock is a new edge');

      await lockSub.cancel();
      await service.dispose();
    });

    test('lock edge is seen even when the clipboard never moves', () async {
      // The regression this guards: a locked screen is exactly when the
      // change counter stops moving, so a lock check placed after the
      // counter short-circuit would never run.
      var locked = false;
      final service = ClipboardService(
        interval: const Duration(milliseconds: 20),
        entryReader: () async => null,
        // Frozen counter — every tick short-circuits at step 1.
        stateProbe: () async =>
            ClipboardState(change: 42, sensitive: false, locked: locked),
      );

      var events = 0;
      final lockSub = service.screenLocks.listen((_) {
        events++;
      });

      service.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      locked = true;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(events, 1);

      await lockSub.cancel();
      await service.dispose();
    });
  });
}
