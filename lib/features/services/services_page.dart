import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n_ext.dart';
import '../skills/skills_page.dart';
import '../mcp/mcp_page.dart';
import '../knowledge/knowledge_base_page.dart';
import '../online_service/online_service_page.dart';
import '../search/search_page.dart';
import '../server/server_page.dart';
import '../toolchain/toolchain_page.dart';

/// 合并的"服务"页 — 包含技能管理、MCP 服务、搜索服务、工具链、服务器和在线服务
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
    _tabController = TabController(length: 7, vsync: this);
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
              icon: const Icon(Icons.auto_stories_outlined, size: 18),
              text: context.s.servicesKbTab,
            ),
            Tab(
              icon: const Icon(Icons.travel_explore, size: 18),
              text: context.s.servicesSearchTab,
            ),
            Tab(
              icon: const Icon(Icons.build_outlined, size: 18),
              text: context.s.servicesToolchainTab,
            ),
            Tab(
              icon: const Icon(Icons.dns_outlined, size: 18),
              text: context.s.servicesServerTab,
            ),
            Tab(
              icon: const Icon(Icons.cloud_outlined, size: 18),
              text: context.s.servicesOnlineTab,
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
        children: const [
          SkillsPageBody(),
          McpPageBody(),
          KnowledgeBasePageBody(),
          SearchPageBody(),
          ToolchainPageBody(),
          ServerPageBody(),
          OnlineServicePageBody(),
        ],
      ),
    );
  }
}
