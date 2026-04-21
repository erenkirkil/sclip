import 'dart:io';

import 'package:tray_manager/tray_manager.dart';

typedef TrayCallback = Future<void> Function();

class TrayService with TrayListener {
  TrayService({
    required this.onToggleWindow,
    required this.onClearAll,
    required this.onQuit,
  });

  final TrayCallback onToggleWindow;
  final TrayCallback onClearAll;
  final TrayCallback onQuit;

  static const _iconMac = 'assets/tray/icon.png';
  static const _iconWin = 'assets/tray/icon.ico';

  bool _installed = false;

  Future<void> init() async {
    if (_installed) return;
    _installed = true;

    trayManager.addListener(this);

    final iconPath = Platform.isWindows ? _iconWin : _iconMac;
    await trayManager.setIcon(iconPath, isTemplate: Platform.isMacOS);
    await trayManager.setToolTip('sclip');
    await _rebuildMenu();
  }

  Future<void> _rebuildMenu() async {
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'toggle', label: 'Göster / Gizle'),
      MenuItem.separator(),
      MenuItem(key: 'clear', label: 'Hepsini Sil'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Çıkış'),
    ]));
  }

  Future<void> dispose() async {
    if (!_installed) return;
    trayManager.removeListener(this);
    await trayManager.destroy();
    _installed = false;
  }

  @override
  void onTrayIconMouseDown() {
    onToggleWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'toggle':
        onToggleWindow();
        break;
      case 'clear':
        onClearAll();
        break;
      case 'quit':
        onQuit();
        break;
    }
  }
}
