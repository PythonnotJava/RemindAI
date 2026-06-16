import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dock_panel.dart';

void main() {
  runApp(const ProviderScope(child: DockPanelDemoApp()));
}

class DockPanelDemoApp extends StatelessWidget {
  const DockPanelDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dock Panel - Multi Panel Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      ),
      home: const DemoDockScreen(),
    );
  }
}

class DemoDockScreen extends ConsumerStatefulWidget {
  const DemoDockScreen({super.key});

  @override
  ConsumerState<DemoDockScreen> createState() => _DemoDockScreenState();
}

class _DemoDockScreenState extends ConsumerState<DemoDockScreen> {
  int _panelCounter = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setupLayout());
  }

  void _setupLayout() {
    final manager = ref.read(dockManagerProvider.notifier);

    // ─── Register panels ───────────────────────────────────
    manager.addPanel(
      _createPanel(
        id: 'file_explorer',
        title: 'Explorer',
        icon: Icons.folder_outlined,
        color: const Color(0xFF1B5E20),
        closable: false,
        content: const _FileExplorerPanel(),
      ),
    );

    manager.addPanel(
      _createPanel(
        id: 'editor_main',
        title: 'main.dart',
        icon: Icons.code,
        color: const Color(0xFF0D47A1),
        content: const _CodeEditorPanel(filename: 'main.dart'),
      ),
    );

    manager.addPanel(
      _createPanel(
        id: 'editor_model',
        title: 'model.dart',
        icon: Icons.data_object,
        color: const Color(0xFF0D47A1),
        content: const _CodeEditorPanel(filename: 'model.dart'),
      ),
    );

    manager.addPanel(
      _createPanel(
        id: 'terminal',
        title: 'Terminal',
        icon: Icons.terminal,
        color: const Color(0xFF212121),
        content: const _TerminalPanel(),
      ),
    );

    manager.addPanel(
      _createPanel(
        id: 'output',
        title: 'Output',
        icon: Icons.output,
        color: const Color(0xFF1A237E),
        content: const _OutputPanel(),
      ),
    );

    manager.addPanel(
      _createPanel(
        id: 'problems',
        title: 'Problems',
        icon: Icons.warning_amber,
        color: const Color(0xFFE65100),
        content: const _ProblemsPanel(),
      ),
    );

    manager.addPanel(
      _createPanel(
        id: 'outline',
        title: 'Outline',
        icon: Icons.account_tree_outlined,
        color: const Color(0xFF4A148C),
        content: const _OutlinePanel(),
      ),
    );

    // ─── Build IDE-like layout ─────────────────────────────
    // Move terminal + output + problems to bottom
    manager.movePanel('terminal', 'file_explorer', DockPosition.bottom);
    manager.movePanel('output', 'terminal', DockPosition.center);
    manager.movePanel('problems', 'terminal', DockPosition.center);

    // Move explorer to left of editor
    manager.movePanel('file_explorer', 'editor_main', DockPosition.left);

    // Move outline to right of editor
    manager.movePanel('outline', 'editor_main', DockPosition.right);
  }

  DockPanel _createPanel({
    required String id,
    required String title,
    required IconData icon,
    required Color color,
    required Widget content,
    bool closable = true,
  }) {
    return DockPanel(
      id: id,
      title: title,
      icon: icon,
      closable: closable,
      builder: (_) => content,
    );
  }

  void _addNewPanel() {
    _panelCounter++;
    final manager = ref.read(dockManagerProvider.notifier);
    manager.addPanel(
      DockPanel(
        id: 'dynamic_$_panelCounter',
        title: 'Tab $_panelCounter',
        icon: Icons.tab,
        builder: (_) => _DemoContent(
          title: 'Dynamic Panel $_panelCounter',
          color: Colors.primaries[_panelCounter % Colors.primaries.length],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Toolbar
          Container(
            height: 40,
            color: const Color(0xFF252526),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text(
                  'Dock Panel Demo',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                _ToolbarButton(
                  icon: Icons.add,
                  tooltip: 'Add Panel',
                  onPressed: _addNewPanel,
                ),
                _ToolbarButton(
                  icon: Icons.restart_alt,
                  tooltip: 'Reset Layout',
                  onPressed: () {
                    ref
                        .read(dockManagerProvider.notifier)
                        .setLayout(const DockLayout());
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _setupLayout(),
                    );
                  },
                ),
              ],
            ),
          ),
          // Dock area
          Expanded(
            child: DockTheme(
              data: const DockThemeData(),
              child: const DockArea(),
            ),
          ),
          // Status bar
          Container(
            height: 24,
            color: const Color(0xFF007ACC),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: const Row(
              children: [
                Icon(Icons.check_circle, size: 14, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Ready',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
                Spacer(),
                Text(
                  'dock_panel v0.1.0',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Toolbar Button ──────────────────────────────────────────

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16, color: Colors.white70),
      onPressed: onPressed,
      tooltip: tooltip,
      splashRadius: 14,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }
}

// ─── Demo Panel Widgets ──────────────────────────────────────

class _DemoContent extends StatelessWidget {
  const _DemoContent({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withValues(alpha: 0.2),
      alignment: Alignment.center,
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 20,
          fontWeight: FontWeight.w300,
        ),
      ),
    );
  }
}

class _FileExplorerPanel extends StatelessWidget {
  const _FileExplorerPanel();

  @override
  Widget build(BuildContext context) {
    final items = [
      ('lib/', Icons.folder, true),
      ('  main.dart', Icons.code, false),
      ('  model.dart', Icons.data_object, false),
      ('  widgets/', Icons.folder, true),
      ('    button.dart', Icons.code, false),
      ('    card.dart', Icons.code, false),
      ('test/', Icons.folder, true),
      ('  widget_test.dart', Icons.code, false),
      ('pubspec.yaml', Icons.settings, false),
      ('README.md', Icons.description, false),
    ];

    return Container(
      color: const Color(0xFF1E1E1E),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final (name, icon, isFolder) = items[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isFolder
                      ? const Color(0xFFDCB67A)
                      : const Color(0xFF6AADCE),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CodeEditorPanel extends StatelessWidget {
  const _CodeEditorPanel({required this.filename});

  final String filename;

  @override
  Widget build(BuildContext context) {
    final lines = filename == 'main.dart'
        ? [
            "import 'package:flutter/material.dart';",
            '',
            'void main() {',
            '  runApp(const MyApp());',
            '}',
            '',
            'class MyApp extends StatelessWidget {',
            '  const MyApp({super.key});',
            '',
            '  @override',
            '  Widget build(BuildContext context) {',
            '    return MaterialApp(',
            '      home: const HomePage(),',
            '    );',
            '  }',
            '}',
          ]
        : [
            'class User {',
            '  final String id;',
            '  final String name;',
            '  final String email;',
            '',
            '  const User({',
            '    required this.id,',
            '    required this.name,',
            '    required this.email,',
            '  });',
            '',
            '  Map<String, dynamic> toJson() => {',
            "    'id': id,",
            "    'name': name,",
            "    'email': email,",
            '  };',
            '}',
          ];

    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.all(12),
      child: SelectionArea(
        child: ListView.builder(
          itemCount: lines.length,
          itemBuilder: (context, index) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    lines[index],
                    style: const TextStyle(
                      color: Color(0xFFD4D4D4),
                      fontSize: 13,
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TerminalPanel extends StatelessWidget {
  const _TerminalPanel();

  @override
  Widget build(BuildContext context) {
    final lines = [
      r'$ flutter run -d windows',
      'Launching lib/main.dart on Windows in debug mode...',
      'Building Windows application...',
      '✓ Built build\\windows\\x64\\runner\\Debug\\dock_panel.exe',
      'Syncing files to device Windows...',
      'Flutter run key commands:',
      '  r  Hot reload',
      '  R  Hot restart',
      '  q  Quit',
      '',
      'An Observatory debugger is available at:',
      'http://127.0.0.1:8888/AbCdEfGh=/',
      '',
      r'$ _',
    ];

    return Container(
      color: const Color(0xFF181818),
      padding: const EdgeInsets.all(12),
      child: ListView.builder(
        itemCount: lines.length,
        itemBuilder: (context, index) {
          final line = lines[index];
          Color color = const Color(0xFFCCCCCC);
          if (line.startsWith(r'$')) {
            color = const Color(0xFF4EC9B0);
          } else if (line.startsWith('✓')) {
            color = const Color(0xFF6A9955);
          }
          return Text(
            line,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.6,
            ),
          );
        },
      ),
    );
  }
}

class _OutputPanel extends StatelessWidget {
  const _OutputPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF181818),
      padding: const EdgeInsets.all(12),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '[2024-01-15 14:30:22] Build completed successfully.',
            style: TextStyle(
              color: Color(0xFF6A9955),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          SizedBox(height: 4),
          Text(
            '[2024-01-15 14:30:22] 0 errors, 0 warnings.',
            style: TextStyle(
              color: Color(0xFFCCCCCC),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          SizedBox(height: 4),
          Text(
            '[2024-01-15 14:30:23] Hot reload applied in 245ms.',
            style: TextStyle(
              color: Color(0xFF569CD6),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _ProblemsPanel extends StatelessWidget {
  const _ProblemsPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF181818),
      padding: const EdgeInsets.all(12),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, size: 14, color: Color(0xFFCCA700)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Unused import: 'dart:io' (line 3)",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFFCCA700),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.info, size: 14, color: Color(0xFF569CD6)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Prefer const with constant constructors (line 15)',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF569CD6),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OutlinePanel extends StatelessWidget {
  const _OutlinePanel();

  @override
  Widget build(BuildContext context) {
    final items = [
      ('MyApp', Icons.class_, 0),
      ('build()', Icons.functions, 1),
      ('HomePage', Icons.class_, 0),
      ('_counter', Icons.data_usage, 1),
      ('_increment()', Icons.functions, 1),
      ('build()', Icons.functions, 1),
    ];

    return Container(
      color: const Color(0xFF1E1E1E),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final (name, icon, indent) = items[index];
          return Padding(
            padding: EdgeInsets.only(
              left: indent * 16.0 + 4,
              top: 4,
              bottom: 4,
            ),
            child: Row(
              children: [
                Icon(icon, size: 14, color: const Color(0xFF4EC9B0)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
