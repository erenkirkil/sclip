import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../services/settings_service.dart';

/// Observable mirror of [SettingsService]. Widgets listen here instead of
/// reading SharedPreferences directly — every setter writes through to
/// disk *and* notifies listeners so the rest of the app (theme, history
/// cap, polling interval, hotkey) reacts instantly without a restart.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._service)
      : _themeMode = _service.themeMode,
        _maxItems = _service.maxItems,
        _sensitiveFilterEnabled = _service.sensitiveFilterEnabled,
        _autoHideOnBlur = _service.autoHideOnBlur,
        _alwaysOnTopDefault = _service.alwaysOnTopDefault,
        _pollingIntervalMs = _service.pollingIntervalMs,
        _clearOnStartup = _service.clearOnStartup,
        _toggleHotkey =
            _service.toggleHotkey ?? SettingsService.defaultToggleHotkey();

  final SettingsService _service;

  ThemeMode _themeMode;
  int _maxItems;
  bool _sensitiveFilterEnabled;
  bool _autoHideOnBlur;
  bool _alwaysOnTopDefault;
  int _pollingIntervalMs;
  bool _clearOnStartup;
  HotKey _toggleHotkey;

  ThemeMode get themeMode => _themeMode;
  int get maxItems => _maxItems;
  bool get sensitiveFilterEnabled => _sensitiveFilterEnabled;
  bool get autoHideOnBlur => _autoHideOnBlur;
  bool get alwaysOnTopDefault => _alwaysOnTopDefault;
  Duration get pollingInterval => Duration(milliseconds: _pollingIntervalMs);
  int get pollingIntervalMs => _pollingIntervalMs;
  bool get clearOnStartup => _clearOnStartup;
  HotKey get toggleHotkey => _toggleHotkey;

  static const allowedMaxItems = [10, 30, 50, 100];
  static const allowedPollingMs = [250, 500, 1000];

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await _service.setThemeMode(mode);
    notifyListeners();
  }

  Future<void> setMaxItems(int value) async {
    if (!allowedMaxItems.contains(value) || _maxItems == value) return;
    _maxItems = value;
    await _service.setMaxItems(value);
    notifyListeners();
  }

  Future<void> setSensitiveFilterEnabled(bool v) async {
    if (_sensitiveFilterEnabled == v) return;
    _sensitiveFilterEnabled = v;
    await _service.setSensitiveFilterEnabled(v);
    notifyListeners();
  }

  Future<void> setAutoHideOnBlur(bool v) async {
    if (_autoHideOnBlur == v) return;
    _autoHideOnBlur = v;
    await _service.setAutoHideOnBlur(v);
    notifyListeners();
  }

  Future<void> setAlwaysOnTopDefault(bool v) async {
    if (_alwaysOnTopDefault == v) return;
    _alwaysOnTopDefault = v;
    await _service.setAlwaysOnTopDefault(v);
    notifyListeners();
  }

  Future<void> setPollingIntervalMs(int ms) async {
    if (!allowedPollingMs.contains(ms) || _pollingIntervalMs == ms) return;
    _pollingIntervalMs = ms;
    await _service.setPollingIntervalMs(ms);
    notifyListeners();
  }

  Future<void> setClearOnStartup(bool v) async {
    if (_clearOnStartup == v) return;
    _clearOnStartup = v;
    await _service.setClearOnStartup(v);
    notifyListeners();
  }

  Future<void> setToggleHotkey(HotKey hotkey) async {
    _toggleHotkey = hotkey;
    await _service.setToggleHotkey(hotkey);
    notifyListeners();
  }

  Future<void> resetAll() async {
    await _service.resetAll();
    _themeMode = _service.themeMode;
    _maxItems = _service.maxItems;
    _sensitiveFilterEnabled = _service.sensitiveFilterEnabled;
    _autoHideOnBlur = _service.autoHideOnBlur;
    _alwaysOnTopDefault = _service.alwaysOnTopDefault;
    _pollingIntervalMs = _service.pollingIntervalMs;
    _clearOnStartup = _service.clearOnStartup;
    _toggleHotkey = SettingsService.defaultToggleHotkey();
    notifyListeners();
  }
}
