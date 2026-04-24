import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin typed wrapper over [SharedPreferences] restricted to user-preference
/// scalars. Clipboard history is **never** written here — the key namespace
/// and the API surface together enforce that boundary: callers can only set
/// known scalar fields, and [prefix] filters eviction/reset to our own keys.
///
/// macOS backs this with `NSUserDefaults` (plist under
/// `~/Library/Preferences`); Windows with a JSON file under `%APPDATA%`.
/// Neither receives `ClipboardEntry` content under any code path — the
/// regression test in `test/settings_service_test.dart` asserts this.
class SettingsService {
  SettingsService(this._prefs);

  static const prefix = 'sclip.settings.';

  static const _kThemeMode = '${prefix}themeMode';
  static const _kMaxItems = '${prefix}maxItems';
  static const _kSensitiveFilter = '${prefix}sensitiveFilter';
  static const _kAutoHideOnBlur = '${prefix}autoHideOnBlur';
  static const _kAlwaysOnTop = '${prefix}alwaysOnTopDefault';
  static const _kPollingMs = '${prefix}pollingIntervalMs';
  static const _kClearOnStartup = '${prefix}clearOnStartup';
  static const _kHotkey = '${prefix}toggleHotkey';

  final SharedPreferences _prefs;

  static Future<SettingsService> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  // ThemeMode stored as enum name (`system` / `light` / `dark`). Unknown
  // values fall back to system so a future schema downgrade doesn't crash.
  ThemeMode get themeMode {
    switch (_prefs.getString(_kThemeMode)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      case null:
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString(_kThemeMode, mode.name);

  int get maxItems => _prefs.getInt(_kMaxItems) ?? 30;
  Future<void> setMaxItems(int value) => _prefs.setInt(_kMaxItems, value);

  bool get sensitiveFilterEnabled => _prefs.getBool(_kSensitiveFilter) ?? true;
  Future<void> setSensitiveFilterEnabled(bool v) =>
      _prefs.setBool(_kSensitiveFilter, v);

  bool get autoHideOnBlur => _prefs.getBool(_kAutoHideOnBlur) ?? true;
  Future<void> setAutoHideOnBlur(bool v) =>
      _prefs.setBool(_kAutoHideOnBlur, v);

  bool get alwaysOnTopDefault => _prefs.getBool(_kAlwaysOnTop) ?? false;
  Future<void> setAlwaysOnTopDefault(bool v) =>
      _prefs.setBool(_kAlwaysOnTop, v);

  int get pollingIntervalMs => _prefs.getInt(_kPollingMs) ?? 500;
  Future<void> setPollingIntervalMs(int ms) =>
      _prefs.setInt(_kPollingMs, ms);

  bool get clearOnStartup => _prefs.getBool(_kClearOnStartup) ?? false;
  Future<void> setClearOnStartup(bool v) =>
      _prefs.setBool(_kClearOnStartup, v);

  HotKey? get toggleHotkey {
    final raw = _prefs.getString(_kHotkey);
    if (raw == null) return null;
    try {
      return HotKey.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('sclip: toggleHotkey parse failed, using default: $e');
      return null;
    }
  }

  Future<void> setToggleHotkey(HotKey hotkey) =>
      _prefs.setString(_kHotkey, jsonEncode(hotkey.toJson()));

  /// Wipes every sclip setting back to defaults. Only keys under [prefix]
  /// are touched — we don't know what else SharedPreferences might be
  /// holding on behalf of platform plugins, and stomping those is rude.
  Future<void> resetAll() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      await _prefs.remove(k);
    }
  }

  /// Default hotkey — platform-specific, matches the original hard-coded
  /// registration in [HotkeyService]. Exposed so UI can preview the default
  /// in the recorder without having to reimplement the platform switch.
  static HotKey defaultToggleHotkey() {
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    return HotKey(
      key: PhysicalKeyboardKey.keyV,
      modifiers: isMac
          ? const [HotKeyModifier.meta, HotKeyModifier.shift]
          : const [HotKeyModifier.alt, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );
  }
}
