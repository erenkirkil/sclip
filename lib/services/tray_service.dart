import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

typedef TrayCallback = Future<void> Function();

class TrayService with TrayListener {
  TrayService({
    required this.onToggleWindow,
    required this.onClearAll,
    required this.onTogglePin,
    required this.onOpenSettings,
    required this.onQuit,
  });

  final TrayCallback onToggleWindow;
  final TrayCallback onClearAll;
  final TrayCallback onTogglePin;
  final TrayCallback onOpenSettings;
  final TrayCallback onQuit;

  static const _iconMac = 'assets/tray/icon.png';
  static const _iconWin = 'assets/tray/icon.ico';

  bool _installed = false;
  bool _pinned = false;

  Future<void> init() async {
    if (_installed) return;
    _installed = true;

    trayManager.addListener(this);

    final iconPath = Platform.isWindows ? _iconWin : _iconMac;
    await trayManager.setIcon(iconPath, isTemplate: Platform.isMacOS);
    await trayManager.setToolTip('sclip');
    await _rebuildMenu();
  }

  Future<void> setPinned(bool value) async {
    if (_pinned == value) return;
    _pinned = value;
    await _rebuildMenu();
  }

  Future<void> _rebuildMenu() async {
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'toggle', label: 'Göster / Gizle'),
          MenuItem.separator(),
          MenuItem.checkbox(
            key: 'pin',
            label: 'Üste sabitle',
            checked: _pinned,
          ),
          MenuItem.separator(),
          MenuItem(key: 'clear', label: 'Hepsini Sil'),
          MenuItem.separator(),
          MenuItem(key: 'settings', label: 'Ayarlar…'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Çıkış'),
        ],
      ),
    );
  }

  Future<void> dispose() async {
    if (!_installed) return;
    trayManager.removeListener(this);
    await trayManager.destroy();
    _installed = false;
  }

  /// Tray listener callbacks are synchronous, so the async app callbacks
  /// are explicitly fire-and-forget — with the error logged instead of
  /// vanishing into an unhandled-async-exception.
  void _dispatch(TrayCallback cb) {
    unawaited(
      cb().catchError((Object e) {
        debugPrint('sclip: tray callback failed: $e');
      }),
    );
  }

  @override
  void onTrayIconMouseDown() {
    _dispatch(onToggleWindow);
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'toggle':
        _dispatch(onToggleWindow);
        break;
      case 'pin':
        _dispatch(onTogglePin);
        break;
      case 'clear':
        _dispatch(onClearAll);
        break;
      case 'settings':
        _dispatch(onOpenSettings);
        break;
      case 'quit':
        _dispatch(onQuit);
        break;
    }
  }
}
