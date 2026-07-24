import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../../core/db/tables/model_cards.dart';
import '../../core/l10n/l10n_ext.dart';
import '../../providers/database_provider.dart';
import '../../widgets/model_logo.dart';
import 'model_card_event_bus.dart';
import 'model_cards_page.dart';

/// 高性能模型卡片：使用局部状态 + RepaintBoundary 隔离重绘
class OptimizedModelCardTile extends StatefulWidget {
  final ModelCard card;
  const OptimizedModelCardTile({required this.card, super.key});

  @override
  State<OptimizedModelCardTile> createState() => _OptimizedModelCardTileState();
}

class _OptimizedModelCardTileState extends State<OptimizedModelCardTile> {
  // 使用局部状态，避免依赖全局 Provider 刷新
  late bool _isDefault;
  StreamSubscription? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _isDefault = widget.card.isDefault;

    // 监听其他卡片的默认变化事件
    _eventSubscription = ModelCardEventBus().onDefaultChanged.listen((
      newDefaultId,
    ) {
      if (newDefaultId != widget.card.id && _isDefault) {
        // 其他卡片被设为默认，当前卡片取消默认
        if (mounted) {
          setState(() => _isDefault = false);
        }
      }
    });
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(OptimizedModelCardTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只有当实际数据变化时才更新
    if (widget.card.isDefault != oldWidget.card.isDefault) {
      _isDefault = widget.card.isDefault;
    }
  }

  void _handleTap() {
    if (_isDefault) return; // 已经是默认，不处理

    // 立即更新 UI（乐观更新）
    setState(() => _isDefault = true);

    // 通知其他卡片取消默认状态
    ModelCardEventBus().notifyDefaultChanged(widget.card.id);

    // 直接调用 DAO，完全绕过 Provider 的状态更新
    final container = ProviderScope.containerOf(context);
    final dao = container.read(modelCardsDaoProvider);
    dao.setDefault(widget.card.id).catchError((e) {
      // 失败则回滚 UI
      if (mounted) {
        setState(() => _isDefault = widget.card.isDefault);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maskedUrl = _maskUrl(widget.card.baseUrl);

    // RepaintBoundary 隔离重绘，避免影响其他卡片
    return RepaintBoundary(
      child: Material(
        color: _isDefault
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _handleTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isDefault ? colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isDefault
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: _isDefault
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    ModelLogo(
                      logoPath: widget.card.logoPath,
                      name: widget.card.name,
                      modelId: widget.card.modelId,
                      size: 32,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.card.name,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_isDefault)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.s.modelsDefault,
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                _kv(context, 'Model', widget.card.modelId, colorScheme),
                const SizedBox(height: 2),
                _kv(context, 'URL', maskedUrl, colorScheme),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: context.s.commonEdit,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _showEditDialog(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: context.s.commonDelete,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _confirmDelete(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(
    BuildContext context,
    String k,
    String v,
    ColorScheme colorScheme,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            k,
            style: TextStyle(fontSize: 12, color: colorScheme.outline),
          ),
        ),
        Expanded(
          child: Text(
            v.isEmpty ? '—' : v,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'Consolas',
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _maskUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}/***';
    } catch (_) {
      if (url.length > 20) return '${url.substring(0, 20)}***';
      return url;
    }
  }

  void _showEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => ModelCardDialog(
        initialName: widget.card.name,
        initialBaseUrl: widget.card.baseUrl,
        initialApiKey: widget.card.apiKey,
        initialModelId: widget.card.modelId,
        initialLogoPath: widget.card.logoPath,
        initialProvider: widget.card.provider,
        initialContextWindow: widget.card.contextWindow,
        initialMaxOutputTokens: widget.card.maxOutputTokens,
        cardId: widget.card.id,
        onSave:
            (
              name,
              baseUrl,
              apiKey,
              modelId,
              logoPath,
              provider,
              contextWindow,
              maxOutputTokens,
            ) {
              final container = ProviderScope.containerOf(context);
              final updated = widget.card.copyWith(
                name: name,
                baseUrl: baseUrl,
                apiKey: apiKey,
                modelId: modelId,
                logoPath: logoPath,
                provider: provider,
                contextWindow: contextWindow,
                maxOutputTokens: maxOutputTokens,
              );
              container.read(modelCardsProvider.notifier).updateCard(updated);
            },
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.modelsDeleteTitle),
        content: Text(context.s.modelsDeleteConfirm(widget.card.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.s.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              container
                  .read(modelCardsProvider.notifier)
                  .deleteCard(widget.card.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.s.commonDelete),
          ),
        ],
      ),
    );
  }
}
