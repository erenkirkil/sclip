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
    size: Size(260, 340),
    minimumSize: Size(220, 260),
    center: true,
    skipTaskbar: true,
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

// ignore: prefer_const_constructors_in_immutables
class SclipApp({super.key, required this.settings}) extends StatelessWidget {
  // Mid-green from the logo gradient (sc.svg / logo.svg, offset 0.62). Seed
  // for Material 3 — light/dark schemes derive harmonised tones from this.
  static const _brandSeed = Color(0xFF609D4F);

  // Hoisted: the ListenableBuilder below fires on EVERY settings change
  // (polling rate, max items, ...), and rebuilding three ColorScheme
  // .fromSeed palettes per toggle is pure waste — only themeMode and
  // trueDark actually vary, and both only pick between prebuilt objects.
  static final _lightTheme = buildSclipTheme();
  static final _darkTheme = buildSclipTheme(brightness: .dark);
  static final _trueDarkTheme = buildSclipTheme(
    brightness: .dark,
    trueDark: true,
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
        darkTheme: settings.trueDark ? _trueDarkTheme : _darkTheme,
        home: HomePage(settings: settings, navigatorKey: navigatorKey),
      ),
    );
  }
}

/// Builds one of sclip's three palettes.
///
/// Both dark modes use a layered carbon-black + neutral charcoal/slate-grey
/// surface hierarchy (eliminating Material 3's greenish dark surface tint)
/// while keeping the brand green accent. [trueDark] pulls the base canvas all
/// the way down to `#000000` for OLED panels while keeping elevated grey
/// containers (`#16161A` / `#1F1F24` / `#28282F`) visibly distinct.
///
/// Exposed (test-only) so the palette regression tests can exercise the
/// exact expressions the hoisted statics in [SclipApp] are built from,
/// rather than a second copy of them that could drift.
@visibleForTesting
ThemeData buildSclipTheme({
  Brightness brightness = .light,
  bool trueDark = false,
}) {
  final base = ColorScheme.fromSeed(
    seedColor: SclipApp._brandSeed,
    brightness: brightness,
  );
  if (brightness == .light) {
    return ThemeData(
      colorScheme: base,
      useMaterial3: true,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
    );
  }
  final scheme = base.copyWith(
    surface: trueDark ? const Color(0xFF000000) : const Color(0xFF0B0B0E),
    surfaceDim: trueDark ? const Color(0xFF000000) : const Color(0xFF070709),
    surfaceBright: trueDark ? const Color(0xFF242429) : const Color(0xFF2C2C33),
    surfaceContainerLowest: trueDark
        ? const Color(0xFF000000)
        : const Color(0xFF070709),
    surfaceContainerLow: trueDark
        ? const Color(0xFF101014)
        : const Color(0xFF131318),
    // Distinct charcoal-grey step up from the black canvas so the AppBar,
    // dialogs, and elevated strips read as neutral grey against black.
    surfaceContainer: trueDark
        ? const Color(0xFF16161B)
        : const Color(0xFF1B1B22),
    surfaceContainerHigh: trueDark
        ? const Color(0xFF1F1F26)
        : const Color(0xFF24242C),
    surfaceContainerHighest: trueDark
        ? const Color(0xFF292932)
        : const Color(0xFF2E2E38),
    onSurface: const Color(0xFFF4F4F6),
    onSurfaceVariant: const Color(0xFFA1A1AA),
    outline: const Color(0xFF71717A),
    // Clears WCAG 1.4.11's 3:1 non-text contrast floor against both #000000
    // and #0B0B0E so a copied #000000 swatch or recorder box stays visible.
    outlineVariant: const Color(0xFF63636E),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surfaceContainer,
    cardColor: scheme.surfaceContainerHigh,
    // hintColor is the one colour ThemeData does NOT derive from the
    // ColorScheme: the SDK hard-codes Colors.white60 for every dark theme.
    hintColor: scheme.onSurfaceVariant,
    dividerTheme: const DividerThemeData(color: Color(0xFF27272F)),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0.0,
    ),
  );
}
