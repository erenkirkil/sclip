import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The hardened-runtime gates are deliberately duplicated in the local gate
/// (scripts/verify.sh) and in CI (.github/workflows/ci.yml), exactly like the
/// pre-existing no-network entitlement check. Duplication is cheap; drift is
/// not — this test is what keeps the two copies identical.
void main() {
  const List<String> gates = <String>[
    "grep -q 'get-task-allow'",
    r"grep -qE 'cs\.allow-jit|cs\.allow-unsigned-executable-memory|cs\.disable-library-validation'",
    r"grep -v '^[[:space:]]*#'",
    "grep -q -- '--options runtime'",
  ];

  final String verify = File('scripts/verify.sh').readAsStringSync();
  final String ci = File('.github/workflows/ci.yml').readAsStringSync();

  for (final String gate in gates) {
    test('scripts/verify.sh carries gate: $gate', () {
      expect(verify, contains(gate));
    });

    test('.github/workflows/ci.yml carries gate: $gate', () {
      expect(ci, contains(gate));
    });
  }
}
