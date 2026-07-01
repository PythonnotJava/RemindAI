import 'dart:convert';

import '../../logger/app_logger.dart';
import '../../toolshell/system_executor.dart';
import '../agent_hook.dart';

/// System 元技能 Hook — 首次会话自动探测开发环境
///
/// 解决的问题: SKILL.md 指示模型"首次对话前主动 system_probe"，
/// 但模型实际上从不这么做——它倾向于直接跑命令，失败再说。
///
/// 改为 Hook 层在 onSessionStart 时自动执行一次全量探测，
/// 结果以精简格式注入 context。模型后续决策就有依据了：
/// - 有 pnpm → 用 pnpm 而非 npm
/// - 有 rg → 用 ripgrep 而非 findstr
/// - 无 docker → 不建议容器化
class SystemProbeHook extends AgentHook {
  final SystemExecutor _executor;

  SystemProbeHook() : _executor = SystemExecutor();

  @override
  Future<void> onSessionStart(
    int conversationId,
    List<Map<String, dynamic>> messages,
  ) async {
    try {
      final resultJson = await _executor.run('system_probe', {
        'category': 'all',
      });

      final data = jsonDecode(resultJson) as Map<String, dynamic>;
      if (data['status'] != 'ok') return;

      final summary = _buildSummary(data);
      if (summary.isEmpty) return;

      messages.add({'role': 'system', 'content': '[系统环境]\n$summary'});

      AppLogger.instance.log('[SystemProbe] 环境探测完成，已注入上下文');
      print('[SystemProbe] ✓ 开发环境已探测并注入');
    } catch (e) {
      AppLogger.instance.log('[SystemProbe] 探测失败: $e');
    }
  }

  /// 从探测结果构建精简摘要
  ///
  /// 只列出已安装的工具（不列未安装的），按类别分组。
  /// 控制在合理长度内，不占用太多 token。
  String _buildSummary(Map<String, dynamic> data) {
    final parts = <String>[];

    // 系统基本信息
    final sys = data['system'] as Map<String, dynamic>?;
    if (sys != null) {
      parts.add('OS: ${sys['os']} ${sys['os_version'] ?? ''}');
    }

    // 各类别已安装的工具
    const categoryLabels = {
      'runtime': '运行时',
      'package_manager': '包管理',
      'vcs': '版本控制',
      'build': '构建工具',
      'container': '容器',
      'search': '搜索',
      'editor': '编辑器',
      'db': '数据库',
      'network': '网络',
      'doc': '文档',
    };

    for (final entry in categoryLabels.entries) {
      final tools = data[entry.key];
      if (tools == null) continue;

      final found = <String>[];
      for (final tool in (tools as List)) {
        if (tool is Map && tool['found'] == true) {
          final name = tool['name'] as String;
          final version = tool['version'] as String?;
          final short = version != null ? _shortenVersion(version) : null;
          if (short != null) {
            found.add('$name($short)');
          } else {
            found.add(name);
          }
        }
      }

      if (found.isNotEmpty) {
        parts.add('${entry.value}: ${found.join(', ')}');
      }
    }

    return parts.join('\n');
  }

  /// 缩短版本字符串（只取核心版本号）
  /// 如果无法提取有效版本号则返回 null（调用方不显示版本）
  String? _shortenVersion(String version) {
    // 尝试匹配 x.y.z 格式
    final match = RegExp(r'(\d+\.\d+(?:\.\d+)?)').firstMatch(version);
    if (match != null) return match.group(1)!;
    // 无有效版本号
    return null;
  }
}
