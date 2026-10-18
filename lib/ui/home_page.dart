import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../models/clipboard_entry.dart';
import '../providers/history_provider.dart';
import '../providers/settings_provider.dart';
import '../services/clipboard_service.dart';
import '../services/entry_filter.dart';
import '../services/hotkey_service.dart';
import '../services/tray_service.dart';
import '../services/window_positioner.dart';
import 'accessibility_banner.dart';
import 'history_list.dart';
import 'search_bar.dart';
import 'settings_page.dart';

class const HomePage({
  super.key,
  required this.settings,
  required this.navigatorKey,
}) extends StatefulWidget {
  final SettingsProvider settings;
  final GlobalKey<NavigatorState> navigatorKey;

  /// Confirmation body for "Hepsini sil". Split out from the dialog so
  /// the filter-aware wording is unit-testable without booting a window:
  /// HomePage owns its HistoryProvider internally, so a widget test can't
  /// seed a history to drive this through the UI.
  ///
  /// Deleting only what the filter shows was rejected: HistoryProvider's
  /// removeAt path fires onEvict per entry (temp-file cleanup), and a
  /// partial "clear" whose scope depends on invisible query state is a
  /// worse contract than one sentence of honesty.
  @visibleForTesting
  static String clearAllMessage({required int total, required int visible}) {
    if (visible == total) {
      return 'Tüm pano geçmişi silinecek. Emin misin?';
    }
    return 'Filtre aktif: görünen $visible değil, tümü ($total) silinecek. '
        'Emin misin?';
  }

  @override
  State<HomePage> createState() => HomePageState();
}

@visibleForTesting
class HomePageState extends State<HomePage> with WindowListener {
  static const _windowChannel = MethodChannel('sclip/window');
  static const _clipboardChannel = MethodChannel('sclip/clipboard');

  late final ClipboardService _service;
  late final HistoryProvider _history;
  late final TrayService _tray;
  late final HotkeyService _hotkey;
  final FocusNode _firstItemFocus = FocusNode(debugLabel: 'sclip-first-item');
  final FocusNode _searchFocus = FocusNode(debugLabel: 'sclip-search');
  final TextEditingController _searchController = TextEditingController();

  /// True while the query bar is mounted. It lives in this Column, above
  /// HistoryList and outside its subtree — see HistorySearchBar's doc for
  /// why that placement is load-bearing rather than cosmetic.
  bool _searchOpen = false;

  /// Live query text. Empty means "no filter".
  String _query = '';

  StreamSubscription<ClipboardEntry>? _sub;
  StreamSubscription<void>? _lockSub;
  Timer? _blurHideTimer;
  Timer? _accessibilityPollTimer;

  /// Optimistically true on first frame so the red banner never flashes at
  /// launch when Accessibility is already granted; [_checkAccessibility] flips
  /// it to false if macOS reports untrusted and polls until granted.
  bool _accessibilityOk = true;

  /// False when no global toggle hotkey could be registered at launch —
  /// the plugin masks per-combo failures, so this is the only signal the
  /// user gets that the shortcut is dead (tray still works).
  bool _hotkeyOk = true;

  /// When true, window stays on top and does not auto-hide on focus loss.
  /// Initial value mirrors the user's `alwaysOnTopDefault` preference but
  /// can be toggled at runtime from the tray without rewriting the pref.
  late bool _pinned;

  /// Tracks whether the window currently owns OS focus. When `autoHideOnBlur`
  /// is off and the user clicks outside, the window stays `isVisible == true`
  /// while losing focus (`_windowFocused == false`); the next tray "Göster /
  /// Gizle" or hotkey press should bring it back to the front instead of
  /// hiding an unfocused background window.
  bool _windowFocused = true;

  /// True while we're programmatically hiding the window, so our own
  /// show→hide bounce doesn't fire the blur-auto-hide path.
  bool _suppressBlur = false;

  /// Guards the pin sync loop: tray toggle writes to settings → settings
  /// listener would otherwise call setAlwaysOnTop again. Settings-driven
  /// flips skip the redundant call when this is true.
  bool _suppressSettingsPinSync = false;

  /// Tracks whether the Settings modal is currently on-screen. Tray /
  /// shortcut re-entries while it's open would otherwise stack multiple
  /// dialogs on top of each other, forcing the user to Esc repeatedly to
  /// unwind the pile.
  bool _settingsOpen = false;

  /// Set when the screen-lock trigger wiped the history. The clear happens
  /// behind a locked screen where a SnackBar draws into a hidden window
  /// and a semantics announcement reaches nobody, so a persistent banner
  /// on the next display is the only honest way to tell the user their
  /// history is gone on purpose rather than through a bug.
  bool _lockClearedNotice = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    _pinned = widget.settings.alwaysOnTopDefault;
    _history = HistoryProvider(maxItems: widget.settings.maxItems);
    _service = ClipboardService(
      interval: widget.settings.pollingInterval,
      sensitiveFilterEnabled: widget.settings.sensitiveFilterEnabled,
    );

    widget.settings.addListener(_onSettingsChanged);

    // Evicted/deleted entries take their materialized temp files with them
    // so pasted content doesn't sit on disk until the next launch.
    _history.onEvict = (e) => unawaited(_service.cleanupEntryTempFiles(e));

    _sub = _service.entries.listen(_history.add);
    _lockSub = _service.screenLocks.listen((_) => _onScreenLocked());
    _service.start();

    // Honour clearOnStartup before the first tick lands anything — the
    // service hasn't produced entries yet, but a user who toggles this on
    // expects a blank list at launch even if a prior session left entries
    // in the (now-gone) heap of a previous process. Routed through
    // _clearHistory so this path picks up the imageCache sweep and the
    // dedup-baseline reset too; calling _history.clear() directly skipped
    // both.
    if (widget.settings.clearOnStartup) {
      _clearHistory();
    }

    // Apply alwaysOnTopDefault to the window itself on launch.
    if (_pinned) {
      unawaited(windowManager.setAlwaysOnTop(true));
    }

    _tray = TrayService(
      onToggleWindow: _toggleWindow,
      onClearAll: () async => _clearHistory(),
      onTogglePin: _togglePin,
      onOpenSettings: _openSettings,
      onQuit: _quit,
    );
    _hotkey = HotkeyService(onToggleWindow: _toggleWindow);

    unawaited(_tray.init());
    // Pass the persisted hotkey through so restart survives user config.
    // Surface a banner when nothing could be registered — otherwise the
    // only symptom is a shortcut that silently does nothing.
    unawaited(
      _hotkey.init(preferred: widget.settings.toggleHotkey).then((ok) {
        if (!mounted || ok == _hotkeyOk) return;
        if (!ok) {
          unawaited(
            SemanticsService.sendAnnouncement(
              View.of(context),
              'Genel kısayol kaydedilemedi.',
              TextDirection.ltr,
            ),
          );
        }
        setState(() => _hotkeyOk = ok);
      }),
    );
    unawaited(_checkAccessibility());

    // Global Esc handler. CallbackShortcuts in the widget tree requires a
    // focused descendant, which isn't reliable when the window is first
    // shown via a hotkey (focus ownership can land outside the Flutter
    // engine for a frame). HardwareKeyboard fires regardless of focus.
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  int? _lastSyncedSurfaceArgb;
  Brightness? _lastSyncedBrightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final surfaceArgb =
        (theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface)
            .toARGB32();
    if (_lastSyncedBrightness == brightness &&
        _lastSyncedSurfaceArgb == surfaceArgb) {
      return;
    }
    _lastSyncedBrightness = brightness;
    _lastSyncedSurfaceArgb = surfaceArgb;
    if (Platform.isMacOS) {
      unawaited(
        _windowChannel
            .invokeMethod<void>('syncTheme', {
              'isDark': brightness == Brightness.dark,
              'argb': surfaceArgb,
            })
            .catchError((Object _) {}),
      );
    } else if (Platform.isWindows) {
      unawaited(
        windowManager.setBrightness(brightness).catchError((Object _) {}),
      );
    }
  }

  void _onSettingsChanged() {
    final s = widget.settings;
    // Propagate the observable knobs to services. These setters all
    // short-circuit when the value hasn't changed, so calling them
    // unconditionally is cheap.
    _history.maxItems = s.maxItems;
    _service.interval = s.pollingInterval;
    _service.sensitiveFilterEnabled = s.sensitiveFilterEnabled;

    // Always-on-top is dual-purpose: the pref stores the boot default, but
    // flipping it from the settings page should *also* apply to the live
    // window so the user sees the effect immediately. Tray toggle and this
    // path stay consistent by routing through _pinned + tray sync.
    if (!_suppressSettingsPinSync && _pinned != s.alwaysOnTopDefault) {
      _pinned = s.alwaysOnTopDefault;
      unawaited(windowManager.setAlwaysOnTop(_pinned));
      unawaited(_tray.setPinned(_pinned));
      if (mounted) setState(() {});
    }
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      // 1. If any modal/dialog/route is on top, pop it first.
      final nav = widget.navigatorKey.currentState;
      if (nav != null && nav.canPop()) {
        nav.pop();
        return true;
      }
      // 2. If the search bar is open, close it and return focus to the list.
      if (_searchOpen) {
        _closeSearch();
        return true;
      }
      // 3. Otherwise hide the panel and return focus to the previous app.
      unawaited(_hideAndReturnFocus());
      return true;
    }
    return false;
  }

  Future<void> _checkAccessibility() async {
    if (!Platform.isMacOS) return;
    try {
      final trusted = await _clipboardChannel.invokeMethod<bool>(
        'isAccessibilityTrusted',
      );
      if (!mounted) return;
      final ok = trusted ?? false;
      if (ok) {
        _accessibilityPollTimer?.cancel();
        _accessibilityPollTimer = null;
      } else {
        // Poll every second while untrusted so the red banner disappears the
        // instant the user flips the switch in System Settings (or as soon as
        // tccd propagates a newly-granted permission on launch).
        _accessibilityPollTimer ??= Timer.periodic(
          const Duration(seconds: 1),
          (_) => unawaited(_checkAccessibility()),
        );
      }
      if (!ok && _accessibilityOk) {
        // The banner appearing is invisible to a screen-reader user — the
        // audience most affected by broken auto-paste. Announce once on
        // the ok→broken transition (not on every re-check).
        unawaited(
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Otomatik yapıştırma için Accessibility izni gerek.',
            .ltr,
          ),
        );
      }
      if (_accessibilityOk != ok) {
        setState(() => _accessibilityOk = ok);
      }
    } on PlatformException catch (e) {
      debugPrint('sclip: accessibility probe failed: $e');
    } on MissingPluginException {
      // Channel not wired (e.g. tests) — assume fine.
    }
  }

  @override
  void dispose() {
    _blurHideTimer?.cancel();
    _accessibilityPollTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    windowManager.removeListener(this);
    widget.settings.removeListener(_onSettingsChanged);
    unawaited(_sub?.cancel());
    unawaited(_lockSub?.cancel());
    unawaited(_service.dispose());
    _history.dispose();
    unawaited(_tray.dispose());
    unawaited(_hotkey.dispose());
    _firstItemFocus.dispose();
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showAndFocusWindow() async {
    if (Platform.isMacOS) {
      try {
        await _windowChannel.invokeMethod<void>('showAndActivate');
        _windowFocused = true;
        return;
      } on MissingPluginException {
        // Fall back to window_manager in tests / older runner.
      } catch (e) {
        debugPrint('sclip: showAndActivate failed: $e');
      }
    }
    await windowManager.show();
    await windowManager.focus();
    _windowFocused = true;
  }

  @visibleForTesting
  Future<void> debugToggleWindow() => _toggleWindow();

  Future<void> _toggleWindow() async {
    // If a blur event just happened (e.g. from clicking the tray icon),
    // cancel its hide action so we can handle the toggle explicitly here
    // without a race condition.
    final wasBlurPending = _blurHideTimer?.isActive ?? false;
    _blurHideTimer?.cancel();

    final visible = await windowManager.isVisible();
    final focused = _windowFocused && await windowManager.isFocused();
    // When autoHideOnBlur is off and the user clicks outside, `visible` stays
    // true while the window drops behind other apps (`focused == false`).
    // Clicking "Göster / Gizle" in the tray menu (or pressing the hotkey) in
    // that state must bring the window to the front rather than hiding it.
    if (visible && !wasBlurPending && (focused || _pinned)) {
      await _hideAndReturnFocus();
    } else {
      // Remember who currently owns the foreground so the native paste
      // handler can verify the right target is back after our hide.
      // Windows stores the HWND for explicit SetForegroundWindow restore;
      // macOS stores the pid for a post-hide guard around CGEvent Cmd+V.
      // Both protect against landing keys in sclip itself or in whatever
      // app the OS happens to promote next.
      try {
        await _windowChannel.invokeMethod('captureForeground');
      } on MissingPluginException {
        // Older build without the handler — paste path falls back to the
        // timing-based behaviour.
      } catch (e) {
        debugPrint('sclip: captureForeground failed: $e');
      }
      // Re-check Accessibility when showing so the banner updates if the user
      // just granted permission in System Settings.
      unawaited(_checkAccessibility());
      await _positionNearCursor();
      await _showAndFocusWindow();
      // Give the compositor a frame to settle, then park focus on the first
      // entry so a single Enter activates it (autofocus only fires on mount
      // and the widget tree is preserved across hide/show).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // An explicit user-driven show with the bar open should land in
        // the field, not on the first entry.
        if (_searchOpen) {
          _searchFocus.requestFocus();
          return;
        }
        if (_firstItemFocus.context != null) {
          _firstItemFocus.requestFocus();
        }
      });
    }
  }

  Future<void> _hideAndReturnFocus() async {
    // Every hide path funnels through here (hotkey toggle, blur auto-hide,
    // minimize, close, URL open, Esc). Dropping the query here is what makes
    // "hide, then show again" start from the full history.
    _resetSearchQuery();
    _windowFocused = false;

    // Hide instantly visually to keep UI snappy
    if (Platform.isWindows) await windowManager.setOpacity(0.0);

    // Wait for physical keys to be released before actually hiding the window.
    // If the window loses focus while a key is pressed, Flutter misses the KeyUp
    // event and the key gets permanently stuck in both HardwareKeyboard and the
    // Widget tree's Focus managers, causing the notorious "requires 2 presses" bug.
    final waitStart = DateTime.now();
    while (HardwareKeyboard.instance.logicalKeysPressed.isNotEmpty) {
      if (DateTime.now().difference(waitStart).inMilliseconds > 500) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    _suppressBlur = true;
    try {
      if (Platform.isMacOS) {
        // Hand focus back to the previously-active app (e.g. Android Studio).
        await _windowChannel.invokeMethod('hideAndDeactivate');
      } else {
        await windowManager.hide();
      }
    } finally {
      if (Platform.isWindows) await windowManager.setOpacity(1.0);
      // Clear on the next microtask — after onWindowBlur has fired.
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        _suppressBlur = false;
      });
    }
  }

  Future<void> _togglePin() async {
    final next = !_pinned;
    setState(() => _pinned = next);
    await windowManager.setAlwaysOnTop(next);
    await _tray.setPinned(next);
    // Keep settings + tray in sync: flipping pin from the tray should also
    // update the persisted pref so the Settings dialog reflects reality and
    // the next launch honours the user's latest choice. The provider
    // no-ops when the value hasn't changed, so calling unconditionally is
    // cheap. Mark a guard so our own settings listener doesn't race us
    // back through setAlwaysOnTop / setPinned.
    _suppressSettingsPinSync = true;
    try {
      await widget.settings.setAlwaysOnTopDefault(next);
    } finally {
      _suppressSettingsPinSync = false;
    }
  }

  /// Cmd/Ctrl+F and the AppBar's search button. Focus is requested in a
  /// post-frame callback rather than via `autofocus:` on the field: the
  /// first tile also autofocuses, and two autofocus requests racing inside
  /// one frame resolve in FocusManager's arbitrary order.
  void _openSearch() {
    if (!_searchOpen) {
      setState(() => _searchOpen = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
      // Re-pressing the shortcut mid-search should let the user retype
      // instead of appending to what's already there.
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
    });
  }

  /// Esc / the bar's X: drop the query, unmount the bar, hand the keyboard
  /// back to the list so arrow navigation resumes immediately.
  void _closeSearch() {
    if (!_searchOpen) return;
    _searchController.clear();
    setState(() {
      _searchOpen = false;
      _query = '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusList();
    });
  }

  /// Parks focus on the first *visible* entry. HistoryList hands
  /// [_firstItemFocus] to index 0 of the filtered list, so this lands on
  /// the first search result, not on the first entry of the raw history.
  /// No-op when nothing is rendered (empty history, zero results) — the
  /// node has no context to attach to then.
  void _focusList() {
    if (_firstItemFocus.context != null) {
      _firstItemFocus.requestFocus();
    }
  }

  void _focusSearchField() {
    if (!_searchOpen) return;
    _searchFocus.requestFocus();
  }

  /// Enter in the query field: activate the first result. Same path as
  /// tapping the top tile, so writeBack + touch + hide all behave
  /// identically.
  void _submitSearch() {
    final results = filterEntries(_history.entries, _query);
    if (results.isEmpty) return;
    unawaited(_onEntryTap(results.first));
  }

  /// Drops the query on every hide. The bar itself deliberately stays
  /// open: a user who reopens with the hotkey mid-search expects to land
  /// back in the field, just with a clean slate. Closing the bar is Esc's
  /// job, not the window's.
  void _resetSearchQuery() {
    if (_query.isEmpty && _searchController.text.isEmpty) return;
    _searchController.clear();
    if (!mounted) {
      _query = '';
      return;
    }
    setState(() => _query = '');
  }

  Future<void> _openSettings() async {
    // Re-entry while the settings page is already on screen would stack
    // another copy on top — Tray clicks don't know the app's UI state.
    // Lock _settingsOpen up front before any await so rapid double-triggers
    // can't slip through the isVisible/show/focus window.
    if (_settingsOpen) {
      await _showAndFocusWindow();
      return;
    }
    _settingsOpen = true;
    try {
      // Settings is shown from a hotkey/tray click, so the window might not
      // currently be visible or might be sitting unfocused behind another app.
      await _showAndFocusWindow();
      if (!mounted) return;

      await SettingsPage.show(
        context,
        settings: widget.settings,
        onHotkeyChange: (hk) async {
          final ok = await _hotkey.reregister(hk);
          if (ok) {
            await widget.settings.setToggleHotkey(hk);
          }
          return ok;
        },
      );
    } finally {
      _settingsOpen = false;
    }
  }

  Future<void> _positionNearCursor() async {
    try {
      final layout = await queryScreenLayout(_windowChannel);
      if (layout == null) return;
      final display = displayContaining(layout.cursor, layout.displays);
      if (display == null) return;
      final bounds = display.visible;
      final scale = Platform.isWindows ? display.scaleFactor : 1.0;
      final size = await windowManager.getSize();
      final physicalSize = Size(size.width * scale, size.height * scale);

      // Align top-center of window slightly below cursor so it doesn't
      // cover the click point, clamped to the visible screen.
      // Cursor and bounds are returned in physical pixels on Windows.
      final desiredPhysical = Offset(
        layout.cursor.dx - physicalSize.width / 2,
        layout.cursor.dy + (12 * scale),
      );

      final clampedPhysical = clampInto(desiredPhysical, physicalSize, bounds);
      final logicalPosition = Platform.isWindows
          ? Offset(clampedPhysical.dx / scale, clampedPhysical.dy / scale)
          : clampedPhysical;

      await windowManager.setPosition(logicalPosition);
    } catch (e) {
      // Fall back to current position on any platform hiccup (e.g. cursor
      // on a disconnected monitor, permission races on first launch).
      debugPrint('sclip: positionNearCursor failed: $e');
    }
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final scheme = Theme.of(context).colorScheme;
    final total = _history.length;
    final visible = filterEntries(_history.entries, _query).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Geçmişi sil', style: TextStyle(fontSize: 13)),
        content: Text(
          HomePage.clearAllMessage(total: total, visible: visible),
          style: const TextStyle(fontSize: 11.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hepsini sil'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _clearHistory();
    }
  }

  /// Edge-triggered by [ClipboardService.screenLocks]: fires once per
  /// unlocked→locked transition, so an hour-long lock clears the history
  /// exactly once instead of on every 500 ms tick.
  ///
  /// Two things are deliberately left alone:
  ///
  ///   * **The OS clipboard.** The last copied item stays on it, so
  ///     Cmd/Ctrl+V keeps working the moment the user unlocks. Emptying it
  ///     would break the user's own workflow, not an attacker's.
  ///   * **The materialized temp files.** The clipboard may still
  ///     reference them by file URI (that is exactly what the guard in
  ///     ClipboardService.cleanupEntryTempFiles exists for) — sweeping
  ///     them would turn the first paste after unlock into an empty one.
  ///
  /// Together those two limits make this a RAM cleanup, not a privacy
  /// guarantee; docs/security.md says so in the same words.
  void _onScreenLocked() {
    if (!widget.settings.clearOnScreenLock) return;
    if (_history.isEmpty) return;
    _clearHistory();
    if (mounted) setState(() => _lockClearedNotice = true);
  }

  /// The single clear path: startup (clearOnStartup), tray "Hepsini Sil",
  /// the confirm dialog and the screen-lock trigger all land here. Drops
  /// the decoded bitmaps Flutter's image cache retained for the thumbnails
  /// — "clear history" should actually release the memory, not just the
  /// raw bytes — and resets the service's dedup baseline so re-copying
  /// something that was just deleted isn't silently swallowed.
  void _clearHistory() {
    _history.clear();
    // Görev 3 / B-01: the dedup baseline still fingerprinted the history
    // we just dropped. Do not remove this line.
    _service.resetBaseline();
    PaintingBinding.instance.imageCache.clear();
    // An emptied history under a live query would render "'x' için sonuç
    // yok" instead of the real "history is empty" state. Dropping the
    // query keeps the empty state honest on both the AppBar path and the
    // tray's unconfirmed "Hepsini Sil".
    _resetSearchQuery();
  }

  Future<void> _quit() async {
    // destroy() kills the process without running State.dispose, so sweep
    // the service (and its materialized temp files) explicitly here —
    // otherwise pasted content would linger on disk until the next launch.
    await _service.dispose();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<void> _onEntryOpen(ClipboardEntry entry) async {
    final uri = entry.uris?.firstOrNull;
    if (uri == null) return;
    await _hideAndReturnFocus();
    await launchUrl(uri, mode: .externalApplication);
  }

  Future<void> _onEntryTap(
    ClipboardEntry entry, {
    int? imageIndex,
    bool plainOnly = false,
  }) async {
    await _service.writeBack(
      entry,
      imageIndex: imageIndex,
      plainOnly: plainOnly,
    );
    // Re-using an existing entry should bump it to the top with a fresh
    // timestamp — touch() keeps the id stable so widget keys don't churn
    // and the "just now" label reflects the latest action.
    _history.touch(entry.id);
    // The native paste path below hides the window via `pasteToPrevious`
    // and never reaches _hideAndReturnFocus, so the query has to be
    // dropped here too.
    _resetSearchQuery();
    _windowFocused = false;

    if (Platform.isWindows) {
      // Hide instantly visually to keep UI snappy
      await windowManager.setOpacity(0.0);
    }

    // Wait for Enter to be released so it doesn't get stuck in Flutter's state
    // (which causes the 2-press bug) and doesn't interfere with Ctrl+V/Cmd+V.
    final waitStart = DateTime.now();
    while (HardwareKeyboard.instance.logicalKeysPressed.isNotEmpty) {
      if (DateTime.now().difference(waitStart).inMilliseconds > 500) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    if (Platform.isWindows) {
      await windowManager.hide();
      await windowManager.setOpacity(1.0);
    }
    try {
      await _windowChannel.invokeMethod('pasteToPrevious');
    } on MissingPluginException {
      // Platform without a paste handler — fall back to plain hide.
      await _hideAndReturnFocus();
    }
  }

  @override
  void onWindowClose() async {
    final preventClose = await windowManager.isPreventClose();
    if (preventClose) {
      await _hideAndReturnFocus();
    }
  }

  @override
  void onWindowMinimize() {
    // Windows: the window is skip-taskbar, so a minimized sclip has no
    // taskbar button to restore from and parks as a floating title strip;
    // worse, IsWindowVisible stays TRUE while minimized so the next hotkey
    // press takes the hide branch. Redirect minimize to the same
    // hide-to-tray behaviour as close. macOS handles Cmd+M restore via
    // show()'s makeKeyAndOrderFront, but the consistent behaviour is
    // desirable there too.
    unawaited(_hideAndReturnFocus());
  }

  @override
  void onWindowFocus() {
    _windowFocused = true;
    unawaited(HardwareKeyboard.instance.syncKeyboardState());
    unawaited(_checkAccessibility());

    // Reassert focus on the top entry — when the window is reshown after a
    // paste, OS focus sometimes arrives before our postFrameCallback from
    // _toggleWindow runs (or we were shown via a path that doesn't go
    // through _toggleWindow, like the system unhiding us). Requesting here
    // guarantees arrow keys have a primary focus to navigate from.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Unlike _toggleWindow this fires on shows we didn't initiate (OS
      // unhide, alt-tab back). Stealing focus out of a field the user is
      // typing in would eat keystrokes, so bail unconditionally.
      if (_searchOpen) return;
      if (_firstItemFocus.context != null &&
          FocusManager.instance.primaryFocus != _firstItemFocus) {
        _firstItemFocus.requestFocus();
      }
    });
  }

  @override
  void onWindowBlur() {
    _windowFocused = false;
    // Auto-hide when user clicks away — unless the user has pinned the
    // window or turned the behaviour off entirely in settings.
    // _suppressBlur guards against our own hide path, which also fires
    // blur on macOS.
    if (_pinned || _suppressBlur || !widget.settings.autoHideOnBlur) return;

    // Delay hide by 150ms to allow `onTrayIconMouseDown` to cancel it.
    // Without this, clicking the tray icon while the window is focused triggers
    // an immediate blur (hiding the window) which races with the tray's own
    // toggle command.
    _blurHideTimer?.cancel();
    _blurHideTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) unawaited(_hideAndReturnFocus());
    });
  }

  Future<void> _openAccessibilitySettings() async {
    try {
      await _clipboardChannel.invokeMethod('openAccessibilitySettings');
    } on MissingPluginException {
      // Not wired on this platform — banner shouldn't be visible anyway.
    } catch (e) {
      debugPrint('sclip: open accessibility settings failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const actionConstraints = BoxConstraints(minWidth: 24, minHeight: 24);
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.comma, meta: true):
            const _OpenSettingsIntent(),
        const SingleActivator(LogicalKeyboardKey.comma, control: true):
            const _OpenSettingsIntent(),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            const _OpenSearchIntent(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            const _OpenSearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _OpenSettingsIntent: CallbackAction<_OpenSettingsIntent>(
            onInvoke: (_) {
              unawaited(_openSettings());
              return null;
            },
          ),
          _OpenSearchIntent: CallbackAction<_OpenSearchIntent>(
            onInvoke: (_) {
              _openSearch();
              return null;
            },
          ),
        },
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: 28,
            titleSpacing: 4,
            title: Image.asset(
              'assets/branding/logo.png',
              height: 14,
              cacheHeight: (14 * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              fit: .contain,
              filterQuality: .medium,
              semanticLabel: 'sclip',
            ),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: 'Ara',
                iconSize: 15,
                padding: .zero,
                constraints: actionConstraints,
                icon: const Icon(Icons.search),
                onPressed: _openSearch,
              ),
              ListenableBuilder(
                listenable: _history,
                builder: (context, _) => IconButton(
                  tooltip: 'Hepsini sil',
                  iconSize: 15,
                  padding: .zero,
                  constraints: actionConstraints,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: _history.isEmpty
                      ? null
                      : () => _confirmClearAll(context),
                ),
              ),
              IconButton(
                tooltip: 'Ayarlar',
                iconSize: 15,
                padding: .zero,
                constraints: actionConstraints,
                icon: const Icon(Icons.settings_outlined),
                onPressed: _openSettings,
              ),
              const SizedBox(width: 2),
            ],
          ),
          body: Column(
            children: [
              if (!_accessibilityOk)
                AccessibilityBanner(onTap: _openAccessibilitySettings),
              if (!_hotkeyOk)
                WarningBanner(
                  icon: Icons.keyboard_outlined,
                  message: 'Genel kısayol kaydedilemedi.',
                  actionLabel: 'Ayarlar\'dan değiştir',
                  onTap: _openSettings,
                ),
              // Görev 21 / Faz 4 — ekran kilidi geri bildirimi. Do not drop.
              if (_lockClearedNotice)
                WarningBanner(
                  icon: Icons.lock_clock_outlined,
                  message: 'Ekran kilidinde geçmiş temizlendi',
                  actionLabel: 'Tamam',
                  onTap: () => setState(() => _lockClearedNotice = false),
                ),
              if (_searchOpen)
                HistorySearchBar(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: (value) => setState(() => _query = value),
                  onSubmit: _submitSearch,
                  onClose: _closeSearch,
                  onDownToList: _focusList,
                ),
              Expanded(
                child: HistoryList(
                  provider: _history,
                  query: _query,
                  onEntryTap: _onEntryTap,
                  onEntryOpen: _onEntryOpen,
                  firstItemFocusNode: _firstItemFocus,
                  onArrowUpAtTop: _searchOpen ? _focusSearchField : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _OpenSettingsIntent() extends Intent;

class const _OpenSearchIntent() extends Intent;
