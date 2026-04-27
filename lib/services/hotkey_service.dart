import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

typedef HotkeyCallback = Future<void> Function();

class HotkeyService {
  HotkeyService({required this.onToggleWindow});

  final HotkeyCallback onToggleWindow;

  HotKey? _registered;
  HotKey? get registered => _registered;

  Future<void> init({HotKey? preferred}) async {
    if (_registered != null) return;
    // Clean any leftovers from a prior run.
    await hotKeyManager.unregisterAll();

    // If the user has a saved preference, try it first and bail on success.
    // Fall through to the built-in attempts on failure (e.g. another app
    // has grabbed the combo since the pref was saved).
    if (preferred != null && await _tryRegister(preferred)) return;

    // Built-in attempts: preferred per-platform combo, with fallbacks so
    // Windows users still get something if Alt+Shift+V is claimed.
    final attempts = Platform.isMacOS
        ? const [
            [HotKeyModifier.meta, HotKeyModifier.shift],
          ]
        : const [
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
      if (await _tryRegister(hk)) return;
    }
    debugPrint('sclip: no global hotkey could be registered');
  }

  /// Swaps the active global hotkey. Unregisters the old one, registers
  /// [next]. Returns true on success — on failure the previous binding is
  /// left intact so the user isn't stranded without a toggle. The settings
  /// page uses the return value to surface an error in the UI.
  Future<bool> reregister(HotKey next) async {
    final previous = _registered;
    if (previous != null) {
      try {
        await hotKeyManager.unregister(previous);
      } catch (e) {
        debugPrint('sclip: unregister previous hotkey failed: $e');
      }
      _registered = null;
    }
    if (await _tryRegister(next)) return true;
    // Roll back so the user keeps a working hotkey.
    if (previous != null) {
      await _tryRegister(previous);
    }
    return false;
  }

  Future<bool> _tryRegister(HotKey hk) async {
    try {
      await hotKeyManager.register(hk, keyDownHandler: (_) => onToggleWindow());
      _registered = hk;
      debugPrint('sclip: hotkey registered — ${hk.debugName}');
      return true;
    } catch (e) {
      debugPrint('sclip: hotkey register failed for ${hk.debugName}: $e');
      return false;
    }
  }

  Future<void> dispose() async {
    final hk = _registered;
    if (hk != null) {
      await hotKeyManager.unregister(hk);
    }
    _registered = null;
  }
}
