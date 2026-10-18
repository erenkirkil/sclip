import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

typedef TrayCallback = Future<void> Function();

class TrayService({
  required this.onToggleWindow,
  required this.onClearAll,
  required this.onTogglePin,
  required this.onOpenSettings,
  required this.onQuit,
}) {
  final TrayCallback onToggleWindow;
  final TrayCallback onClearAll;
  final TrayCallback onTogglePin;
  final TrayCallback onOpenSettings;
  final TrayCallback onQuit;

  static const _iconMac = 'assets/tray/icon.png';
  static const _iconWin = 'assets/tray/icon.ico';

  TrayIcon? _trayIcon;
  Image? _icon;
  Menu? _menu;
  MenuItem? _pinItem;
  final List<(MenuItem, ListenerId)> _itemListeners = [];
  ListenerId? _trayListenerId;

  bool _installed = false;
  bool _pinned = false;

  Future<void> init() async {
    if (_installed) return;

    final trayIcon = TrayIcon.create();
    if (trayIcon == null) {
      debugPrint('sclip: unable to create native tray icon');
      return;
    }

    final iconPath = Platform.isWindows ? _iconWin : _iconMac;
    final icon = ImageAsset.fromAsset(iconPath) ?? Image.fromFile(iconPath);
    if (icon != null) {
      trayIcon
        ..isIconTemplate = Platform.isMacOS
        ..icon = icon;
      _icon = icon;
    }

    trayIcon.setTooltip('sclip');
    _trayIcon = trayIcon;
    _installed = true;

    _buildMenu(trayIcon);
    _trayListenerId = trayIcon.addListener(_onTrayEvent);
    trayIcon.setVisible(true);
  }

  Future<void> setPinned(bool value) async {
    if (_pinned == value) return;
    _pinned = value;
    _pinItem?.state = _pinnedState;
  }

  MenuItemState get _pinnedState => _pinned ? .checked : .unchecked;

  void _buildMenu(TrayIcon trayIcon) {
    final menu = Menu.create();
    if (menu == null) return;

    void addAction(
      String label,
      TrayCallback cb, {
      MenuItemType type = .normal,
      bool isPinItem = false,
    }) {
      final item = MenuItem.createWithLabelAndType(label, type);
      if (item == null) return;
      if (isPinItem) {
        item.state = _pinnedState;
        _pinItem = item;
      }
      final listenerId = item.addListener((event) {
        if (event is! MenuItemClickedEvent) return;
        _dispatch(cb);
        // Native platforms may auto-toggle a checkbox item on click;
        // enforce our controlled state until setPinned updates it.
        if (isPinItem) {
          item.state = _pinnedState;
        }
      });
      _itemListeners.add((item, listenerId));
      menu.addItem(item);
    }

    addAction('Göster / Gizle', onToggleWindow);
    menu.addSeparator();
    addAction('Üste sabitle', onTogglePin, type: .checkbox, isPinItem: true);
    menu.addSeparator();
    addAction('Hepsini Sil', onClearAll);
    menu.addSeparator();
    addAction('Ayarlar…', onOpenSettings);
    menu.addSeparator();
    addAction('Çıkış', onQuit);

    trayIcon.setContextMenu(menu);
    _menu = menu;
  }

  Future<void> dispose() async {
    if (!_installed) return;
    final trayIcon = _trayIcon;
    final trayListenerId = _trayListenerId;
    if (trayIcon != null && trayListenerId != null) {
      trayIcon.removeListener(trayListenerId);
    }
    _trayListenerId = null;

    for (final (item, listenerId) in _itemListeners) {
      item.removeListener(listenerId);
      item.dispose();
    }
    _itemListeners.clear();
    _pinItem = null;

    _menu?.dispose();
    _menu = null;
    _icon?.dispose();
    _icon = null;
    trayIcon?.dispose();
    _trayIcon = null;
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

  void _onTrayEvent(TrayIconEvent event) {
    switch (event) {
      case TrayIconClickedEvent():
        if (Platform.isMacOS) {
          _trayIcon?.openContextMenu();
        } else {
          _dispatch(onToggleWindow);
        }
      case TrayIconRightClickedEvent():
        _trayIcon?.openContextMenu();
      case TrayIconDoubleClickedEvent():
        break;
    }
  }
}
