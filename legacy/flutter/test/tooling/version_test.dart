import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pubspec sürümü v2.0 serisinde', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((String l) => l.startsWith('version:'));
    final version = line.split(':')[1].trim();
    expect(
      version,
      startsWith('2.0.'),
      reason:
          'Paketleme script\'leri sürümü pubspec.yaml\'dan okuyor; v1.1.0 '
          'kalırsa üretilen artefakt mevcut v1.1.0 DMG\'sinin adını alır.',
    );
  });
}
