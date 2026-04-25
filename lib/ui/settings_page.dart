import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../providers/settings_provider.dart';

/// Modal settings surface. Every change is committed through
/// [SettingsProvider] immediately — there is no "Apply" button, so closing
/// the modal simply dismisses it without any save step. The "Reset" button
/// restores defaults in place, which the user can then undo by changing
/// values again (no confirm dialog — resetting doesn't touch history).
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.onHotkeyChange,
  });

  final SettingsProvider settings;

  /// Called when the user commits a new hotkey via the recorder. Returns
  /// `true` on successful registration, `false` otherwise — the page
  /// surfaces a snackbar on failure without persisting the change.
  final Future<bool> Function(HotKey) onHotkeyChange;

  static Future<void> show(
    BuildContext context, {
    required SettingsProvider settings,
    required Future<bool> Function(HotKey) onHotkeyChange,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        // Derive the modal cap from the current window size rather than a
        // fixed 520×640 — on a small display (MacBook Air as a secondary)
        // the parent window itself is shrunk below those numbers and the
        // modal would otherwise overflow.
        final window = MediaQuery.sizeOf(ctx);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(440.0, window.width - 24),
              maxHeight: math.min(560.0, window.height - 48),
            ),
            child: SettingsPage(
              settings: settings,
              onHotkeyChange: onHotkeyChange,
            ),
          ),
        );
      },
    );
  }

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _advancedExpanded = false;
  bool _recordingHotkey = false;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettings);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  Future<void> _openHotkeyRecorder() async {
    setState(() => _recordingHotkey = true);
    final captured = await showDialog<HotKey>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) =>
          _HotkeyRecorderDialog(initial: widget.settings.toggleHotkey),
    );
    if (!mounted) return;
    setState(() => _recordingHotkey = false);
    if (captured == null) return;
    final modifiers = captured.modifiers ?? const [];
    if (modifiers.length < 2) {
      // Single-modifier combos (e.g. Cmd+V, Ctrl+C) collide with standard
      // system shortcuts; we require at least two modifiers + a key so the
      // combo is distinctive enough to not steal a common OS binding.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'En az 2 modifier (Cmd/Ctrl/Alt/Shift) + bir tuş gerekli.',
          ),
        ),
      );
      return;
    }
    final ok = await widget.onHotkeyChange(captured);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bu kombinasyon başka bir uygulama tarafından kullanılıyor.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final reset = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Varsayılanlara sıfırla'),
                  content: const Text(
                    'Tüm ayarlar varsayılan değerlere dönecek. Pano geçmişi etkilenmez.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Vazgeç'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Sıfırla'),
                    ),
                  ],
                ),
              );
              if (reset == true) {
                await s.resetAll();
                // Also re-register the default hotkey so the active binding
                // matches the visible default immediately.
                await widget.onHotkeyChange(s.toggleHotkey);
              }
            },
            child: const Text('Sıfırla'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader('Kısayollar'),
          ListTile(
            title: const Text('Pano aç/kapa'),
            subtitle: Text(_hotkeyLabel(s.toggleHotkey)),
            trailing: FilledButton.tonalIcon(
              icon: Icon(
                _recordingHotkey ? Icons.fiber_manual_record : Icons.keyboard,
              ),
              label: Text(_recordingHotkey ? 'Kaydediliyor…' : 'Değiştir'),
              onPressed: _recordingHotkey ? null : _openHotkeyRecorder,
            ),
          ),
          const Divider(),
          _SectionHeader('Görünüm'),
          RadioGroup<ThemeMode>(
            groupValue: s.themeMode,
            onChanged: (v) {
              if (v != null) s.setThemeMode(v);
            },
            child: const Column(
              children: [
                _ThemeRadioTile(label: 'Sistem', value: ThemeMode.system),
                _ThemeRadioTile(label: 'Açık', value: ThemeMode.light),
                _ThemeRadioTile(label: 'Koyu', value: ThemeMode.dark),
              ],
            ),
          ),
          const Divider(),
          _SectionHeader('Geçmiş'),
          ListTile(
            title: const Text('Maksimum öğe sayısı'),
            subtitle: Text('${s.maxItems} öğe'),
            trailing: DropdownButton<int>(
              value: s.maxItems,
              items: [
                for (final v in SettingsProvider.allowedMaxItems)
                  DropdownMenuItem(value: v, child: Text('$v')),
              ],
              onChanged: (v) {
                if (v != null) s.setMaxItems(v);
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Hassas içerik filtresi'),
            subtitle: Text(
              s.sensitiveFilterEnabled
                  ? '1Password/Bitwarden gibi uygulamalardan gelen şifreler yakalanmaz.'
                  : 'Uyarı: hassas içerik geçmişe düşebilir.',
              style: TextStyle(
                color: s.sensitiveFilterEnabled ? null : scheme.error,
              ),
            ),
            value: s.sensitiveFilterEnabled,
            onChanged: s.setSensitiveFilterEnabled,
          ),
          const Divider(),
          _SectionHeader('Pencere'),
          SwitchListTile(
            title: const Text('Odak kaybında gizle'),
            subtitle: const Text(
              'Başka bir uygulamaya tıklayınca sclip otomatik gizlenir.',
            ),
            value: s.autoHideOnBlur,
            onChanged: s.setAutoHideOnBlur,
          ),
          SwitchListTile(
            title: const Text('Üste sabitle'),
            subtitle: const Text(
              'Pencere her zaman diğer uygulamaların üstünde kalır. Tray menüsüyle senkron.',
            ),
            value: s.alwaysOnTopDefault,
            onChanged: s.setAlwaysOnTopDefault,
          ),
          const Divider(),
          ExpansionTile(
            title: const Text('Gelişmiş'),
            initiallyExpanded: _advancedExpanded,
            onExpansionChanged: (v) => setState(() => _advancedExpanded = v),
            children: [
              ListTile(
                title: const Text('Polling aralığı'),
                subtitle: Text('${s.pollingIntervalMs} ms'),
                trailing: DropdownButton<int>(
                  value: s.pollingIntervalMs,
                  items: [
                    for (final v in SettingsProvider.allowedPollingMs)
                      DropdownMenuItem(value: v, child: Text('$v ms')),
                  ],
                  onChanged: (v) {
                    if (v != null) s.setPollingIntervalMs(v);
                  },
                ),
              ),
              SwitchListTile(
                title: const Text('Başlangıçta geçmişi temizle'),
                subtitle: const Text(
                  'Uygulama açılırken önceki oturumun belleği zaten uçar — bu, açılış anını garantiler.',
                ),
                value: s.clearOnStartup,
                onChanged: s.setClearOnStartup,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _hotkeyLabel(HotKey hotkey) {
    final mods = hotkey.modifiers ?? const [];
    final parts = <String>[
      for (final m in mods) _modLabel(m),
      hotkey.physicalKey.debugName ?? '?',
    ];
    return parts.join(' + ');
  }

  static String _modLabel(HotKeyModifier m) {
    switch (m) {
      case HotKeyModifier.meta:
        return 'Cmd';
      case HotKeyModifier.control:
        return 'Ctrl';
      case HotKeyModifier.alt:
        return 'Alt';
      case HotKeyModifier.shift:
        return 'Shift';
      case HotKeyModifier.capsLock:
        return 'CapsLock';
      case HotKeyModifier.fn:
        return 'Fn';
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ThemeRadioTile extends StatelessWidget {
  const _ThemeRadioTile({required this.label, required this.value});

  final String label;
  final ThemeMode value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      leading: Radio<ThemeMode>(value: value),
      onTap: () {
        // Trigger the ambient RadioGroup's onChanged by dispatching the
        // selection through the Radio's own registered value. The simplest
        // way is to just let the Radio handle taps, but ListTile gives us
        // a bigger hit target — so we mirror the behaviour here.
        final group = RadioGroup.maybeOf<ThemeMode>(context);
        group?.onChanged.call(value);
      },
    );
  }
}

/// A focus-locked dialog that captures the next non-modifier keypress and
/// returns a [HotKey] to the caller. Wraps the package's [HotKeyRecorder]
/// so we own the confirmation step — raw `HotKeyRecorder` fires on every
/// partial combo as modifiers drop, and we don't want to commit until the
/// user explicitly confirms.
class _HotkeyRecorderDialog extends StatefulWidget {
  const _HotkeyRecorderDialog({required this.initial});

  final HotKey initial;

  @override
  State<_HotkeyRecorderDialog> createState() => _HotkeyRecorderDialogState();
}

class _HotkeyRecorderDialogState extends State<_HotkeyRecorderDialog> {
  HotKey? _captured;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kısayolu kaydet'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'İstediğin tuş kombinasyonuna bas. En az 2 modifier '
            '(Cmd/Ctrl/Alt/Shift) + bir tuş gerekli.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: HotKeyRecorder(
              initalHotKey: widget.initial,
              onHotKeyRecorded: (hk) => setState(() => _captured = hk),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _captured == null
              ? null
              : () => Navigator.of(context).pop(_captured),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
