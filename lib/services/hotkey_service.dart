import 'dart:io';

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

    final modifiers = Platform.isMacOS
        ? [HotKeyModifier.meta, HotKeyModifier.shift]
        : [HotKeyModifier.control, HotKeyModifier.shift];

    final hk = HotKey(
      key: PhysicalKeyboardKey.keyV,
      modifiers: modifiers,
      scope: HotKeyScope.system,
    );

    await hotKeyManager.register(
      hk,
      keyDownHandler: (_) => onToggleWindow(),
    );
    _registered = hk;
  }

  Future<void> dispose() async {
    final hk = _registered;
    if (hk != null) {
      await hotKeyManager.unregister(hk);
    }
    _registered = null;
  }
}
