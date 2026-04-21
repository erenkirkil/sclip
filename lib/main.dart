import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'models/clipboard_entry.dart';
import 'services/clipboard_service.dart';

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
  final List<ClipboardEntry> _entries = [];
  StreamSubscription<ClipboardEntry>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _service.entries.listen((entry) {
      debugPrint('[clipboard] ${entry.type.name} · ${entry.preview}');
      setState(() => _entries.insert(0, entry));
    });
    _service.start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('sclip'),
        centerTitle: true,
      ),
      body: _entries.isEmpty
          ? const Center(
              child: Text(
                'Henüz içerik yok — bir şey kopyala',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.separated(
              itemCount: _entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = _entries[i];
                return ListTile(
                  dense: true,
                  leading: _leadingFor(e),
                  title: Text(
                    e.preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(e.type.name),
                );
              },
            ),
    );
  }

  Widget _leadingFor(ClipboardEntry e) {
    if (e.type == ClipboardEntryType.color) {
      final argb = e.toArgb32();
      if (argb != null) {
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Color(argb),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24),
          ),
        );
      }
    }
    return Icon(_iconFor(e.type));
  }

  IconData _iconFor(ClipboardEntryType t) {
    switch (t) {
      case ClipboardEntryType.text:
        return Icons.notes;
      case ClipboardEntryType.url:
        return Icons.link;
      case ClipboardEntryType.image:
        return Icons.image;
      case ClipboardEntryType.files:
        return Icons.folder;
      case ClipboardEntryType.color:
        return Icons.palette;
    }
  }
}
