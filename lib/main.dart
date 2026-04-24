import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'models/clipboard_entry.dart';
import 'providers/history_provider.dart';
import 'services/clipboard_service.dart';
import 'services/hotkey_service.dart';
import 'services/tray_service.dart';
import 'ui/history_list.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Surface the default red-screen errors to the console so we can diagnose
  // frames that flash an error widget without leaving a log trail.
  final prevOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    debugPrint('sclip: widget error: ${details.exception}');
    if (details.stack != null) debugPrint('${details.stack}');
    prevOnError?.call(details);
  };

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

  runApp(const SclipApp());
}

class SclipApp extends StatelessWidget {
  const SclipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'sclip',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,

      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),

    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WindowListener {
  static const _windowChannel = MethodChannel('sclip/window');
  static const _clipboardChannel = MethodChannel('sclip/clipboard');
  final ClipboardService _service = ClipboardService();
  final HistoryProvider _history = HistoryProvider();
  late final TrayService _tray;
  late final HotkeyService _hotkey;
  final FocusNode _firstItemFocus = FocusNode(debugLabel: 'sclip-first-item');
  StreamSubscription<ClipboardEntry>? _sub;

  /// True once we've confirmed macOS Accessibility is granted (or we're on a
  /// platform where it doesn't apply). While false on macOS, the paste-to-
  /// previous path silently fails, so we surface a one-time banner.
  bool _accessibilityOk = !Platform.isMacOS;

  /// When true, window stays on top and does not auto-hide on focus loss.
  /// Toggled from the tray menu.
  bool _pinned = false;

  /// True while we're programmatically hiding the window, so our own
  /// show→hide bounce doesn't fire the blur-auto-hide path.
  bool _suppressBlur = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    _sub = _service.entries.listen(_history.add);
    _service.start();

    _tray = TrayService(
      onToggleWindow: _toggleWindow,
      onClearAll: () async => _history.clear(),
      onTogglePin: _togglePin,
      onQuit: _quit,
    );
    _hotkey = HotkeyService(onToggleWindow: _toggleWindow);

    _tray.init();
    _hotkey.init();
    _checkAccessibility();

    // Global Esc handler. CallbackShortcuts in the widget tree requires a
    // focused descendant, which isn't reliable when the window is first
    // shown via a hotkey (focus ownership can land outside the Flutter
    // engine for a frame). HardwareKeyboard fires regardless of focus.
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(_hideAndReturnFocus());
      return true;
    }
    return false;
  }

  Future<void> _checkAccessibility() async {
    if (!Platform.isMacOS) return;
    try {
      final trusted =
          await _clipboardChannel.invokeMethod<bool>('isAccessibilityTrusted');
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
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    windowManager.removeListener(this);
    _sub?.cancel();
    _service.dispose();
    _history.dispose();
    _tray.dispose();
    _hotkey.dispose();
    _firstItemFocus.dispose();
    super.dispose();
  }

  Future<void> _toggleWindow() async {
    final visible = await windowManager.isVisible();
    // We intentionally ignore isFocused: if the window is on screen at all
    // (e.g. opened via tray click and now lives in the background), pressing
    // the hotkey should hide it rather than fight its focus state.
    if (visible) {
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
    _suppressBlur = true;
    try {
      if (Platform.isMacOS) {
        // Hand focus back to the previously-active app (e.g. Android Studio).
        await _windowChannel.invokeMethod('hideAndDeactivate');
      } else {
        await windowManager.hide();
      }
    } finally {
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
  }

  Future<void> _positionNearCursor() async {
    try {
      final cursor = await screenRetriever.getCursorScreenPoint();
      final display = await screenRetriever.getPrimaryDisplay();
      final size = await windowManager.getSize();
      final screenSize = display.size;
      final visible = display.visiblePosition ?? Offset.zero;
      final scale = display.scaleFactor ?? 1.0;

      // Align top-right of window slightly below-left of cursor so it doesn't
      // cover the click point, and keep it clamped to the visible screen.
      var x = cursor.dx - size.width / 2;
      var y = cursor.dy + 12;

      final minX = visible.dx + 8;
      final minY = visible.dy + 8;
      final maxX = visible.dx + screenSize.width / scale - size.width - 8;
      final maxY = visible.dy + screenSize.height / scale - size.height - 8;

      x = x.clamp(minX, maxX);
      y = y.clamp(minY, maxY);

      await windowManager.setPosition(Offset(x, y));
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
    // File entries can't be pasted via Ctrl/Cmd+V reliably; just copy.
    if (entry.type == ClipboardEntryType.files) {
      await _hideAndReturnFocus();
      return;
    }
    if (Platform.isWindows) {
      // Hide first so focus returns to the previously-active app, then let
      // the native side send Ctrl+V after a short delay.
      await windowManager.hide();
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
    // Flutter's HardwareKeyboard tracks pressed keys in Dart and can drift
    // out of sync with the OS while our window is hidden — any key-up that
    // fires in another app never reaches us, so the next KeyDown trips an
    // assertion ("A KeyDownEvent is dispatched, but the state shows that
    // the physical key is already pressed."). Once that assertion throws,
    // subsequent dispatches are also unreliable, which is why arrow-key
    // navigation silently dies after the first copy+paste cycle.
    // syncKeyboardState asks the OS for the real pressed-key set and
    // reconciles, so the next event frame starts clean.
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
    // Auto-hide when user clicks away — unless the user has explicitly
    // pinned the window. _suppressBlur guards against our own hide path,
    // which also fires blur on macOS.
    if (_pinned || _suppressBlur) return;
    unawaited(_hideAndReturnFocus());
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
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 40,
        titleSpacing: 8,
        title: const Text('sclip', style: TextStyle(fontSize: 14)),
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
    );
  }
}
