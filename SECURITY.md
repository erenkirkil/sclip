# Security Policy

## Reporting a Vulnerability

If you discover a security issue, please open a GitHub Issue or email **erenkirkil@gmail.com**. There is no SLA — this is a personal project — but reports will be reviewed and addressed promptly.

## Threat Model

sclip is designed to be safer than cloud-backed clipboard managers by keeping clipboard history in RAM only and never making network calls.

**In scope:**
- Malicious clipboard content (e.g. SVG XXE, billion-laughs entity expansion)
- Keystroke injection race condition (paste sent to wrong window)
- Accidental disk persistence of clipboard history
- **Live process-memory reads** by another unprivileged process running as the same user. In scope but **not mitigable** on Windows, and blocked on macOS only for the notarised, hardened-runtime build — see Risk 7 in [`docs/security.md`](docs/security.md)

**Out of scope:**
- Kernel-level access, or offline access to the disk — swap file, hibernation image, memory forensics on a powered-off machine. That attacker already owns the machine
- Apps that bypass `ConcealedType` / `ExcludeClipboardContentFromMonitoring` by not setting the flag (OS protocol limit, not a sclip bug)
- OCR-based "is this a password?" heuristics (false-positive rate is unacceptably high)

## Known Limitations

### Network
Disabled at the macOS entitlement layer (`Release.entitlements` has no `com.apple.security.network.*`). Absent from the codebase on Windows. No package used by sclip makes outbound connections.

### Sensitive content filter
macOS: sclip checks for `org.nspasteboard.ConcealedType` on every pasteboard read. Windows: checks `ExcludeClipboardContentFromMonitoring`. These flags are set cooperatively by apps like 1Password and Bitwarden. A plain text editor copying a password will not set the flag — sclip has no way to detect that. This is an OS-level limitation.

### Paste race window (~120ms)
When the user selects an item in sclip, sclip hides itself and injects Cmd+V (macOS) or Ctrl+V (Windows) into what it believes is the previously active window. There is a ~120ms window during which the foreground could change. As of sprint 10, sclip performs a PID/HWND verification before injecting: if the frontmost app changed during the window, the paste is aborted and logged.

See [`docs/security.md`](docs/security.md) for the full trade-off analysis.

### RAM-only guarantee
History is stored as a `List<ClipboardEntry>` in process heap. It is never written to a database or a network endpoint, and it is never persisted to disk — the single exception being the short-lived temp file needed to paste SVG/PDF/image-sets into file-handler targets, cleaned per entry on eviction, on quit, and on next launch. When the process exits the history is gone.

Two memory-level limits follow from that, and neither can be fixed inside the app:

- **Offline recovery — out of scope.** With disk access, swap or hibernation images may still hold heap pages. macOS encrypts swap by default; on Windows this needs BitLocker.
- **Live reads by a same-user process — in scope, not mitigable.** On Windows, any unprivileged process running as you can `OpenProcess(PROCESS_VM_READ)` + `ReadProcessMemory` against sclip: that is how process objects are ACLed by default and no application can opt out. On macOS the notarised build's hardened runtime blocks `task_for_pid` for non-root debuggers, but a locally built `.app` is not hardened. Full analysis: Risk 7 in [`docs/security.md`](docs/security.md).
