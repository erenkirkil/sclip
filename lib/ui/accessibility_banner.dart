import 'package:flutter/material.dart';

class AccessibilityBanner extends StatelessWidget {
  const AccessibilityBanner({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: InkWell(
        onTap: onTap,
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
    );
  }
}
