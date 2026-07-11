import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/settings_provider.dart';
import 'services/settings_service.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Clamp Flutter's decoded-image cache (default 100 MB / 1000 images).
  // Thumbnails decode at ~48px now, so 32 MB is generous headroom — the
  // default would let full-size decodes from before the clamp (or any
  // future unscaled Image) stick around long after their entries left
  // history, pinning RSS at its high-water mark.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 32 << 20;

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
          (ex.contains('is not pressed') ||
              ex.contains('is already pressed'))) {
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

  // Hoisted: the ListenableBuilder below fires on EVERY settings change
  // (polling rate, max items, ...), and rebuilding two ColorScheme.fromSeed
  // palettes per toggle is pure waste — only themeMode actually varies.
  static final _lightTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _brandSeed),
    useMaterial3: true,
  );
  static final _darkTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _brandSeed,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );

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
        theme: _lightTheme,
        darkTheme: _darkTheme,
        home: HomePage(settings: settings, navigatorKey: navigatorKey),
      ),
    );
  }
}
