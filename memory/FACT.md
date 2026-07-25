# RemindAI 项目知识

## 上下文压缩系统

### 当前配置
- 触发阈值：50% contextWindow（gpt-5 使用 35%）
- 保留策略：最近 4 轮对话
- 位置：
  - `lib/core/agent/transformers/context_compactor.dart`
  - `lib/core/toolshell/agent_loop.dart`（兜底逻辑）

### 已知问题与修复
1. **工具调用丢失（已修复）**
   - 旧逻辑删除整个 assistant 消息导致 "No tool output found" 错误
   - 新逻辑只移除孤立的 tool_calls，保留消息本身
   - 参考 Hermes 的 `_sanitize_tool_pairs` 实现

2. **压缩后仍超阈值（已添加验证）**
   - 预检：压缩前检查保真区大小
   - 后验：压缩后验证是否仍超阈值
   - 记录警告日志，建议调整 keepRecentTurns

### 三家压缩策略对比
- **Cherry Studio**: 依赖 Claude SDK，事件驱动
- **Hermes**: 完整自研（4600行），Token预算驱动，双向边界对齐
- **RemindAI**: 轻量级自研（600行），按轮数保留，Cache-Aligned摘要优化

### 待优化方向
- 混合保留策略：轮数下限 + Token 预算上限
- 工具结果修剪：压缩前生成信息性摘要
- 双向边界对齐：更严格的边界保护

## Gallery 工具
- 位置：`lib/features/tools/gallery/`
- 特性：星空动画，生命周期管理（后台暂停）
- 已修复：添加 `WidgetsBindingObserver` 防止后台占用

## 代码质量
- 已修复所有 Flutter info 警告
- 使用 `withValues(alpha:)` 替代 `withOpacity`
- 使用 `WidgetState` 替代 `MaterialState`
