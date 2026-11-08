import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/toolshell/android_executor.dart';

/// vivo 风格的安装确认弹窗（真机 dump 的结构精简版）。
const String _vivoInstallDialogXml =
    "<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>"
    '<hierarchy rotation="0">'
    '<node index="0" text="" resource-id="" class="android.widget.FrameLayout" '
    'package="com.vivo.installer" content-desc="" checkable="false" checked="false" '
    'clickable="false" enabled="true" bounds="[0,0][1260,2800]" drawing-order="0" hint="">'
    '<node index="0" text="风险检测结果" resource-id="" class="android.widget.TextView" '
    'package="com.vivo.installer" content-desc="" checkable="false" checked="false" '
    'clickable="false" enabled="true" bounds="[80,900][1180,1000]" />'
    '<node index="1" text="已了解风险检测结果" resource-id="com.vivo.installer:id/risk" '
    'class="android.widget.CheckBox" package="com.vivo.installer" content-desc="" '
    'checkable="true" checked="false" clickable="true" enabled="true" '
    'bounds="[80,1100][700,1180]" />'
    '<node index="2" text="继续安装" resource-id="com.vivo.installer:id/install" '
    'class="android.widget.Button" package="com.vivo.installer" content-desc="" '
    'checkable="false" checked="false" clickable="true" enabled="true" '
    'bounds="[80,2400][1180,2520]" />'
    '<node index="3" text="取消安装" resource-id="com.vivo.installer:id/cancel" '
    'class="android.widget.Button" package="com.vivo.installer" content-desc="" '
    'checkable="false" checked="false" clickable="true" enabled="true" '
    'bounds="[80,2540][1180,2660]" />'
    '</node></hierarchy>';

void main() {
  group('extractUiNodes', () {
    test('只保留有文本/可点/可勾选的节点，并解析坐标', () {
      final nodes = extractUiNodes(_vivoInstallDialogXml);

      // 根节点没有文本也不可点，应被过滤
      expect(nodes, hasLength(4));
      expect(nodes.map((n) => n.text), contains('已了解风险检测结果'));

      final checkbox = nodes.firstWhere(
        (n) => n.text == '已了解风险检测结果',
      );
      expect(checkbox.checkable, isTrue);
      expect(checkbox.checked, isFalse);
      expect(checkbox.bounds, '[80,1100][700,1180]');
      expect(checkbox.centerX, (80 + 700) ~/ 2);
      expect(checkbox.centerY, (1100 + 1180) ~/ 2);
    });

    test('解析 XML 转义字符', () {
      const xml =
          '<hierarchy><node text="A &amp; B &quot;quoted&quot;" '
          'bounds="[0,0][10,10]" clickable="true" /></hierarchy>';
      final nodes = extractUiNodes(xml);
      expect(nodes.single.text, 'A & B "quoted"');
    });

    test('空文本的纯容器不进入结果', () {
      const xml =
          '<hierarchy><node text="" content-desc="" clickable="false" '
          'checkable="false" bounds="[0,0][10,10]" /></hierarchy>';
      expect(extractUiNodes(xml), isEmpty);
    });
  });

  group('pickInstallTarget', () {
    test('先勾风险确认，再点继续安装', () {
      final nodes = extractUiNodes(_vivoInstallDialogXml);

      final first = pickInstallTarget(nodes);
      expect(first, isNotNull);
      expect(first!.node.text, '已了解风险检测结果');
      expect(first.reason, contains('勾选'));

      // 勾选之后再读屏：勾选框 checked=true，应改为点「继续安装」
      final checkedXml = _vivoInstallDialogXml.replaceFirst(
        'checked="false" clickable="true" enabled="true" '
        'bounds="[80,1100][700,1180]"',
        'checked="true" clickable="true" enabled="true" '
        'bounds="[80,1100][700,1180]"',
      );
      final next = pickInstallTarget(extractUiNodes(checkedXml));
      expect(next, isNotNull);
      expect(next!.node.text, '继续安装');
      expect(next.reason, contains('确认安装'));
    });

    test('绝不点「取消安装」这类按钮', () {
      const xml =
          '<hierarchy><node text="取消安装" clickable="true" '
          'bounds="[0,0][100,100]" /></hierarchy>';
      expect(pickInstallTarget(extractUiNodes(xml)), isNull);
    });

    test('长词优先：继续安装 胜过 安装', () {
      const xml =
          '<hierarchy>'
          '<node text="安装" clickable="true" bounds="[0,0][100,100]" />'
          '<node text="继续安装" clickable="true" bounds="[0,200][100,300]" />'
          '</hierarchy>';
      final target = pickInstallTarget(extractUiNodes(xml));
      expect(target?.node.text, '继续安装');
    });

    test('屏幕上没有弹窗时返回 null', () {
      const xml =
          '<hierarchy><node text="设置" clickable="true" '
          'bounds="[0,0][100,100]" /></hierarchy>';
      expect(pickInstallTarget(extractUiNodes(xml)), isNull);
    });

    test('已勾选的勾选框不会被重复点（否则会取消勾选）', () {
      const xml =
          '<hierarchy><node text="已了解风险" checkable="true" checked="true" '
          'clickable="true" bounds="[0,0][100,100]" /></hierarchy>';
      expect(pickInstallTarget(extractUiNodes(xml)), isNull);
    });
  });

  test('parseBounds 容错', () {
    expect(parseBounds('[10,20][30,40]'), (10, 20, 30, 40));
    expect(parseBounds('bad'), (0, 0, 0, 0));
  });
}
