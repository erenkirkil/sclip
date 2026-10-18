import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../providers/settings_provider.dart';
import 'hotkey_recorder_dialog.dart';

/// Full-window settings surface. Every change is committed through
/// [SettingsProvider] immediately — there is no "Apply" button, so closing
/// the page simply pops the route without any save step. The "Reset" button
/// restores defaults in place, which the user can then undo by changing
/// values again (no confirm dialog — resetting doesn't touch history).
class const SettingsPage({
  super.key,
  required this.settings,
  required this.onHotkeyChange,
}) extends StatefulWidget {
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
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            SettingsPage(settings: settings, onHotkeyChange: onHotkeyChange),
      ),
    );
  }

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
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
    final captured = await HotkeyRecorderDialog.show(
      context,
      initial: widget.settings.toggleHotkey,
    );
    if (!mounted) return;
    setState(() => _recordingHotkey = false);
    if (captured == null) return;
    final modifiers = captured.modifiers ?? const [];
    if (modifiers.length < 2) {
      // Single-modifier combos (e.g. Cmd+V, Ctrl+C) collide with standard
      // system shortcuts; we require at least two modifiers + a key so the
      // combo is distinctive enough to not steal a common OS binding.
      _messengerKey.currentState?.clearSnackBars();
      _messengerKey.currentState?.showSnackBar(
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
      _messengerKey.currentState?.clearSnackBars();
      _messengerKey.currentState?.showSnackBar(
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
    const titleStyle = TextStyle(fontSize: 11.5);
    const subStyle = TextStyle(fontSize: 10);
    const tilePadding = EdgeInsets.symmetric(horizontal: 8, vertical: 0);
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 28,
          titleSpacing: 4,
          title: const Text('Ayarlar', style: TextStyle(fontSize: 12.5)),
          leadingWidth: 28,
          leading: IconButton(
            iconSize: 15,
            padding: .zero,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 24),
                tapTargetSize: .shrinkWrap,
              ),
              onPressed: () async {
                final reset = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text(
                      'Varsayılanlara sıfırla',
                      style: TextStyle(fontSize: 13),
                    ),
                    content: const Text(
                      'Tüm ayarlar varsayılan değerlere dönecek. Pano geçmişi etkilenmez.',
                      style: TextStyle(fontSize: 11.5),
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
              child: const Text('Sıfırla', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        body: ListTileTheme(
          data: const ListTileThemeData(
            dense: true,
            minVerticalPadding: 2,
            contentPadding: tilePadding,
            visualDensity: VisualDensity(horizontal: -4, vertical: -4),
            titleTextStyle: titleStyle,
            subtitleTextStyle: subStyle,
          ),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              const _SectionHeader('Kısayollar'),
              ListTile(
                title: const Text('Pano aç/kapa', style: titleStyle),
                subtitle: Text(_hotkeyLabel(s.toggleHotkey), style: subStyle),
                trailing: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 24),
                    tapTargetSize: .shrinkWrap,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  icon: Icon(
                    _recordingHotkey
                        ? Icons.fiber_manual_record
                        : Icons.keyboard,
                    size: 13,
                  ),
                  label: Text(_recordingHotkey ? 'Kaydediliyor…' : 'Değiştir'),
                  onPressed: _recordingHotkey ? null : _openHotkeyRecorder,
                ),
              ),
              const Divider(height: 6),
              const _SectionHeader('Görünüm'),
              RadioGroup<ThemeMode>(
                groupValue: s.themeMode,
                onChanged: (v) {
                  if (v != null) unawaited(s.setThemeMode(v));
                },
                child: const Column(
                  children: [
                    _ThemeRadioTile(label: 'Sistem', value: .system),
                    _ThemeRadioTile(label: 'Açık', value: .light),
                    _ThemeRadioTile(label: 'Koyu', value: .dark),
                  ],
                ),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: tilePadding,
                title: const Text(
                  'Koyu temayı siyahlaştır (OLED)',
                  style: titleStyle,
                ),
                subtitle: Text(
                  s.themeMode == .light
                      ? 'Yalnızca koyu tema için geçerli.'
                      : 'Yüzeyler saf siyaha iner; marka rengi değişmez.',
                  style: subStyle,
                ),
                value: s.trueDark,
                // Light mode never builds darkTheme, so the switch would be
                // a control that visibly changes nothing. It stays on screen
                // (the preference is still persisted, and "Sistem" can flip
                // to dark at any moment) but goes inert.
                onChanged: s.themeMode == .light ? null : s.setTrueDark,
              ),
              const Divider(height: 6),
              const _SectionHeader('Geçmiş'),
              ListTile(
                title: const Text('Maksimum öğe sayısı', style: titleStyle),
                subtitle: Text('${s.maxItems} öğe', style: subStyle),
                trailing: DropdownButton<int>(
                  isDense: true,
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurface),
                  value: s.maxItems,
                  items: [
                    for (final v in SettingsProvider.allowedMaxItems)
                      DropdownMenuItem(value: v, child: Text('$v')),
                  ],
                  onChanged: (v) {
                    if (v != null) unawaited(s.setMaxItems(v));
                  },
                ),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: tilePadding,
                title: const Text('Hassas içerik filtresi', style: titleStyle),
                subtitle: Text(
                  s.sensitiveFilterEnabled
                      ? '1Password/Bitwarden gibi uygulamalardan gelen şifreler yakalanmaz.'
                      : 'Uyarı: hassas içerik geçmişe düşebilir.',
                  style: TextStyle(
                    fontSize: 10,
                    color: s.sensitiveFilterEnabled ? null : scheme.error,
                  ),
                ),
                value: s.sensitiveFilterEnabled,
                onChanged: s.setSensitiveFilterEnabled,
              ),
              SwitchListTile(
                dense: true,
                contentPadding: tilePadding,
                title: const Text(
                  'Ekran kilitlendiğinde geçmişi temizle',
                  style: titleStyle,
                ),
                subtitle: const Text(
                  'Kilidi açtığında geçmiş boş olur. Panonun kendisi ve '
                  'geçici dosyalar korunur — Cmd/Ctrl+V çalışmaya devam eder.',
                  style: subStyle,
                ),
                value: s.clearOnScreenLock,
                onChanged: s.setClearOnScreenLock,
              ),
              const Divider(height: 6),
              const _SectionHeader('Pencere'),
              SwitchListTile(
                dense: true,
                contentPadding: tilePadding,
                title: const Text('Odak kaybında gizle', style: titleStyle),
                subtitle: const Text(
                  'Başka bir uygulamaya tıklayınca sclip otomatik gizlenir.',
                  style: subStyle,
                ),
                value: s.autoHideOnBlur,
                onChanged: s.setAutoHideOnBlur,
              ),
              SwitchListTile(
                dense: true,
                contentPadding: tilePadding,
                title: const Text('Üste sabitle', style: titleStyle),
                subtitle: const Text(
                  'Pencere her zaman diğer uygulamaların üstünde kalır. Tray menüsüyle senkron.',
                  style: subStyle,
                ),
                value: s.alwaysOnTopDefault,
                onChanged: s.setAlwaysOnTopDefault,
              ),
              const Divider(height: 6),
              ExpansionTile(
                tilePadding: tilePadding,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
                title: const Text('Gelişmiş', style: titleStyle),
                initiallyExpanded: _advancedExpanded,
                onExpansionChanged: (v) =>
                    setState(() => _advancedExpanded = v),
                children: [
                  ListTile(
                    title: const Text('Polling aralığı', style: titleStyle),
                    subtitle: Text(
                      '${s.pollingIntervalMs} ms',
                      style: subStyle,
                    ),
                    trailing: DropdownButton<int>(
                      isDense: true,
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurface),
                      value: s.pollingIntervalMs,
                      items: [
                        for (final v in SettingsProvider.allowedPollingMs)
                          DropdownMenuItem(value: v, child: Text('$v ms')),
                      ],
                      onChanged: (v) {
                        if (v != null) unawaited(s.setPollingIntervalMs(v));
                      },
                    ),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: tilePadding,
                    title: const Text(
                      'Başlangıçta geçmişi temizle',
                      style: titleStyle,
                    ),
                    subtitle: const Text(
                      'Uygulama açılırken önceki oturumun belleği zaten uçar — bu, açılış anını garantiler.',
                      style: subStyle,
                    ),
                    value: s.clearOnStartup,
                    onChanged: s.setClearOnStartup,
                  ),
                ],
              ),
            ],
          ),
        ),
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

  static String _modLabel(HotKeyModifier m) => switch (m) {
    .meta => 'Cmd',
    .control => 'Ctrl',
    .alt => 'Alt',
    .shift => 'Shift',
    .capsLock => 'CapsLock',
    .fn => 'Fn',
  };
}

class const _SectionHeader(this.text) extends StatelessWidget {
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 9.5,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class const _ThemeRadioTile({required this.label, required this.value})
    extends StatelessWidget {
  final String label;
  final ThemeMode value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      minLeadingWidth: 0,
      horizontalTitleGap: 4,
      title: Text(label, style: const TextStyle(fontSize: 11.5)),
      leading: Radio<ThemeMode>(
        value: value,
        materialTapTargetSize: .shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      ),
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
