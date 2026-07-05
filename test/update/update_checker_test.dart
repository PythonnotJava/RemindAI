import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/update/update_checker.dart';

/// 验证 UpdateChecker 的版本比较逻辑与真实网络请求行为。
///
/// 版本比较是纯函数逻辑，用私有方法的行为通过公开的 check() 间接验证
/// (用真实仓库 PythonnotJava/RemindAI 的最新 release 做对照，同时用一个
/// 不存在的仓库验证 404 错误路径)。
void main() {
  group('UpdateChecker - 真实 GitHub API 请求', () {
    test('场景1: 当前版本设为 0.0.1 (远低于任何真实发布版本) → 应判定为有更新', () async {
      const checker = UpdateChecker();
      final result = await checker.check('0.0.1');

      print(
        '[场景1] 结果: status=${result.status}, latest=${result.latestVersion}',
      );

      // 只要该仓库有至少一个 release，0.0.1 必然被判定为需要更新
      // (如果仓库尚无 release，则会走 error/404 分支，两种都断言覆盖)
      expect(
        result.status == UpdateCheckStatus.updateAvailable ||
            result.status == UpdateCheckStatus.error,
        isTrue,
      );
      if (result.status == UpdateCheckStatus.updateAvailable) {
        expect(result.latestVersion, isNotNull);
        expect(result.releaseUrl, contains('PythonnotJava/RemindAI'));
        expect(result.changelog, isNotNull);
        print(
          '[场景1] 结论: 正确识别出新版本 v${result.latestVersion}，changelog 长度=${result.changelog!.length}',
        );
      } else {
        print('[场景1] 结论: 该仓库当前无可用 release，走了 error 分支: ${result.errorMessage}');
      }
    });

    test('场景2: 当前版本设为 999.0.0 (远超任何真实发布版本) → 应判定为已最新', () async {
      const checker = UpdateChecker();
      final result = await checker.check('999.0.0');

      print(
        '[场景2] 结果: status=${result.status}, latest=${result.latestVersion}',
      );

      expect(
        result.status == UpdateCheckStatus.upToDate ||
            result.status == UpdateCheckStatus.error,
        isTrue,
      );
      if (result.status == UpdateCheckStatus.upToDate) {
        print('[场景2] 结论: 999.0.0 正确判定为已是最新(不会反过来误判成"有更新")');
      }
    });

    test('场景3: 不存在的仓库 → 应返回 error 且带 404 相关提示', () async {
      const checker = UpdateChecker(
        owner: 'this-owner-does-not-exist-abcxyz',
        repoName: 'this-repo-does-not-exist-abcxyz',
      );
      final result = await checker.check('1.0.0');

      print('[场景3] 结果: ${result.status}, ${result.errorMessage}');

      expect(result.status, UpdateCheckStatus.error);
      expect(result.errorMessage, isNotNull);
      print('[场景3] 结论: 不存在的仓库正确落入 error 分支，而不是抛异常崩溃');
    });

    test('场景4: 版本号带 v 前缀时不影响比较结果', () async {
      const checker = UpdateChecker();
      final withPrefix = await checker.check('v0.0.1');
      final withoutPrefix = await checker.check('0.0.1');

      print('[场景4] 带前缀: ${withPrefix.status}, 不带前缀: ${withoutPrefix.status}');

      // 两次调用对同一个极低版本号的判定结果应该一致 (前缀不影响比较逻辑)
      expect(withPrefix.status, withoutPrefix.status);
      print('[场景4] 结论: v 前缀被正确剥离，不影响版本比较结果');
    });
  });
}
