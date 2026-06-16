import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widgets/agent_workspace.dart';

/// 多Agent并行协作标签页
class MultiAgentPage extends ConsumerWidget {
  const MultiAgentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const AgentWorkspace();
  }
}
