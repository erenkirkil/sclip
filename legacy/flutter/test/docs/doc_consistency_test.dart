import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CONTEXT.md and sprints/ are gitignored (.gitignore:5-6): they exist on the
/// maintainer's machine but never in a CI checkout. Assertions on them are
/// skipped when absent rather than failing a clean clone.
String? skipIfMissing(String path) => File(path).existsSync()
    ? null
    : '$path is gitignored and absent from this checkout';

void main() {
  group('README.md', () {
    late final String text;
    setUpAll(() => text = File('README.md').readAsStringSync());

    test('drops the absolute no-file claim', () {
      expect(text, isNot(contains('never touches a database, a file')));
      expect(text, isNot(contains('no disk writes for clipboard content')));
      expect(text, contains('short-lived temp file'));
    });

    test('lists the real history limits', () {
      expect(text, isNot(contains('10–200')));
      expect(text, contains('history limit (10 / 30 / 50 / 100)'));
    });

    test('Esc row matches the code', () {
      expect(text, isNot(contains('| Esc | Hide panel |')));
      expect(text, contains('Close the open dialog'));
    });
  });

  group('SECURITY.md', () {
    late final String text;
    setUpAll(() => text = File('SECURITY.md').readAsStringSync());

    test('splits kernel/disk from same-user live reads', () {
      expect(text, isNot(contains('kernel/disk/RAM-dump access')));
      expect(text, contains('Live process-memory reads'));
      expect(text, contains('Risk 7'));
    });
  });

  group('CONTEXT.md', () {
    test('states the correct SQLCipher rationale', () {
      final String text = File('CONTEXT.md').readAsStringSync();
      expect(text, contains('şifrelenecek disk artefaktı yok'));
      expect(text, isNot(contains("geçmiş RAM'de olduğu için SQLCipher")));
    }, skip: skipIfMissing('CONTEXT.md'));

    test('Esc row matches the code', () {
      final String text = File('CONTEXT.md').readAsStringSync();
      expect(text, isNot(contains('Delete sil, Esc gizle')));
      expect(text, contains('Esc açık diyaloğu kapatır'));
    }, skip: skipIfMissing('CONTEXT.md'));

    test('splits the threat model', () {
      final String text = File('CONTEXT.md').readAsStringSync();
      expect(text, isNot(contains('Kernel / disk / RAM-dump erişimi')));
      expect(text, contains('Aynı kullanıcı altında çalışan'));
    }, skip: skipIfMissing('CONTEXT.md'));

    test('pins the current toolchain', () {
      final String text = File('CONTEXT.md').readAsStringSync();
      expect(text, isNot(contains('3.35.7')));
      expect(text, contains('Flutter sürümü: 3.44.8 (stable) · Dart 3.12.2'));
    }, skip: skipIfMissing('CONTEXT.md'));
  });

  group('sprints/', () {
    test('records the shipped notarisation', () {
      final String text = File('sprints/pending-verification.md')
          .readAsStringSync();
      expect(text, isNot(contains('codesign/notarize,')));
      expect(text, contains('992XYS9346'));
      expect(text, contains('stapler validate'));
    }, skip: skipIfMissing('sprints/pending-verification.md'));

    test('points F-05..F-07 at their definition', () {
      final String text = File('sprints/pending-verification.md')
          .readAsStringSync();
      expect(text, contains('audit-2026-07.md:110-112'));
    }, skip: skipIfMissing('sprints/pending-verification.md'));

    test('lists the Faz 4 Windows leg', () {
      final String text = File('sprints/pending-verification.md')
          .readAsStringSync();
      expect(text, contains('OpenInputDesktop'));
    }, skip: skipIfMissing('sprints/pending-verification.md'));

    test('sprint 4 row mentions the screen-lock exception', () {
      final String text = File('sprints/README.md').readAsStringSync();
      expect(text, contains('ekran kilidi auto-clear'));
      expect(text, contains('| — | **Release v2.0**'));
    }, skip: skipIfMissing('sprints/README.md'));

    test('release.md has a v2.0 checklist', () {
      final String text = File('sprints/release.md').readAsStringSync();
      expect(text, contains('## v2.0 Kontrol Listesi'));
      expect(text, contains('Ekran kilitlendiğinde geçmişi temizle'));
    }, skip: skipIfMissing('sprints/release.md'));
  });
}
