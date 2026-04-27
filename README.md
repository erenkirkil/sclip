<p align="center">
  <img src="assets/branding/logo.png" alt="sclip" width="320">
</p>

<p align="center">
  <strong>Offline, RAM-only clipboard manager for macOS &amp; Windows.</strong><br>
  Built in Flutter. No cloud sync, no disk writes for clipboard content, no network access.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2012%2B%20%7C%20Windows%2010%2B-blue" alt="Platforms">
  <img src="https://img.shields.io/badge/flutter-3.9%2B-02569B?logo=flutter" alt="Flutter">
</p>

---

## Why

Most clipboard managers either sync history through the cloud or persist it to disk, which trades convenience for confidentiality. sclip keeps the entire history in-process: when you quit the app, the history is gone. Settings live in `shared_preferences`; clipboard content never touches a database, a file, or the network.

The macOS build ships with `com.apple.security.network.*` entitlements removed. The Windows build links no networking code. A CI gate enforces both: pushes that introduce `HttpClient`, `dart:io` sockets, or a network entitlement fail before merge.

## Features

- **Format coverage**: text, URLs, hex/`rgb()` colours, PNG/JPEG/GIF/WebP (single + multi-image grid), SVG (UTI + plain-text markup, both XXE-sanitised), files (Finder/Explorer + `NSFilePromiseReceiver` non-destructive), PDF (bytes ≤ 25 MB + Finder URI fallback), rich text/HTML (formatting preserved on paste-back).
- **Global hotkey**: ⌘⇧V (macOS) / Ctrl+Shift+V (Windows), rebindable from the settings page.
- **Tray-resident**: lives in the menu bar / system tray; no Dock or taskbar footprint.
- **Smart paste**: hides itself, restores focus to the previous app, posts the paste keystroke. PID/HWND verification aborts the paste if the target window changed during the focus race.
- **Sensitive content filter**: skips entries where the source app set the OS-level concealed flag (1Password, Bitwarden, etc.).
- **Customisable**: theme (system/light/dark), history limit (10–200), hotkey, window prefs.

## Format support

| Type | Detection | Notes |
|---|---|---|
| Text | fallback | unicode-safe |
| URL | scheme whitelist | `http`, `https`, `ftp`, `mailto` only — `javascript:` / `data:` reject to text |
| Color | regex | `#hex`, `rgb()`, `rgba()` |
| Image | UTI / format ID | PNG, JPEG, GIF, WebP |
| Image set | multi-format | grid view, paste-all via temp file URIs |
| SVG | UTI **and** plain-text `<svg>` heuristic | DOCTYPE/ENTITY/XInclude rejected, > 20 MB rejected |
| Files | native channel | macOS `NSURL` + `NSFilePromiseReceiver`; Windows `CF_HDROP` |
| PDF | format ID + URL fallback | bytes capped at 25 MB; Finder copies hold URI only |
| Rich text | HTML + plain text side-by-side | RTF preserved when pasting into formatting-aware targets |

## Security

Clipboard content is sensitive by nature, so sclip's threat model and mitigations are documented up front:

- [`SECURITY.md`](SECURITY.md) — threat model, scope, reporting.
- [`docs/security.md`](docs/security.md) — per-risk trade-off analysis (paste race, swap-dump, cooperative concealed flag, SVG entity expansion, URL schemes).

Highlights:
- SVG XXE defence rejects `<!DOCTYPE>`, `<!ENTITY>`, `xmlns:xi`, and oversized payloads before render. Test fixtures in [`test/fixtures/malicious_svg/`](test/fixtures/malicious_svg/).
- Paste race window (~120 ms) is verified — both platforms capture the target PID/HWND before hiding, and abort the keystroke injection if the foreground changed.
- Network entitlement removed at the macOS build layer; CI checks for regressions.

## Architecture

```
lib/
├── models/clipboard_entry.dart     # value type — text / url / color / image / imageSet / svg / files / pdf / richText
├── services/
│   ├── clipboard_service.dart      # 500 ms changeCount poll → format priority chain → emit
│   ├── tray_service.dart           # tray icon + tooltip
│   ├── hotkey_service.dart         # global shortcut registration
│   └── settings_service.dart       # shared_preferences wrapper
├── providers/
│   ├── history_provider.dart       # in-memory FIFO, dedup via SHA-256 (16-char prefix)
│   └── settings_provider.dart      # reactive prefs
└── ui/                             # Material 3 widgets

macos/Runner/MainFlutterWindow.swift    # captureForeground / pasteToPrevious / readFiles channels
windows/runner/flutter_window.cpp       # SetForegroundWindow / SendInput / CF_HDROP channels
```

The clipboard service avoids deep clipboard reads when possible: a 500 ms `changeCount` / `GetClipboardSequenceNumber` integer comparison runs first, and content is only fetched when the counter advances. Files content bypasses `super_clipboard` entirely because its `NSFilePromise` resolution is destructive (it empties the source pasteboard); the native `readFiles` channel reads non-destructively.

## Install

### macOS (12.0+)

1. Download `sclip-<version>.dmg` from the [latest release](https://github.com/erenkirkil/sclip/releases/latest).
2. Open the DMG and drag **sclip** into the **Applications** folder.
3. Launch sclip from Spotlight or Launchpad.
4. First launch asks for Accessibility permission (System Settings → Privacy & Security → Accessibility). This is required for the smart-paste keystroke injection. sclip works without it but the paste step has to be done manually with Cmd+V.

The DMG is signed with a Developer ID certificate and notarised by Apple — no Gatekeeper warnings, no `xattr` workaround needed.

### Windows (10+)

Download the release ZIP, extract anywhere, run `sclip.exe`. SmartScreen may warn on first launch ("More info" → "Run anyway") since the binary is not Authenticode-signed.

## Build from source

Requires Flutter 3.9+ on stable channel.

```bash
git clone https://github.com/erenkirkil/sclip.git
cd sclip
flutter pub get
```

**macOS:** `flutter build macos --release` → `open build/macos/Build/Products/Release/sclip.app`

**Windows:** `flutter build windows --release` → `.\build\windows\x64\runner\Release\sclip.exe`

For a signed + notarised DMG (requires an Apple Developer Program membership), see [`scripts/make-dmg.sh`](scripts/make-dmg.sh).

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘⇧V / Ctrl+Shift+V | Toggle panel (rebindable in settings) |
| ↑ / ↓ | Move between entries |
| ← / → | Move between row actions (open / paste-all / delete) |
| Enter | Copy + paste into previous app |
| Delete / Backspace | Remove entry |
| Esc | Hide panel |

## Quality gate

```bash
bash scripts/verify.sh
```
Runs format check, `flutter analyze --fatal-warnings`, `flutter test`, forbidden-pattern scan (no network code in `lib/`), and entitlement check. Same checks the [CI workflow](.github/workflows/ci.yml) enforces on push.

## Tech

Flutter / Dart for UI and business logic. Native channels in Swift (macOS) and C++ (Windows) for clipboard reads that need to bypass the Flutter plugin abstraction. `super_clipboard` for cross-platform format detection where it's safe to use; `tray_manager`, `hotkey_manager`, `window_manager` for desktop integration; `flutter_svg` for SVG rendering.

## License

[MIT](LICENSE) © Eren Kırkıl


