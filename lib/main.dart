import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'models/clipboard_entry.dart';
import 'providers/history_provider.dart';
import 'providers/settings_provider.dart';
import 'services/clipboard_service.dart';
import 'services/hotkey_service.dart';
import 'services/settings_service.dart';
import 'services/tray_service.dart';
import 'ui/history_list.dart';
import 'ui/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Surface the default red-screen errors to the console so we can diagnose
  // frames that flash an error widget without leaving a log trail. Debug
  // builds only — release binaries fall back to Flutter's default handler so
  // we don't leak stack traces into shipped artefacts.
  if (kDebugMode) {
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final ex = details.exception.toString();
      // Suppress HardwareKeyboard state assertions. clearState() intentionally
      // wipes the state to prevent stuck keys across window shows. Trailing
      // KeyUp events from the global shortcut or instantaneous hide will trigger
      // "key not pressed", and trailing KeyDowns might trigger "already pressed".
      if (ex.contains('HardwareKeyboard') && 
          (ex.contains('is not pressed') || ex.contains('is already pressed'))) {
        return;
      }
      debugPrint('sclip: widget error: ${details.exception}');
      if (details.stack != null) debugPrint('${details.stack}');
      prevOnError?.call(details);
    };
  }

  // Load persisted user preferences (theme, hotkey, toggles) before the
  // first frame so the app opens in the user's configured state — no
  // theme flash, no wrong hotkey briefly registered.
  final settingsService = await SettingsService.load();
  final settings = SettingsProvider(settingsService);

  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(340, 460),
    minimumSize: Size(300, 360),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.normal,
    title: 'sclip',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setPreventClose(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(SclipApp(settings: settings));
}

class SclipApp extends StatelessWidget {
  SclipApp({super.key, required this.settings});

  // Mid-green from the logo gradient (sc.svg / logo.svg, offset 0.62). Seed
  // for Material 3 — light/dark schemes derive harmonised tones from this.
  static const _brandSeed = Color(0xFF609D4F);

  final SettingsProvider settings;

  /// Exposed so the global Escape handler can pop any open modal before
  /// falling through to the window-hide behaviour. Using a key rather than
  /// context lookups keeps the handler decoupled from widget-tree state.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'sclip',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        themeMode: settings.themeMode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _brandSeed),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: _brandSeed,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: HomePage(settings: settings, navigatorKey: navigatorKey),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.settings,
    required this.navigatorKey,
  });

  final SettingsProvider settings;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WindowListener {
  static const _windowChannel = MethodChannel('sclip/window');
  static const _clipboardChannel = MethodChannel('sclip/clipboard');

  late final ClipboardService _service;
  late final HistoryProvider _history;
  late final TrayService _tray;
  late final HotkeyService _hotkey;
  final FocusNode _firstItemFocus = FocusNode(debugLabel: 'sclip-first-item');
  StreamSubscription<ClipboardEntry>? _sub;
  Timer? _blurHideTimer;

  /// True once we've confirmed macOS Accessibility is granted (or we're on a
  /// platform where it doesn't apply). While false on macOS, the paste-to-
  /// previous path silently fails, so we surface a one-time banner.
  bool _accessibilityOk = !Platform.isMacOS;

  /// When true, window stays on top and does not auto-hide on focus loss.
  /// Initial value mirrors the user's `alwaysOnTopDefault` preference but
  /// can be toggled at runtime from the tray without rewriting the pref.
  late bool _pinned;

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

    _sub = _service.entries.listen(_history.add);
    _service.start();

    // Honour clearOnStartup before the first tick lands anything — the
    // service hasn't produced entries yet, but a user who toggles this on
    // expects a blank list at launch even if a prior session left entries
    // in the (now-gone) heap of a previous process. The clear() is
    // effectively a no-op today; we keep it explicit so the intent is
    // preserved when session-restore lands in a future sprint.
    if (widget.settings.clearOnStartup) {
      _history.clear();
    }

    // Apply alwaysOnTopDefault to the window itself on launch.
    if (_pinned) {
      unawaited(windowManager.setAlwaysOnTop(true));
    }

    _tray = TrayService(
      onToggleWindow: _toggleWindow,
      onClearAll: () async => _history.clear(),
      onTogglePin: _togglePin,
      onOpenSettings: _openSettings,
      onQuit: _quit,
    );
    _hotkey = HotkeyService(onToggleWindow: _toggleWindow);

    _tray.init();
    // Pass the persisted hotkey through so restart survives user config.
    _hotkey.init(preferred: widget.settings.toggleHotkey);
    _checkAccessibility();

    // Global Esc handler. CallbackShortcuts in the widget tree requires a
    // focused descendant, which isn't reliable when the window is first
    // shown via a hotkey (focus ownership can land outside the Flutter
    // engine for a frame). HardwareKeyboard fires regardless of focus.
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
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
      // If any modal/dialog is on top, pop it first. We no longer hide the
      // window itself via Esc — users rely on the global hotkey to toggle.
      final nav = widget.navigatorKey.currentState;
      if (nav != null && nav.canPop()) {
        nav.pop();
        return true;
      }
      return false;
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
      setState(() => _accessibilityOk = trusted ?? false);
    } on PlatformException catch (e) {
      debugPrint('sclip: accessibility probe failed: $e');
    } on MissingPluginException {
      // Channel not wired (e.g. tests) — assume fine.
    }
  }

  @override
  void dispose() {
    _blurHideTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    windowManager.removeListener(this);
    widget.settings.removeListener(_onSettingsChanged);
    _sub?.cancel();
    _service.dispose();
    _history.dispose();
    _tray.dispose();
    _hotkey.dispose();
    _firstItemFocus.dispose();
    super.dispose();
  }

  Future<void> _toggleWindow() async {
    // If a blur event just happened (e.g. from clicking the tray icon), 
    // cancel its hide action so we can handle the toggle explicitly here 
    // without a race condition.
    final wasBlurPending = _blurHideTimer?.isActive ?? false;
    _blurHideTimer?.cancel();

    final visible = await windowManager.isVisible();
    // We intentionally ignore isFocused: if the window is on screen at all
    // (e.g. opened via tray click and now lives in the background), pressing
    // the hotkey should hide it rather than fight its focus state.
    if (visible && !wasBlurPending) {
      await _hideAndReturnFocus();
    } else {
      // Remember who currently owns the foreground so the native paste
      // handler can restore it precisely instead of racing with whatever
      // Windows decides to focus next. macOS handles this deterministically
      // via NSApp.hide, no capture needed there.
      if (Platform.isWindows) {
        try {
          await _windowChannel.invokeMethod('captureForeground');
        } on MissingPluginException {
          // Older Windows build without the handler — paste path falls back
          // to the timing-based behaviour.
        } catch (e) {
          debugPrint('sclip: captureForeground failed: $e');
        }
      }
      await _positionNearCursor();
      await windowManager.show();
      await windowManager.focus();
      // Re-check Accessibility on every show so the banner disappears the
      // moment the user grants permission, without requiring an app restart.
      unawaited(_checkAccessibility());
      // Give the compositor a frame to settle, then park focus on the first
      // entry so a single Enter activates it (autofocus only fires on mount
      // and the widget tree is preserved across hide/show).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_firstItemFocus.context != null) {
          _firstItemFocus.requestFocus();
        }
      });
    }
  }

  Future<void> _hideAndReturnFocus() async {
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

  /// Preferred settings window size on a roomy display — we cap at this
  /// and shrink via [_settingsSizeFor] when the host display is smaller
  /// (e.g. MacBook Air as a secondary monitor). Kept deliberately tight
  /// to preserve sclip's minimalist feel; the Settings surface fits
  /// comfortably in 440×560 with the current sections.
  static const _settingsPreferredSize = Size(440, 560);
  static const _defaultWindowSize = Size(340, 460);
  static const _defaultMinSize = Size(300, 360);

  Future<void> _openSettings() async {
    // Re-entry while the modal is already on screen would stack another
    // copy on top — Tray clicks don't know the app's UI state. Just bring
    // focus back and bail.
    if (_settingsOpen) {
      await windowManager.show();
      await windowManager.focus();
      return;
    }
    // Settings is shown from a hotkey/tray click, so the window might not
    // currently be visible. Surface it first so the modal has a frame.
    final visible = await windowManager.isVisible();
    if (!visible) {
      await windowManager.show();
      await windowManager.focus();
    }
    if (!mounted) return;

    // Snapshot the current window size/position before resizing so the
    // user's own manual layout isn't clobbered when we shrink back down.
    final previousSize = await windowManager.getSize();
    final previousPosition = await windowManager.getPosition();

    // Size the settings window to fit the display it currently lives on.
    // We look up the display by the window's current position (not the
    // cursor) — Settings is typically opened from the tiny top-right
    // tray anchor while the cursor sits elsewhere; moving to the cursor
    // would feel like a teleport. When we can't determine the display,
    // fall back to the preferred size and hope for the best.
    final layout = await _queryScreenLayout();
    final display = layout == null
        ? null
        : _displayContaining(previousPosition, layout.displays);
    final bounds = display?.visible;
    final scale = Platform.isWindows ? (display?.scaleFactor ?? 1.0) : 1.0;
    
    final settingsSize = bounds == null
        ? _settingsPreferredSize
        : _settingsSizeFor(bounds);
    final settingsMinSize = Size(
      math.min(_settingsPreferredSize.width, settingsSize.width),
      math.min(_settingsPreferredSize.height, settingsSize.height),
    );

    // Raise the minimum first so the OS can't immediately clamp the
    // new size down; then grow the window to its settings size.
    await windowManager.setMinimumSize(settingsMinSize);
    await windowManager.setSize(settingsSize);
    // Preserve the user's anchor: if they opened sclip via the tray (top-
    // right corner) and clicked Settings, the window should still hug the
    // top-right after growing — not jump to the centre of the display.
    // Clamping nudges only as much as needed to keep the bigger size
    // inside the visible bounds. Physical clamping is used on Windows.
    if (bounds != null) {
      final physicalSize = Size(settingsSize.width * scale, settingsSize.height * scale);
      final physicalPosition = Offset(previousPosition.dx * scale, previousPosition.dy * scale);
      final clampedPhysical = _clampInto(physicalPosition, physicalSize, bounds);
      final clampedLogical = Platform.isWindows 
          ? Offset(clampedPhysical.dx / scale, clampedPhysical.dy / scale)
          : clampedPhysical;

      if (clampedLogical != previousPosition) {
        await windowManager.setPosition(clampedLogical);
      }
    }
    if (!mounted) return;

    _settingsOpen = true;
    try {
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
      // Restore the minimal footprint. If the user manually resized the
      // window to something larger than the default but smaller than the
      // settings size, we treat that as intent to keep it — shrink only
      // when the window is still at the size we just grew it to.
      await windowManager.setMinimumSize(_defaultMinSize);
      final sizeNow = await windowManager.getSize();
      if (sizeNow == settingsSize) {
        final restoreSize = previousSize == settingsSize
            ? _defaultWindowSize
            : previousSize;
        await windowManager.setSize(restoreSize);
        // Position restore is deliberately conditional on "nothing else
        // moved us in the meantime". If the user cycled hide/show (e.g.
        // hid with the hotkey, re-opened via tray on another display)
        // between opening and closing settings, the current position is
        // their latest intent — teleporting back to the A-position we
        // captured at open time would feel like a screen jump. We detect
        // the no-move case via the same clamped position we set on open.
        final currentPosition = await windowManager.getPosition();
        final expectedOpenPosition = bounds == null
            ? previousPosition
            : (() {
                final physicalSize = Size(settingsSize.width * scale, settingsSize.height * scale);
                final physicalPos = Offset(previousPosition.dx * scale, previousPosition.dy * scale);
                final clampedPhysical = _clampInto(physicalPos, physicalSize, bounds);
                return Platform.isWindows 
                    ? Offset(clampedPhysical.dx / scale, clampedPhysical.dy / scale)
                    : clampedPhysical;
              })();
        final unmoved =
            (currentPosition - expectedOpenPosition).distanceSquared < 1.0;
        if (unmoved) {
          await windowManager.setPosition(previousPosition);
        }
      }
    }
  }

  /// Snapshot of the desktop: cursor position plus every display's
  /// visible rectangle, all in a single top-left flipped coordinate
  /// space. Queried from our own native channel because
  /// `screen_retriever` 0.2.0 normalises cursor Y against
  /// `min(frame.maxY)` but display Y against `primary.frame.height` —
  /// secondary is taller or sits side-by-side, so cursor-in-display
  /// containment silently fails. Falling back to `screen_retriever`
  /// when the channel isn't available keeps tests + non-desktop hosts
  /// working.
  Future<({Offset cursor, List<({Rect visible, Rect full, double scaleFactor})> displays})?>
  _queryScreenLayout() async {
    try {
      final layout = await _windowChannel.invokeMapMethod<String, dynamic>(
        'screenLayout',
      );
      if (layout != null) {
        final cursorMap = (layout['cursor'] as Map).cast<String, dynamic>();
        final cursor = Offset(
          (cursorMap['dx'] as num).toDouble(),
          (cursorMap['dy'] as num).toDouble(),
        );
        final raw = (layout['displays'] as List).cast<Map>();
        final displays = [
          for (final d in raw)
            (
              visible: Rect.fromLTWH(
                (d['x'] as num).toDouble(),
                (d['y'] as num).toDouble(),
                (d['width'] as num).toDouble(),
                (d['height'] as num).toDouble(),
              ),
              full: Rect.fromLTWH(
                (d['fullX'] as num? ?? d['x'] as num).toDouble(),
                (d['fullY'] as num? ?? d['y'] as num).toDouble(),
                (d['fullWidth'] as num? ?? d['width'] as num).toDouble(),
                (d['fullHeight'] as num? ?? d['height'] as num).toDouble(),
              ),
              scaleFactor: (d['scaleFactor'] as num? ?? 1.0).toDouble(),
            ),
        ];
        return (cursor: cursor, displays: displays);
      }
    } on MissingPluginException {
      // Fall through to screen_retriever below.
    } catch (e) {
      debugPrint('sclip: screenLayout channel failed: $e');
    }
    try {
      final cursor = await screenRetriever.getCursorScreenPoint();
      final ds = await screenRetriever.getAllDisplays();
      final displays = [
        for (final d in ds)
          (() {
            final visible =
                (d.visiblePosition ?? Offset.zero) &
                (d.visibleSize ??
                    Size(
                      d.size.width / (d.scaleFactor ?? 1.0).toDouble(),
                      d.size.height / (d.scaleFactor ?? 1.0).toDouble(),
                    ));
            return (visible: visible, full: visible, scaleFactor: (d.scaleFactor ?? 1.0).toDouble());
          })(),
      ];
      return (cursor: cursor, displays: displays);
    } catch (e) {
      debugPrint('sclip: screen_retriever fallback failed: $e');
      return null;
    }
  }

  /// The visible rectangle of whichever display owns [point]. Cursor
  /// containment uses each display's *full* frame (including menu bar /
  /// taskbar) so a tray-icon click — which by definition lands on the
  /// menu bar — still resolves to the right display. The returned rect
  /// is the *visible* frame, since callers clamp the window into it and
  /// is the *visible* frame, since callers clamp the window into it and
  /// never want sclip sliding under the menu bar. Falls back to the
  /// primary (first) display when nothing contains the point.
  ({Rect visible, Rect full, double scaleFactor})? _displayContaining(
    Offset point,
    List<({Rect visible, Rect full, double scaleFactor})> displays,
  ) {
    if (displays.isEmpty) return null;
    for (final d in displays) {
      if (d.full.contains(point)) return d;
    }
    return displays.first;
  }

  /// Window size used while the settings modal is open, adapted to the
  /// display it will live on. We cap at the preferred 520×600 for
  /// comfort on big monitors, but shrink to ~80% of the display's
  /// visible area on small screens so the modal never dominates — a
  /// MacBook Air is cramped enough already without sclip eating most of
  /// the screen.
  Size _settingsSizeFor(Rect bounds) {
    final w = math.min(
      _settingsPreferredSize.width,
      math.max(380.0, bounds.width * 0.7),
    );
    final h = math.min(
      _settingsPreferredSize.height,
      math.max(440.0, bounds.height * 0.7),
    );
    return Size(w, h);
  }

  /// Shift [position] just enough so that a [size]-sized window sits
  /// fully inside [bounds] with an 8-px margin. Preserves the user's
  /// anchor (top-right from tray stays top-right, centred stays centred)
  /// instead of jumping back to centre on every resize.
  Offset _clampInto(Offset position, Size size, Rect bounds) {
    final minX = bounds.left + 8;
    final minY = bounds.top + 8;
    final maxX = bounds.right - size.width - 8;
    final maxY = bounds.bottom - size.height - 8;
    return Offset(
      position.dx.clamp(minX, math.max(minX, maxX)),
      position.dy.clamp(minY, math.max(minY, maxY)),
    );
  }

  Future<void> _positionNearCursor() async {
    try {
      final layout = await _queryScreenLayout();
      if (layout == null) return;
      final display = _displayContaining(layout.cursor, layout.displays);
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
      
      final clampedPhysical = _clampInto(desiredPhysical, physicalSize, bounds);
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Geçmişi sil'),
        content: const Text('Tüm pano geçmişi silinecek. Emin misin?'),
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
      _history.clear();
    }
  }

  Future<void> _quit() async {
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<void> _onEntryOpen(ClipboardEntry entry) async {
    final uri = entry.uris?.firstOrNull;
    if (uri == null) return;
    await _hideAndReturnFocus();
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _onEntryTap(ClipboardEntry entry, {int? imageIndex}) async {
    await _service.writeBack(entry, imageIndex: imageIndex);
    // Re-using an existing entry should bump it to the top with a fresh
    // timestamp — touch() keeps the id stable so widget keys don't churn
    // and the "just now" label reflects the latest action.
    _history.touch(entry.id);

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
  void onWindowFocus() {
    unawaited(HardwareKeyboard.instance.syncKeyboardState());

    // Reassert focus on the top entry — when the window is reshown after a
    // paste, OS focus sometimes arrives before our postFrameCallback from
    // _toggleWindow runs (or we were shown via a path that doesn't go
    // through _toggleWindow, like the system unhiding us). Requesting here
    // guarantees arrow keys have a primary focus to navigate from.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_firstItemFocus.context != null &&
          FocusManager.instance.primaryFocus != _firstItemFocus) {
        _firstItemFocus.requestFocus();
      }
    });
  }

  @override
  void onWindowBlur() {
    debugPrint('[DEBUG] ${DateTime.now().toIso8601String()} - onWindowBlur | Pressed keys: ${HardwareKeyboard.instance.logicalKeysPressed.map((k) => k.debugName).join(", ")}');
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
    final scheme = Theme.of(context).colorScheme;
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.comma, meta: true):
            const _OpenSettingsIntent(),
        const SingleActivator(LogicalKeyboardKey.comma, control: true):
            const _OpenSettingsIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _OpenSettingsIntent: CallbackAction<_OpenSettingsIntent>(
            onInvoke: (_) {
              unawaited(_openSettings());
              return null;
            },
          ),
        },
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: 40,
            titleSpacing: 8,
            title: Image.asset(
              'assets/branding/logo.png',
              height: 22,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              semanticLabel: 'sclip',
            ),
            centerTitle: true,
            actions: [
              ListenableBuilder(
                listenable: _history,
                builder: (context, _) => IconButton(
                  tooltip: 'Hepsini sil',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: _history.isEmpty
                      ? null
                      : () => _confirmClearAll(context),
                ),
              ),
              IconButton(
                tooltip: 'Ayarlar',
                icon: const Icon(Icons.settings_outlined),
                onPressed: _openSettings,
              ),
            ],
          ),
          body: Column(
            children: [
              if (!_accessibilityOk)
                Material(
                  color: scheme.errorContainer,
                  child: InkWell(
                    onTap: _openAccessibilitySettings,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: scheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Otomatik yapıştırma için Accessibility izni gerek.',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onErrorContainer,
                              ),
                            ),
                          ),
                          Text(
                            'Ayarları aç',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onErrorContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: HistoryList(
                  provider: _history,
                  onEntryTap: _onEntryTap,
                  onEntryOpen: _onEntryOpen,
                  firstItemFocusNode: _firstItemFocus,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpenSettingsIntent extends Intent {
  const _OpenSettingsIntent();
}
