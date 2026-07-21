# V1.0.5
- 优化了流式UI断触、用户中断不渲染（但是仍然保存到上下文，只是不美观）
- 优化了超长对话、每轮对话快结束大量UI生成的渲染卡顿问题
- 优化了对话时流式UI效果
- 模型卡片添加上下文窗口大小配置（不配置则默认128K）
- 增强了Authropic协议的支持
- 添加了Linux和MacOS的webview渲染H5代码，但是未做验证
- 除此之外还优化了其他卡顿问题和UI


# V1.0.4

## zh

- 优化了长对话思考时途中可能产生卡顿的问题.
- 优化了"软失效过滤"，避免过时记忆和新记忆同权重混在检索结果里.
- 编排多Agent对大量文档进行并行理解的命令.
- 可控的agentloop模式，从思考，编写，测试，验证的循环流水线.
- 技能现在可以批量导入.
- 优化了代码高亮文本.
- 使用[archify](https://github.com/tt-a1i/archify)对对话进行流程图总结输出.
- 更为可靠的版本工作流.
- 知识库功能.
- 优化了MCP服务器的载入和启动配置.
- 优化了Agent自主生成文件默认在工作目录下.


## en
- Optimized the issue of potential stuttering during long conversations.
- Optimized the "soft failure filter" to prevent outdated and new memories from being mixed with the same weight in search results.
- Orchestrated commands for multi-agent parallel understanding of large amounts of documents.
- A controllable agentloop model, a pipeline of thought, writing, testing, and verification.
- Skills can now be imported in batches.
- Optimized code highlighting.
- Use [archify](https://github.com/tt-a1i/archify) to summarize and output flowcharts of conversations.
- More reliable version workflows.
- Knowledge base functionality.
- Optimized MCP server loading and startup configuration.
- Optimized the default location of Agent-generated files in the working directory.

# V1.0.3

## zh

- 提供了在线访问Agent的功能
- 优化了上下文压缩
- 在工作目录下创建、使用临时技能进行临时性自我进化
- 命令功能，比如说创建全局技能并且自己导入


## en

- Provides online access to the Agent.
- Optimized context compression.
- Create and use temporary skills for temporary self-evolution within the working directory.
- Command functionality, such as creating global skills and importing them automatically.


# V1.0.2

## zh

- 优化了部分实现、增强了工具链
- 在模型输出html5的时候可以使用webview2预览了

## en
- Optimized some implementation details and enhanced the toolchain
- WebView2 can now be used for previewing when outputting HTML5 models

# V1.0.1

## zh
- 添加了字体设置
- 内置了截图工具
- 检测到大量模型时可以输入快速匹配
- 添加了宠物功能，宠物作为全局观察者，可以通过右键内容唤醒进行交互


## en
- Added font settings
- Built-in screenshot tool
- Allows for quick matching when a large number of models are detected
- A pet feature has been added. Pets act as global observers and can be activated and interacted with by right-clicking on content.


# V1.0.0

## zh
发布！支持MCP、Skill、Search、Memory、多Agents协同办公等等等

## en
Released! Supports MCP, Skill, Search, Memory, multi-agent collaborative work, and more.

