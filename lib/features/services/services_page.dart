import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n_ext.dart';
import '../skills/skills_page.dart';
import '../mcp/mcp_page.dart';
import '../search/search_page.dart';

/// 合并的"服务"页 — 包含技能管理、MCP 服务和搜索服务三个子页面
class ServicesPage extends ConsumerStatefulWidget {
  const ServicesPage({super.key});

  @override
  ConsumerState<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends ConsumerState<ServicesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.s.servicesTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.extension, size: 18),
              text: context.s.servicesSkillsTab,
            ),
            Tab(icon: const Icon(Icons.hub, size: 18), text: 'MCP'),
            Tab(
              icon: const Icon(Icons.travel_explore, size: 18),
              text: context.s.servicesSearchTab,
            ),
          ],
          labelStyle: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          indicatorSize: TabBarIndicatorSize.label,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [SkillsPageBody(), McpPageBody(), SearchPageBody()],
      ),
    );
  }
}
