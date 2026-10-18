import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The shipped .app gets hardened runtime without a single
/// `com.apple.security.cs.*` exception. That only holds while sclip's own code
/// loads nothing at runtime — no dlopen, no FFI, no DynamicLibrary. If a change
/// breaks it, the symptom would otherwise be a launch-time crash on a notarised
/// build, i.e. on a user's machine and nowhere earlier. This test moves the
/// failure to `flutter test`.
void main() {
  final RegExp forbidden = RegExp(r'dlopen|dart:ffi|DynamicLibrary');
  const List<String> roots = <String>['lib', 'macos/Runner', 'windows/runner'];
  const List<String> sourceExtensions = <String>[
    '.dart',
    '.swift',
    '.cpp',
    '.h',
  ];

  test('first-party code loads no native library at runtime', () {
    final List<String> offenders = <String>[];

    for (final String root in roots) {
      final Directory dir = Directory(root);
      expect(dir.existsSync(), isTrue, reason: '$root is missing');

      for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!sourceExtensions.any(entity.path.endsWith)) continue;

        final List<String> lines = entity.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          if (forbidden.hasMatch(lines[i])) {
            offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Runtime library loading in first-party code breaks the '
          'hardened-runtime assumption in docs/security.md. The fix is to drop '
          'the dependency on it, never to add a com.apple.security.cs.* '
          'entitlement.',
    );
  });
}
