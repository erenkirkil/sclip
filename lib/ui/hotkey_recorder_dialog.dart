import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

/// A focus-locked dialog that captures the next non-modifier keypress and
/// returns a [HotKey] to the caller. Wraps the package's [HotKeyRecorder]
/// so we own the confirmation step — raw `HotKeyRecorder` fires on every
/// partial combo as modifiers drop, and we don't want to commit until the
/// user explicitly confirms.
class HotkeyRecorderDialog extends StatefulWidget {
  const HotkeyRecorderDialog({super.key, required this.initial});

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
            constraints: const BoxConstraints(minHeight: 64),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _recording
                ? HotKeyRecorder(
                    initalHotKey: widget.initial,
                    onHotKeyRecorded: _onRecorded,
                  )
                : HotKeyVirtualView(hotKey: _captured!),
          ),
          if (!_recording)
            TextButton(
              onPressed: () => setState(() {
                _captured = null;
                _recording = true;
              }),
              child: const Text('Yeniden kaydet'),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: (_captured == null || !_isValid(_captured!))
              ? null
              : () => Navigator.of(context).pop(_captured),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
