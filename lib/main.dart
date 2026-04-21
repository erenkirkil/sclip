import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'models/clipboard_entry.dart';
import 'providers/history_provider.dart';
import 'services/clipboard_service.dart';
import 'ui/history_list.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(400, 600),
    minimumSize: Size(320, 420),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: 'sclip',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const SclipApp());
}

class SclipApp extends StatelessWidget {
  const SclipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'sclip',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ClipboardService _service = ClipboardService();
  final HistoryProvider _history = HistoryProvider();
  StreamSubscription<ClipboardEntry>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _service.entries.listen(_history.add);
    _service.start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _service.dispose();
    _history.dispose();
    super.dispose();
  }

  Future<void> _onEntryTap(ClipboardEntry entry) async {
    await _service.writeBack(entry);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('sclip'),
        centerTitle: true,
        actions: [
          ListenableBuilder(
            listenable: _history,
            builder: (_, __) => IconButton(
              tooltip: 'Hepsini sil',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _history.isEmpty ? null : _history.clear,
            ),
          ),
        ],
      ),
      body: HistoryList(
        provider: _history,
        onEntryTap: _onEntryTap,
      ),
    );
  }
}
