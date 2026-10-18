import 'package:flutter/material.dart';

/// Thin persistent warning strip shown above the history list when a
/// capability sclip depends on is unavailable (Accessibility permission,
/// global hotkey). Tapping runs [onTap] — typically "open the relevant
/// settings".
class const WarningBanner({
  super.key,
  required this.icon,
  required this.message,
  required this.actionLabel,
  required this.onTap,
}) extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // button: true so screen readers announce this as actionable — the
    // row otherwise reads as plain text with an unnamed tap action, and
    // the 'action label' trailing text visually mimics a separate link
    // while being part of the same target.
    return Semantics(
      button: true,
      label: '$message $actionLabel',
      // The label above is the whole announcement; without this the inner
      // Texts would be read a second time as separate nodes.
      excludeSemantics: true,
      child: Material(
        color: scheme.errorContainer,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(icon, size: 13, color: scheme.onErrorContainer),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  actionLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: .w600,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class const AccessibilityBanner({super.key, required this.onTap})
    extends StatelessWidget {
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return WarningBanner(
      icon: Icons.lock_outline,
      message: 'Otomatik yapıştırma için Accessibility izni gerek.',
      actionLabel: 'Ayarları aç',
      onTap: onTap,
    );
  }
}
