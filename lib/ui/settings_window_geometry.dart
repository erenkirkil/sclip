import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../services/window_positioner.dart';

/// The temporary grow-shrink dance around the Settings modal: the panel's
/// minimal footprint (340×460) is too tight for the settings surface, so
/// the window is grown for the modal's lifetime and conditionally restored
/// afterwards. Kept out of HomePage — it's pure window geometry.
abstract final class SettingsWindowGeometry {
  /// Preferred settings window size on a roomy display — capped at this
  /// and shrunk via [settingsSizeFor] when the host display is smaller
  /// (e.g. MacBook Air as a secondary monitor). Kept deliberately tight
  /// to preserve sclip's minimalist feel; the Settings surface fits
  /// comfortably in 440×560 with the current sections.
  static const preferredSize = Size(440, 560);
  static const defaultWindowSize = Size(340, 460);
  static const defaultMinSize = Size(300, 360);

  /// Grows the window to fit the settings modal and returns a restore
  /// closure to run after the modal closes. The restore is conditional:
  /// a user who manually resized/moved the window while the modal was
  /// open keeps their layout (see comments inline).
  static Future<Future<void> Function()> grow(
    MethodChannel windowChannel,
  ) async {
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
    final layout = await queryScreenLayout(windowChannel);
    final display = layout == null
        ? null
        : displayContaining(previousPosition, layout.displays);
    final bounds = display?.visible;
    final scale = Platform.isWindows ? (display?.scaleFactor ?? 1.0) : 1.0;

    final settingsSize = bounds == null
        ? preferredSize
        : settingsSizeFor(bounds, preferredSize);
    final settingsMinSize = Size(
      math.min(preferredSize.width, settingsSize.width),
      math.min(preferredSize.height, settingsSize.height),
    );

    // Position math is shared by the grow clamp and the restore's
    // "did anything move us?" check below.
    Offset expectedOpenPosition() {
      if (bounds == null) return previousPosition;
      final physicalSize = Size(
        settingsSize.width * scale,
        settingsSize.height * scale,
      );
      final physicalPos = Offset(
        previousPosition.dx * scale,
        previousPosition.dy * scale,
      );
      final clampedPhysical = clampInto(physicalPos, physicalSize, bounds);
      return Platform.isWindows
          ? Offset(clampedPhysical.dx / scale, clampedPhysical.dy / scale)
          : clampedPhysical;
    }

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
      final clamped = expectedOpenPosition();
      if (clamped != previousPosition) {
        await windowManager.setPosition(clamped);
      }
    }

    return () async {
      // Restore the minimal footprint. If the user manually resized the
      // window to something larger than the default but smaller than the
      // settings size, we treat that as intent to keep it — shrink only
      // when the window is still at the size we just grew it to.
      await windowManager.setMinimumSize(defaultMinSize);
      final sizeNow = await windowManager.getSize();
      if (sizeNow != settingsSize) return;
      final restoreSize = previousSize == settingsSize
          ? defaultWindowSize
          : previousSize;
      await windowManager.setSize(restoreSize);
      // Position restore is deliberately conditional on "nothing else
      // moved us in the meantime". If the user cycled hide/show (e.g.
      // hid with the hotkey, re-opened via tray on another display)
      // between opening and closing settings, the current position is
      // their latest intent — teleporting back to the position we
      // captured at open time would feel like a screen jump. We detect
      // the no-move case via the same clamped position we set on open.
      final currentPosition = await windowManager.getPosition();
      final unmoved =
          (currentPosition - expectedOpenPosition()).distanceSquared < 1.0;
      if (unmoved) {
        await windowManager.setPosition(previousPosition);
      }
    };
  }
}
