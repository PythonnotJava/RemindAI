import 'dart:async';
import 'dart:convert';

import '../tool_middleware.dart';

/// 权限中间件 — normal 模式下写/删/执行操作需用户确认
class PermissionMiddleware extends ToolMiddleware {
  /// 需要确认的工具名列表
  static const _needsApproval = {
    'toolshell_write',
    'toolshell_delete',
    'toolshell_exec',
    'toolshell_run_python',
  };

  /// 权限确认回调 — 通知 UI 弹出确认卡片,等待用户响应
  /// 返回 true = 允许, false = 拒绝
  final Future<bool> Function(String toolName, Map<String, dynamic> args)
  onPermissionRequest;

  PermissionMiddleware({required this.onPermissionRequest});

  @override
  Future<String> handle(
    String toolName,
    Map<String, dynamic> args,
    Future<String> Function(String, Map<String, dynamic>) next,
  ) async {
    if (_needsApproval.contains(toolName)) {
      final approved = await onPermissionRequest(toolName, args);
      if (!approved) {
        return jsonEncode({
          'status': 'error',
          'code': 'PERMISSION_DENIED',
          'detail': '用户拒绝了操作',
        });
      }
    }
    return next(toolName, args);
  }
}
