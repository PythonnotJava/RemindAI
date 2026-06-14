import 'package:flutter/widgets.dart';
import '../../l10n/app_localizations.dart';

/// 便捷扩展 — 通过 context.s 获取国际化字符串
///
/// 用法: `context.s.settingsTitle` 代替 `S.of(context).settingsTitle`
extension LocalizationExt on BuildContext {
  S get s => S.of(this);
}
