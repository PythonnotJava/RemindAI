import 'tool_registry.dart';
import '../../features/tools/image_gen/image_gen_tool.dart';
import '../../features/tools/formula_ocr/formula_ocr_tool.dart';
import '../../features/tools/paddle_ocr/paddle_ocr_tool.dart';
import '../../features/tools/vpl/vpl_tool.dart';
import '../../features/tools/flowchart/flowchart_tool.dart';
import '../../features/tools/siyu/siyu_tool.dart';

/// 创建并初始化全局工具注册表
Future<ToolRegistry> createToolRegistry() async {
  final registry = ToolRegistry();

  // 注册所有内置工具
  registry.register(ImageGenTool());
  registry.register(FormulaOcrTool());
  registry.register(PaddleOcrTool());
  registry.register(VplTool());
  registry.register(FlowchartTool());
  registry.register(SiyuTool());

  // 初始化（加载持久化配置）
  await registry.initAll();

  return registry;
}
