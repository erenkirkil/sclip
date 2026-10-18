import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

/// A focus-locked dialog that captures the next non-modifier keypress and
/// returns a [HotKey] to the caller. Wraps the package's [HotKeyRecorder]
/// so we own the confirmation step — raw `HotKeyRecorder` fires on every
/// partial combo as modifiers drop, and we don't want to commit until the
/// user explicitly confirms.
class const HotkeyRecorderDialog({super.key, required this.initial})
    extends StatefulWidget {
  final HotKey initial;

  /// Shows the dialog and resolves to the confirmed combo, or null when
  /// dismissed.
  static Future<HotKey?> show(BuildContext context, {required HotKey initial}) {
    return showDialog<HotKey>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => HotkeyRecorderDialog(initial: initial),
    );
  }

  @override
  State<HotkeyRecorderDialog> createState() => _HotkeyRecorderDialogState();
}

class _HotkeyRecorderDialogState extends State<HotkeyRecorderDialog> {
  HotKey? _captured;

  /// While true, raw keystrokes are being recorded. Latches off as soon
  /// as a combo satisfying the min-2-modifier rule lands — without the
  /// latch, HotKeyRecorder (a global keyboard handler) captures the very
  /// Tab/Enter presses a keyboard user needs to reach and activate
  /// 'Kaydet', overwriting the combo and making the dialog impossible to
  /// confirm without a mouse.
  bool _recording = true;

  static bool _isValid(HotKey hk) => (hk.modifiers?.length ?? 0) >= 2;

  void _onRecorded(HotKey hk) {
    setState(() {
      _captured = hk;
      if (_isValid(hk)) _recording = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      titlePadding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      title: const Text('Kısayolu kaydet', style: TextStyle(fontSize: 13)),
      content: Column(
        mainAxisSize: .min,
        children: [
          const Text(
            'İstediğin tuş kombinasyonuna bas. En az 2 modifier '
            '(Cmd/Ctrl/Alt/Shift) + bir tuş gerekli.',
            textAlign: .center,
            style: TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            alignment: .center,
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _recording
                ? HotKeyRecorder(
                    initalHotKey: widget.initial,
                    onHotKeyRecorded: _onRecorded,
                  )
                : FittedBox(
                    fit: .scaleDown,
                    child: HotKeyVirtualView(hotKey: _captured!),
                  ),
          ),
          if (!_recording)
            TextButton(
              onPressed: () => setState(() {
                _captured = null;
                _recording = true;
              }),
              child: const Text(
                'Yeniden kaydet',
                style: TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç', style: TextStyle(fontSize: 11.5)),
        ),
        FilledButton(
          onPressed: (_captured == null || !_isValid(_captured!))
              ? null
              : () => Navigator.of(context).pop(_captured),
          child: const Text('Kaydet', style: TextStyle(fontSize: 11.5)),
        ),
      ],
    );
  }
}
