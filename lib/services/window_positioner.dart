import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';

typedef DisplayInfo = ({Rect visible, Rect full, double scaleFactor});
typedef ScreenLayout = ({Offset cursor, List<DisplayInfo> displays});

/// Snapshot of the desktop: cursor position plus every display's
/// visible rectangle, all in a single top-left flipped coordinate
/// space. Queried from our own native channel because
/// `screen_retriever` 0.2.0 normalises cursor Y against
/// `min(frame.maxY)` but display Y against `primary.frame.height` —
/// secondary is taller or sits side-by-side, so cursor-in-display
/// containment silently fails. Falling back to `screen_retriever`
/// when the channel isn't available keeps tests + non-desktop hosts
/// working.
Future<ScreenLayout?> queryScreenLayout(MethodChannel windowChannel) async {
  try {
    final layout = await windowChannel.invokeMapMethod<String, dynamic>(
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
/// never want sclip sliding under the menu bar. Falls back to the
/// primary (first) display when nothing contains the point.
DisplayInfo? displayContaining(Offset point, List<DisplayInfo> displays) {
  if (displays.isEmpty) return null;
  for (final d in displays) {
    if (d.full.contains(point)) return d;
  }
  return displays.first;
}

/// Window size used while the settings modal is open, adapted to the
/// display it will live on. We cap at the [preferredSize] for
/// comfort on big monitors, but shrink to ~70% of the display's
/// visible area on small screens so the modal never dominates — a
/// MacBook Air is cramped enough already without sclip eating most of
/// the screen.
Size settingsSizeFor(Rect bounds, Size preferredSize) {
  final w = math.min(
    preferredSize.width,
    math.max(380.0, bounds.width * 0.7),
  );
  final h = math.min(
    preferredSize.height,
    math.max(440.0, bounds.height * 0.7),
  );
  return Size(w, h);
}

/// Shift [position] just enough so that a [size]-sized window sits
/// fully inside [bounds] with an 8-px margin. Preserves the user's
/// anchor (top-right from tray stays top-right, centred stays centred)
/// instead of jumping back to centre on every resize.
Offset clampInto(Offset position, Size size, Rect bounds) {
  final minX = bounds.left + 8;
  final minY = bounds.top + 8;
  final maxX = bounds.right - size.width - 8;
  final maxY = bounds.bottom - size.height - 8;
  return Offset(
    position.dx.clamp(minX, math.max(minX, maxX)),
    position.dy.clamp(minY, math.max(minY, maxY)),
  );
}
