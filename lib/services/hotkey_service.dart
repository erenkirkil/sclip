import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

typedef HotkeyCallback = Future<void> Function();

class HotkeyService {
  HotkeyService({required this.onToggleWindow});

  final HotkeyCallback onToggleWindow;

  HotKey? _registered;

  Future<void> init() async {
    if (_registered != null) return;
    // Clean any leftovers from a prior run.
    await hotKeyManager.unregisterAll();

    // Preferred combo per-platform, with a fallback if the OS rejects it
    // (e.g. another app already grabbed the global shortcut on Windows).
    final attempts = Platform.isMacOS
        ? [
            [HotKeyModifier.meta, HotKeyModifier.shift],
          ]
        : [
            [HotKeyModifier.alt, HotKeyModifier.shift],
            [HotKeyModifier.control, HotKeyModifier.alt],
            [HotKeyModifier.control, HotKeyModifier.shift],
          ];

    for (final modifiers in attempts) {
      final hk = HotKey(
        key: PhysicalKeyboardKey.keyV,
        modifiers: modifiers,
        scope: HotKeyScope.system,
      );
      try {
        await hotKeyManager.register(
          hk,
          keyDownHandler: (_) => onToggleWindow(),
        );
        _registered = hk;
        debugPrint('sclip: hotkey registered with $modifiers + V');
        return;
      } catch (e) {
        debugPrint('sclip: hotkey registration failed for $modifiers + V: $e');
      }
    }
    debugPrint('sclip: no global hotkey could be registered');
  }

  Future<void> dispose() async {
    final hk = _registered;
    if (hk != null) {
      await hotKeyManager.unregister(hk);
    }
    _registered = null;
  }
}
