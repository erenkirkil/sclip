# Security Policy

## Reporting a Vulnerability

If you discover a security issue, please open a GitHub Issue or email **erenkirkil@gmail.com**. There is no SLA — this is a personal project — but reports will be reviewed and addressed promptly.

## Threat Model

sclip is designed to be safer than cloud-backed clipboard managers by keeping clipboard history in RAM only and never making network calls.

**In scope:**
- Malicious clipboard content (e.g. SVG XXE, billion-laughs entity expansion)
- Keystroke injection race condition (paste sent to wrong window)
- Accidental disk persistence of clipboard history

**Out of scope:**
- Attacker with kernel/disk/RAM-dump access (swap file, memory forensics) — this attacker already owns the machine
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
History is stored as a `List<ClipboardEntry>` in process heap. It is never written to disk, a database, or a network endpoint. When the process exits the history is gone. Swap-file recovery by an attacker with disk access is theoretically possible but is out of scope — that attacker controls the entire machine.
