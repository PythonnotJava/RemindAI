import 'package:flutter/material.dart';

import '../../core/l10n/l10n_ext.dart';
import '../settings/widgets/api_server_section.dart';

/// 服务器页面 — 对外 API 服务的统一管理入口 (独立页面形态)。
class ServerPage extends StatelessWidget {
  const ServerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.s.serverTitle)),
      body: const ServerPageBody(),
    );
  }
}

/// 服务器管理的内容体 (可独立嵌入到其他容器, 如"服务"页的 Tab)。
///
/// 把三个对外端点 (OpenAI 聚合 / Claude 聚合 / Claude 纯代理) 的开关、
/// 端口/令牌、模型/技能/MCP/记忆/搜索绑定及局域网安全设置集中于此。
class ServerPageBody extends StatelessWidget {
  const ServerPageBody({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = context.s;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Icon(Icons.dns_outlined, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              s.serverApiServiceTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          s.serverApiServiceDesc,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        const ApiServerSection(),
      ],
    );
  }
}
