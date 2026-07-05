import 'package:dio/dio.dart';

/// 检查更新的结果。
///
/// [status] 区分三种终态，UI 层据此渲染不同的弹窗内容：
/// - [UpdateCheckStatus.upToDate]：已是最新版本
/// - [UpdateCheckStatus.updateAvailable]：发现新版本，附带 changelog
/// - [UpdateCheckStatus.error]：网络异常/接口异常/无发布记录等
enum UpdateCheckStatus { upToDate, updateAvailable, error }

class UpdateCheckResult {
  final UpdateCheckStatus status;

  /// 最新版本号 (已去掉可能的 'v' 前缀)，仅在 upToDate/updateAvailable 时有值
  final String? latestVersion;

  /// Release 的 markdown 说明 (GitHub release body)，仅 updateAvailable 时有值
  final String? changelog;

  /// Release 详情页链接，引导用户手动跳转下载，仅 updateAvailable 时有值
  final String? releaseUrl;

  /// error 状态下的错误描述 (已本地化为对用户友好的文案)
  final String? errorMessage;

  const UpdateCheckResult._({
    required this.status,
    this.latestVersion,
    this.changelog,
    this.releaseUrl,
    this.errorMessage,
  });

  factory UpdateCheckResult.upToDate(String latestVersion) =>
      UpdateCheckResult._(
        status: UpdateCheckStatus.upToDate,
        latestVersion: latestVersion,
      );

  factory UpdateCheckResult.updateAvailable({
    required String latestVersion,
    required String changelog,
    required String releaseUrl,
  }) => UpdateCheckResult._(
    status: UpdateCheckStatus.updateAvailable,
    latestVersion: latestVersion,
    changelog: changelog,
    releaseUrl: releaseUrl,
  );

  factory UpdateCheckResult.error(String message) => UpdateCheckResult._(
    status: UpdateCheckStatus.error,
    errorMessage: message,
  );
}

/// 检查 GitHub Releases 是否有新版本 —— 纯手动触发，不做任何后台轮询/
/// 自动弹窗，也不提供应用内下载安装，只负责"查询 + 对比版本号 + 把
/// changelog 和 release 页面链接交给上层"，下载安装完全交还给用户。
class UpdateChecker {
  final String owner;
  final String repoName;

  const UpdateChecker({
    this.owner = 'PythonnotJava',
    this.repoName = 'RemindAI',
  });

  /// 拉取最新 release 并与 [currentVersion] 比较。
  Future<UpdateCheckResult> check(String currentVersion) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    try {
      final resp = await dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/$owner/$repoName/releases/latest',
        options: Options(headers: {'Accept': 'application/vnd.github+json'}),
      );
      final data = resp.data;
      if (data == null) {
        return UpdateCheckResult.error('接口返回了空数据，请稍后再试');
      }

      final tagName = (data['tag_name'] as String?)?.trim() ?? '';
      final latest = _stripVPrefix(tagName);
      if (latest.isEmpty) {
        return UpdateCheckResult.error('未能解析最新版本号，请稍后再试');
      }

      final body = (data['body'] as String?)?.trim() ?? '';
      final htmlUrl =
          (data['html_url'] as String?) ??
          'https://github.com/$owner/$repoName/releases/tag/$tagName';

      final cmp = _compareVersions(latest, _stripVPrefix(currentVersion));
      if (cmp > 0) {
        return UpdateCheckResult.updateAvailable(
          latestVersion: latest,
          changelog: body.isEmpty ? '（此版本未附带更新说明）' : body,
          releaseUrl: htmlUrl,
        );
      }
      return UpdateCheckResult.upToDate(latest);
    } on DioException catch (e) {
      return UpdateCheckResult.error(_describeDioError(e));
    } catch (e) {
      return UpdateCheckResult.error('检查更新失败: $e');
    } finally {
      dio.close();
    }
  }

  String _stripVPrefix(String v) =>
      v.startsWith('v') || v.startsWith('V') ? v.substring(1) : v;

  /// 语义版本比较: 返回 >0 表示 a 更新, <0 表示 b 更新, 0 表示相同。
  /// 只比较数字段 (major.minor.patch...)，非数字后缀 (如 -beta.1) 被忽略，
  /// 段数不一致时缺的段按 0 补齐 (如 1.0 视为 1.0.0)。
  int _compareVersions(String a, String b) {
    List<int> parse(String v) {
      final numericPart = v.split(RegExp(r'[-+]')).first;
      return numericPart
          .split('.')
          .map((s) => int.tryParse(s.trim()) ?? 0)
          .toList();
    }

    final pa = parse(a);
    final pb = parse(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final ai = i < pa.length ? pa[i] : 0;
      final bi = i < pb.length ? pb[i] : 0;
      if (ai != bi) return ai - bi;
    }
    return 0;
  }

  String _describeDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时，请检查网络后重试';
      case DioExceptionType.connectionError:
        return '网络连接失败，请检查网络后重试';
      default:
        final status = e.response?.statusCode;
        if (status == 404) {
          return '该仓库暂无已发布的版本';
        }
        if (status == 403) {
          return '请求过于频繁，请稍后再试 (GitHub API 限流)';
        }
        return '检查更新失败 (HTTP ${status ?? '未知'})';
    }
  }
}
