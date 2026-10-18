import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/security.md is the contract for what sclip does and does not defend
/// against. A silent edit that drops a risk section is a regression in the
/// same sense a deleted guard clause is, so it gets a test.
void main() {
  group('docs/security.md', () {
    late final String text;

    setUpAll(() {
      text = File('docs/security.md').readAsStringSync();
    });

    test('documents Risk 7 live memory reads', () {
      expect(text, contains('## Risk 7 — Canlı process belleği okuma'));
      expect(text, contains('Kapsam içi, azaltılamaz'));
      expect(text, contains('PROCESS_VM_READ'));
      expect(text, contains('task_for_pid'));
      expect(text, contains('BitLocker'));
      expect(text, contains('Win+V'));
      expect(text, contains('sclip.settings.clearOnScreenLock'));
    });

    test('narrows Risk 2 to the offline attack', () {
      expect(text, contains('## Risk 2 — Swap/paging ile offline RAM dump'));
      expect(text, contains('offline saldırı yüzeyini değiştirmez'));
    });

    test('documents the hardened-runtime structural condition', () {
      expect(
        text,
        contains('Hardened runtime neden ek entitlement gerektirmiyor'),
      );
      expect(text, contains('DynamicLibrary.process()'));
      expect(text, contains('libsuper_native_extensions.a'));
      expect(text, contains('launch-time'));
    });
  });
}
