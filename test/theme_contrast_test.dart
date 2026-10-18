import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sclip/main.dart';

/// WCAG 2.1 relative luminance. Deliberately hand-rolled instead of calling
/// `Color.computeLuminance()`: this file is the regression net for the
/// palette, and a net woven from the same thread as the thing it is meant
/// to catch is not a net.
double _relativeLuminance(Color c) {
  double linearize(double channel) => channel <= 0.03928
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * linearize(c.r) +
      0.7152 * linearize(c.g) +
      0.0722 * linearize(c.b);
}

/// WCAG 2.1 contrast ratio: (L_lighter + 0.05) / (L_darker + 0.05).
double contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  // WCAG 2.1 SC 1.4.3 (normal text) and SC 1.4.11 (non-text UI components).
  const textThreshold = 4.5;
  const uiThreshold = 3.0;

  ThemeData trueDark() =>
      buildSclipTheme(brightness: Brightness.dark, trueDark: true);

  group('theme contrast', () {
    test('all three palettes clear the WCAG text and UI thresholds', () {
      final themes = <String, ThemeData>{
        'light': buildSclipTheme(),
        'dark': buildSclipTheme(brightness: Brightness.dark),
        'trueDark': trueDark(),
      };

      for (final entry in themes.entries) {
        final scheme = entry.value.colorScheme;
        expect(
          contrastRatio(scheme.surface, scheme.onSurface),
          greaterThanOrEqualTo(textThreshold),
          reason: '${entry.key}: body text on surface',
        );
        expect(
          contrastRatio(scheme.surface, scheme.primary),
          greaterThanOrEqualTo(uiThreshold),
          reason: '${entry.key}: brand accent on surface',
        );
      }
    });

    test('trueDark hand-raised roles clear their thresholds', () {
      final theme = trueDark();
      final scheme = theme.colorScheme;

      // Swatch border (standard_tile.dart:253) and hotkey recorder box
      // (hotkey_recorder_dialog.dart:66). The tonalSpot dark value scores
      // 2.24:1 against pure black — a copied #000000 swatch would dissolve
      // straight into the background.
      expect(
        contrastRatio(scheme.surface, scheme.outlineVariant),
        greaterThanOrEqualTo(uiThreshold),
        reason: 'trueDark: swatch / recorder border on surface',
      );

      // The AppBar sits on surfaceContainer; equal values mean no seam.
      expect(scheme.surfaceContainer, isNot(scheme.surface));
    });

    test('trueDark hintColor is an opaque palette colour', () {
      final theme = trueDark();

      // ThemeData.hintColor does not derive from ColorScheme — the SDK
      // hard-codes Colors.white60 for any dark theme (theme_data.dart:487).
      // The 11px timestamps (standard_tile.dart:166) paint with it, so on
      // a black surface it drifts off-palette; and a translucent value has
      // no well-defined contrast ratio at all.
      expect(theme.hintColor, theme.colorScheme.onSurfaceVariant);
      expect(theme.hintColor.a, 1.0);
      expect(
        contrastRatio(theme.colorScheme.surface, theme.hintColor),
        greaterThanOrEqualTo(textThreshold),
      );
    });

    test('trueDark divider is pinned apart from outlineVariant', () {
      final theme = trueDark();
      final divider = theme.dividerTheme.color;

      // Divider falls back to colorScheme.outlineVariant. At the raised
      // value a full-width rule between every history row
      // (history_list.dart:116) reads as a ladder, so the separator keeps
      // its own dimmer value: a row divider is decorative, not a UI
      // component boundary under SC 1.4.11.
      expect(divider, isNotNull);
      expect(divider, isNot(theme.colorScheme.outlineVariant));
      expect(divider, isNot(theme.colorScheme.surface));
    });
  });
}
