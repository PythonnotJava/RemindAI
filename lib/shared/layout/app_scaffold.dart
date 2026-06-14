import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/expert/expert.dart';
import '../../features/chat/chat_page.dart';
import '../../features/chat/chat_provider.dart';
import '../../features/chat/widgets/new_workspace_dialog.dart';
import '../../features/experts/experts_page.dart';
import '../../features/history/history_page.dart';
import '../../features/models/model_cards_page.dart';
import '../../features/services/services_page.dart';
import '../../features/tools/tools_page.dart';
import '../../features/memory/memory_page.dart';
import '../../features/multi_agent/multi_agent_page.dart';
import '../../features/logs/logs_page.dart';
import '../../features/settings/settings_page.dart';
import '../../providers/experts_provider.dart';
import '../../core/l10n/l10n_ext.dart';

/// 导航项定义
class _NavItem {
  final String id;
  final String Function(BuildContext) label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() pageBuilder;

  _NavItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.pageBuilder,
  });
}

class AppScaffold extends StatefulWidget {
  const AppScaffold({super.key});

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  int _selectedIndex = 0;
  List<String>? _navOrder; // 用户自定义顺序 (id列表)
  bool _loaded = false;

  /// 所有可用的导航项（默认顺序）
  static List<_NavItem> _allNavItems(
    void Function(WidgetRef, Expert) startExpertChat,
    VoidCallback navigateToChat,
  ) => [
    _NavItem(
      id: 'chat',
      label: (context) => context.s.navChat,
      icon: Icons.chat_outlined,
      selectedIcon: Icons.chat,
      pageBuilder: () => const ChatPage(),
    ),
    _NavItem(
      id: 'experts',
      label: (context) => context.s.navExperts,
      icon: Icons.person_search_outlined,
      selectedIcon: Icons.person_search,
      pageBuilder: () => const _ExpertsPagePlaceholder(), // 需要特殊处理
    ),
    _NavItem(
      id: 'history',
      label: (context) => context.s.navHistory,
      icon: Icons.history_outlined,
      selectedIcon: Icons.history,
      pageBuilder: () => const _HistoryPagePlaceholder(),
    ),
    _NavItem(
      id: 'models',
      label: (context) => context.s.navModels,
      icon: Icons.credit_card_outlined,
      selectedIcon: Icons.credit_card,
      pageBuilder: () => const ModelCardsPage(),
    ),
    _NavItem(
      id: 'services',
      label: (context) => context.s.navMcp,
      icon: Icons.extension_outlined,
      selectedIcon: Icons.extension,
      pageBuilder: () => const ServicesPage(),
    ),
    _NavItem(
      id: 'tools',
      label: (context) => context.s.navTools,
      icon: Icons.build_outlined,
      selectedIcon: Icons.build,
      pageBuilder: () => const ToolsPage(),
    ),
    _NavItem(
      id: 'memory',
      label: (context) => context.s.navMemory,
      icon: Icons.memory_outlined,
      selectedIcon: Icons.memory,
      pageBuilder: () => const MemoryPage(),
    ),
    _NavItem(
      id: 'logs',
      label: (context) => context.s.navLogs,
      icon: Icons.article_outlined,
      selectedIcon: Icons.article,
      pageBuilder: () => const LogsPage(),
    ),
    _NavItem(
      id: 'collab',
      label: (context) => context.s.navMultiAgent,
      icon: Icons.groups_outlined,
      selectedIcon: Icons.groups,
      pageBuilder: () => const MultiAgentPage(),
    ),
    _NavItem(
      id: 'settings',
      label: (context) => context.s.navSettings,
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      pageBuilder: () => const SettingsPage(),
    ),
  ];

  List<_NavItem> get _orderedItems {
    final all = _allNavItems(_startExpertChat, _navigateToChat);
    if (_navOrder == null) return all;
    final map = {for (final item in all) item.id: item};
    final ordered = <_NavItem>[];
    for (final id in _navOrder!) {
      if (map.containsKey(id)) {
        ordered.add(map.remove(id)!);
      }
    }
    // 追加任何新增的（不在保存列表中的）
    ordered.addAll(map.values);
    return ordered;
  }

  @override
  void initState() {
    super.initState();
    _loadNavOrder();
  }

  Future<void> _loadNavOrder() async {
    try {
      final file = await _navOrderFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = (jsonDecode(content) as List).cast<String>();
        if (list.isNotEmpty) {
          _navOrder = list;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _saveNavOrder() async {
    try {
      final file = await _navOrderFile();
      final dir = file.parent;
      if (!await dir.exists()) await dir.create(recursive: true);
      await file.writeAsString(jsonEncode(_navOrder));
    } catch (_) {}
  }

  Future<File> _navOrderFile() async {
    final appDir = await getApplicationSupportDirectory();
    return File(p.join(appDir.path, 'nav_order.json'));
  }

  void _navigateToChat() {
    final items = _orderedItems;
    final idx = items.indexWhere((e) => e.id == 'chat');
    if (idx >= 0) setState(() => _selectedIndex = idx);
  }

  void _startExpertChat(WidgetRef ref, Expert expert) {
    ref.read(activeExpertProvider.notifier).state = expert;
    showDialog(
      context: context,
      builder: (_) => const NewWorkspaceDialog(),
    ).then((_) {
      final workDir = ref.read(workingDirectoryProvider);
      if (workDir.isNotEmpty) {
        _navigateToChat();
      } else {
        ref.read(activeExpertProvider.notifier).state = null;
      }
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    final items = List<_NavItem>.from(_orderedItems);
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);
    _navOrder = items.map((e) => e.id).toList();
    // 调整选中索引
    if (_selectedIndex == oldIndex) {
      _selectedIndex = newIndex;
    } else if (oldIndex < _selectedIndex && newIndex >= _selectedIndex) {
      _selectedIndex--;
    } else if (oldIndex > _selectedIndex && newIndex <= _selectedIndex) {
      _selectedIndex++;
    }
    setState(() {});
    _saveNavOrder();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    return Consumer(
      builder: (context, ref, _) {
        final items = _orderedItems;

        final pages = items.map((item) {
          Widget page;
          // 特殊页面需要回调
          if (item.id == 'experts') {
            page = ExpertsPage(onStartChat: (e) => _startExpertChat(ref, e));
          } else if (item.id == 'history') {
            page = HistoryPage(onNavigateToChat: _navigateToChat);
          } else {
            page = item.pageBuilder();
          }
          // 用 KeyedSubtree 保证拖动排序时不会 dispose/rebuild
          return KeyedSubtree(key: ValueKey(item.id), child: page);
        }).toList();

        return Scaffold(
          body: Row(
            children: [
              // 自定义可拖动导航栏
              _DraggableNavRail(
                items: items,
                selectedIndex: _selectedIndex,
                onSelected: (i) => setState(() => _selectedIndex = i),
                onReorder: _onReorder,
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: IndexedStack(index: _selectedIndex, children: pages),
              ),
            ],
          ),
        );
      },
    );
  }
}

// 占位类（不会实际被使用，pageBuilder 在 build 中被覆盖）
class _ExpertsPagePlaceholder extends StatelessWidget {
  const _ExpertsPagePlaceholder();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _HistoryPagePlaceholder extends StatelessWidget {
  const _HistoryPagePlaceholder();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// PLACEHOLDER_FOR_DRAGGABLE_NAV_RAIL

/// 支持拖动排序的侧边导航栏
class _DraggableNavRail extends StatelessWidget {
  const _DraggableNavRail({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.onReorder,
  });

  final List<_NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final void Function(int oldIndex, int newIndex) onReorder;

  void _showLogoDialog(BuildContext context) {
    // 根据当前语言选择彩蛋图片
    final locale = Localizations.localeOf(context).languageCode;
    final eggAsset = locale == 'en'
        ? 'assets/icons/logo_egg_en.png'
        : 'assets/icons/logo_egg_zh.png';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(40),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.white.withValues(alpha: 0.6),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.5)
                      : Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.8),
                width: 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Image.asset(eggAsset, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      width: 72,
      child: ColoredBox(
        color: colorScheme.surface,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 防御：约束尚未稳定时不渲染内容，避免瞬态扭曲
              if (constraints.maxHeight <= 0) {
                return const SizedBox.shrink();
              }

              return SingleChildScrollView(
                physics: constraints.maxHeight < (items.length * 50 + 60)
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    children: [
                      // Logo（点击彩蛋：放大显示）
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: GestureDetector(
                          onTap: () => _showLogoDialog(context),
                          child: _GlassLogo(
                            asset:
                                Localizations.localeOf(context).languageCode ==
                                    'en'
                                ? 'assets/icons/logo_egg_en.png'
                                : 'assets/icons/logo_egg_zh.png',
                            size: 36,
                          ),
                        ),
                      ),
                      // 导航项
                      ...List.generate(items.length, (index) {
                        final item = items[index];
                        final selected = index == selectedIndex;
                        return LongPressDraggable<int>(
                          data: index,
                          axis: Axis.vertical,
                          feedback: Material(
                            elevation: 4,
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: _NavTile(
                              item: item,
                              selected: selected,
                              onTap: () {},
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.3,
                            child: _NavTile(
                              item: item,
                              selected: selected,
                              onTap: () {},
                            ),
                          ),
                          child: DragTarget<int>(
                            onAcceptWithDetails: (details) {
                              onReorder(details.data, index);
                            },
                            builder: (context, candidateData, rejectedData) {
                              return _NavTile(
                                item: item,
                                selected: selected,
                                onTap: () => onSelected(index),
                              );
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 单个导航 tile
class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.secondaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                size: 22,
                color: selected
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label(context),
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 水润拟态 Logo — 透明背景 + 光晕边框 + 柔和阴影
class _GlassLogo extends StatelessWidget {
  final String asset;
  final double size;
  const _GlassLogo({required this.asset, required this.size});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.25),
        boxShadow: [
          // 外发光
          BoxShadow(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.6),
            blurRadius: 8,
            spreadRadius: 0.5,
          ),
          // 投影
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.4)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.7),
          width: 0.8,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25 - 0.8),
        child: Image.asset(asset, fit: BoxFit.contain),
      ),
    );
  }
}
