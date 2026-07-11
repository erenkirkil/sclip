import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

typedef HotkeyCallback = Future<void> Function();

class HotkeyService {
  HotkeyService({required this.onToggleWindow});

  static const _windowChannel = MethodChannel('sclip/window');

  final HotkeyCallback onToggleWindow;

  HotKey? _registered;
  HotKey? get registered => _registered;

  /// Attempts to register a global toggle hotkey. Returns true when one of
  /// the attempts landed — the caller surfaces a warning banner on false,
  /// because the plugin's own register() reports success unconditionally
  /// on both platforms and would otherwise leave the user with a silently
  /// dead shortcut.
  Future<bool> init({HotKey? preferred}) async {
    if (_registered != null) return true;
    // Clean any leftovers from a prior run.
    await hotKeyManager.unregisterAll();

    // If the user has a saved preference, try it first and bail on success.
    // Fall through to the built-in attempts on failure (e.g. another app
    // has grabbed the combo since the pref was saved).
    if (preferred != null && await _tryRegister(preferred)) return true;

    // Built-in attempts: preferred per-platform combo, with fallbacks so
    // users still get something if the first choice is claimed.
    final attempts = Platform.isMacOS
        ? const [
            [HotKeyModifier.meta, HotKeyModifier.shift],
            [HotKeyModifier.meta, HotKeyModifier.alt],
            [HotKeyModifier.control, HotKeyModifier.meta],
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
      if (await _tryRegister(hk)) return true;
    }
    debugPrint('sclip: no global hotkey could be registered');
    return false;
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
    // hotkey_manager's Windows plugin discards RegisterHotKey's return
    // value and always reports success, so a combo held by another app
    // "registers" fine and just never fires. Probe availability natively
    // first — the probe registers and immediately unregisters the same
    // combo, so a probe failure means someone else holds it.
    if (Platform.isWindows && !await _isAvailableOnWindows(hk)) {
      debugPrint('sclip: hotkey taken (native probe) — ${hk.debugName}');
      return false;
    }
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

  /// MOD_ALT / MOD_CONTROL / MOD_SHIFT / MOD_WIN bit values from WinUser.h.
  static const _winModBits = {
    HotKeyModifier.alt: 0x1,
    HotKeyModifier.control: 0x2,
    HotKeyModifier.shift: 0x4,
    HotKeyModifier.meta: 0x8,
  };

  /// Best-effort Win32 virtual-key code for the combo's key. Letters and
  /// digits map directly from the key label; F-keys from their key ids.
  /// Anything else returns null and the probe is skipped (assume free) —
  /// a false "free" only degrades to today's behaviour.
  static int? _winVkFor(HotKey hk) {
    final label = hk.logicalKey.keyLabel.toUpperCase();
    if (label.length == 1) {
      final c = label.codeUnitAt(0);
      final isLetter = c >= 0x41 && c <= 0x5A;
      final isDigit = c >= 0x30 && c <= 0x39;
      if (isLetter || isDigit) return c;
    }
    const fKeyBase = 0x70; // VK_F1
    for (var i = 0; i < 12; i++) {
      if (hk.logicalKey.keyId == LogicalKeyboardKey.f1.keyId + i) {
        return fKeyBase + i;
      }
    }
    return null;
  }

  Future<bool> _isAvailableOnWindows(HotKey hk) async {
    var mods = 0;
    for (final m in hk.modifiers ?? const <HotKeyModifier>[]) {
      final bit = _winModBits[m];
      if (bit == null) return true; // unprobeable modifier — assume free
      mods |= bit;
    }
    final vk = _winVkFor(hk);
    if (mods == 0 || vk == null) return true;
    try {
      final free = await _windowChannel.invokeMethod<bool>('probeHotkey', {
        'modifiers': mods,
        'vk': vk,
      });
      return free ?? true;
    } on MissingPluginException {
      return true; // older native build — keep legacy behaviour
    } catch (e) {
      debugPrint('sclip: hotkey probe failed: $e');
      return true;
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
