/// 在线服务 Web 前端资源 — 高质量单页聊天应用
/// 特性: Markdown渲染、代码高亮、思考动画、历史持久化、文件上传、模型管理、产物面板
class WebAssets {
  WebAssets._();

  /// 完整单页 HTML
  static String get indexHtml {
    return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>AI 在线服务</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.1/marked.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<style>${WebAssets.css}</style>
</head>
<body>
<div id="app">
  <aside id="sidebar">
    <div class="sidebar-header">
      <button id="new-chat-btn" class="sidebar-action-btn">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 5v14M5 12h14"/></svg>
        <span>新对话</span>
      </button>
    </div>
    <div id="history-list" class="history-list"></div>
    <div class="sidebar-footer">
      <button id="clear-all-btn" class="sidebar-footer-btn">清空全部</button>
    </div>
  </aside>

  <main id="main">
    <header id="header">
      <button id="sidebar-toggle" class="hdr-btn" title="侧栏">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 12h18M3 6h18M3 18h18"/></svg>
      </button>
      <div class="hdr-center">
        <select id="model-select" title="选择模型"></select>
        <button id="add-model-btn" class="hdr-btn" title="添加自定义模型">+</button>
      </div>
      <div class="hdr-right">
        <div id="status" class="status-dot"></div>
        <button id="terminal-toggle" class="hdr-btn" title="调试终端">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>
        </button>
        <button id="search-toggle" class="hdr-btn admin-only" title="联网搜索" style="display:none">🔍</button>
        <button id="mcp-toggle" class="hdr-btn admin-only" title="MCP 服务" style="display:none">⚡</button>
        <button id="skill-toggle" class="hdr-btn admin-only" title="Skills" style="display:none">🧩</button>
        <button id="artifacts-toggle" class="hdr-btn" title="文件产物">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
          <span id="artifact-count" class="badge" style="display:none">0</span>
        </button>
      </div>
    </header>

    <div id="chat-area">
      <div id="welcome-screen">
        <div class="welcome-logo">&#9733;</div>
        <h2>AI 在线服务</h2>
        <p>输入消息开始对话，支持 Markdown 渲染</p>
      </div>
      <div id="messages"></div>
      <div id="thinking" class="thinking" style="display:none">
        <div class="thinking-bubble">
          <span class="dot"></span><span class="dot"></span><span class="dot"></span>
        </div>
      </div>
    </div>

    <footer id="footer">
      <div id="file-chips" class="file-chips" style="display:none"></div>
      <div class="input-row">
        <button id="attach-btn" class="input-btn" title="上传文件">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21.44 11.05l-9.19 9.19a6 6 0 01-8.49-8.49l9.19-9.19a4 4 0 015.66 5.66l-9.2 9.19a2 2 0 01-2.83-2.83l8.49-8.48"/></svg>
        </button>
        <textarea id="input" placeholder="输入消息…" rows="1"></textarea>
        <button id="send-btn" class="input-btn primary" title="发送">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 2L11 13M22 2l-7 20-4-9-9-4z"/></svg>
        </button>
        <button id="stop-btn" class="input-btn danger" title="停止" style="display:none">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>
        </button>
      </div>
      <input type="file" id="file-input" multiple style="display:none">
    </footer>

    <!-- 调试终端 -->
    <div id="terminal-panel" class="terminal-panel collapsed">
      <div class="terminal-header">
        <span>🖥 调试终端</span>
        <div class="terminal-actions">
          <button id="terminal-clear" class="panel-btn">清空</button>
          <button id="terminal-close" class="panel-btn">✕</button>
        </div>
      </div>
      <div id="terminal-output" class="terminal-output"></div>
    </div>
  </main>

  <!-- 产物面板 -->
  <aside id="artifacts-panel" class="artifacts-panel collapsed">
    <div class="panel-header">
      <span>文件产物</span>
      <button id="download-all-btn" class="panel-btn" title="打包下载" style="display:none">⬇ ZIP</button>
      <button id="close-panel-btn" class="panel-btn">✕</button>
    </div>
    <div id="artifacts-list" class="artifacts-list"></div>
    <div id="artifact-preview" class="artifact-preview" style="display:none">
      <div class="preview-header">
        <span id="preview-filename"></span>
        <button id="preview-download" class="panel-btn">下载</button>
        <button id="preview-close" class="panel-btn">✕</button>
      </div>
      <pre><code id="preview-code"></code></pre>
    </div>
  </aside>
</div>

<!-- 管理员: MCP/Skill/Search 弹出面板 -->
<dialog id="admin-dialog">
  <div class="dialog-content">
    <div id="admin-panel-mcp" style="display:none">
      <h3>MCP 服务器</h3>
      <div id="mcp-list" class="admin-list"></div>
    </div>
    <div id="admin-panel-skill" style="display:none">
      <h3>Skills</h3>
      <div id="skill-list" class="admin-list"></div>
    </div>
    <div id="admin-panel-search" style="display:none">
      <h3>联网搜索</h3>
      <div class="search-options">
        <label class="radio-option"><input type="radio" name="search-p" value="none" checked><span>关闭</span></label>
        <label class="radio-option"><input type="radio" name="search-p" value="tavily"><span>Tavily</span></label>
        <label class="radio-option"><input type="radio" name="search-p" value="brave"><span>Brave</span></label>
        <label class="radio-option"><input type="radio" name="search-p" value="baidu"><span>百度千帆</span></label>
      </div>
    </div>
    <div class="dialog-actions"><button id="admin-close" class="btn outline">关闭</button></div>
  </div>
</dialog>

<!-- 自定义模型对话框 -->
<dialog id="model-dialog">
  <div class="dialog-content">
    <h3>添加自定义模型</h3>
    <label>协议类型
      <select id="md-provider">
        <option value="openai">OpenAI 兼容</option>
        <option value="anthropic">Anthropic</option>
        <option value="gemini">Google Gemini</option>
      </select>
    </label>
    <label>Base URL
      <input id="md-url" type="url" placeholder="https://api.openai.com/v1">
    </label>
    <label>API Key
      <input id="md-key" type="password" placeholder="sk-...">
    </label>
    <label>模型名称 (显示用)
      <input id="md-name" type="text" placeholder="My GPT-4o">
    </label>
    <label>模型 ID
      <input id="md-model" type="text" placeholder="gpt-4o">
      <button id="md-fetch" class="small-btn">获取模型列表</button>
    </label>
    <div id="md-model-list" class="model-list" style="display:none"></div>
    <div id="md-status" class="dialog-status"></div>
    <div class="dialog-actions">
      <button id="md-test" class="btn outline">测试连接</button>
      <button id="md-cancel" class="btn outline">取消</button>
      <button id="md-confirm" class="btn primary">添加</button>
    </div>
  </div>
</dialog>
<script>${WebAssets.js}</script>
</body>
</html>''';
  }

  /// CSS (合并三段)
  static String get css => '$_css1$_css2$_css3';

  /// JS
  static const String js = _js;

  // ─── CSS Part 1: Reset + Layout + Sidebar + Header ───

  static const String _css1 = r'''
*{margin:0;padding:0;box-sizing:border-box}
:root{
  --bg:#0b0d14;--bg2:#13151f;--bg3:#1c1f2e;--bg4:#262a3d;
  --accent:#7c6aff;--accent2:#9d8fff;--accent-bg:rgba(124,106,255,.12);
  --text:#e4e4ed;--text2:#a3a3bc;--text3:#6b6b82;
  --border:#252838;--radius:10px;--radius-sm:6px;
  --green:#4ade80;--red:#f87171;--yellow:#fbbf24;
  --shadow:0 8px 32px rgba(0,0,0,.4);
  --tr:.2s cubic-bezier(.4,0,.2,1);
}
html,body{height:100%;overflow:hidden}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif;background:var(--bg);color:var(--text);font-size:14px;-webkit-tap-highlight-color:transparent}
#app{display:flex;height:100vh;overflow:hidden}

/* Sidebar */
#sidebar{width:240px;background:var(--bg2);border-right:1px solid var(--border);display:flex;flex-direction:column;transition:transform var(--tr),opacity var(--tr);flex-shrink:0;z-index:50}
#sidebar.hide{transform:translateX(-240px);opacity:0;position:absolute;height:100%}
.sidebar-header{padding:12px}
.sidebar-action-btn{display:flex;align-items:center;gap:6px;width:100%;padding:9px 12px;background:var(--accent-bg);border:1px dashed var(--accent);border-radius:var(--radius-sm);color:var(--accent2);cursor:pointer;font-size:13px;transition:all var(--tr)}
.sidebar-action-btn:hover{background:var(--accent);color:#fff;border-style:solid}
.history-list{flex:1;overflow-y:auto;padding:4px 8px}
.history-item{padding:8px 10px;border-radius:var(--radius-sm);cursor:pointer;font-size:12px;color:var(--text2);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;transition:background var(--tr);margin-bottom:1px}
.history-item:hover{background:var(--bg3)}
.history-item.active{background:var(--bg4);color:var(--text)}
.sidebar-footer{padding:8px 12px;border-top:1px solid var(--border)}
.sidebar-footer-btn{width:100%;padding:6px;background:none;border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text3);font-size:11px;cursor:pointer;transition:all var(--tr)}
.sidebar-footer-btn:hover{border-color:var(--red);color:var(--red)}

/* Header */
#header{display:flex;align-items:center;padding:8px 12px;gap:8px;border-bottom:1px solid var(--border);background:var(--bg2);flex-shrink:0}
.hdr-btn{background:none;border:none;color:var(--text2);cursor:pointer;padding:6px;border-radius:var(--radius-sm);transition:background var(--tr);font-size:16px;display:flex;align-items:center;position:relative}
.hdr-btn:hover{background:var(--bg3)}
.hdr-center{flex:1;display:flex;align-items:center;gap:6px}
#model-select{background:var(--bg3);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text);padding:5px 8px;font-size:12px;max-width:200px;cursor:pointer;outline:none}
#add-model-btn{font-size:18px;font-weight:700;color:var(--accent2)}
.hdr-right{display:flex;align-items:center;gap:6px}
.status-dot{width:8px;height:8px;border-radius:50%;background:var(--text3);transition:background var(--tr)}
.status-dot.ok{background:var(--green)}
.status-dot.err{background:var(--red)}
.badge{position:absolute;top:0;right:0;background:var(--accent);color:#fff;font-size:9px;padding:1px 4px;border-radius:8px;min-width:14px;text-align:center}
  ''';

  // ─── CSS Part 2: Chat + Messages + Input ───

  static const String _css2 = r'''
/* Main */
#main{flex:1;display:flex;flex-direction:column;min-width:0;position:relative}

/* Chat area */
#chat-area{flex:1;overflow-y:auto;padding:16px;scroll-behavior:smooth}
#welcome-screen{display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;gap:8px;color:var(--text3)}
.welcome-logo{font-size:40px;opacity:.6}
#welcome-screen h2{font-size:18px;color:var(--text2);font-weight:500}
#welcome-screen p{font-size:13px}
#messages{max-width:760px;margin:0 auto;width:100%}

/* Message rows */
.msg-row{display:flex;gap:10px;margin-bottom:16px;animation:fadeUp .25s ease}
@keyframes fadeUp{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:none}}
.msg-row.user{flex-direction:row-reverse}
.msg-ava{width:28px;height:28px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:600;flex-shrink:0}
.msg-row.assistant .msg-ava{background:var(--accent-bg);color:var(--accent2)}
.msg-row.user .msg-ava{background:var(--bg4);color:var(--text2)}
.msg-body{max-width:72%;min-width:60px}
.msg-bubble{padding:10px 14px;border-radius:var(--radius);font-size:13px;line-height:1.7;word-break:break-word;user-select:text;-webkit-user-select:text;position:relative}
.msg-row.user .msg-bubble{background:var(--accent);color:#fff;border-bottom-right-radius:3px}
.msg-row.assistant .msg-bubble{background:var(--bg3);border:1px solid var(--border);border-bottom-left-radius:3px}
.msg-copy{position:absolute;top:4px;right:4px;background:var(--bg4);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text3);cursor:pointer;padding:3px 6px;font-size:11px;opacity:0;transition:opacity var(--tr);z-index:2;line-height:1}
.msg-row:hover .msg-copy{opacity:1}
.msg-copy:hover{color:var(--accent2);border-color:var(--accent)}
.msg-copy.copied{color:var(--green);border-color:var(--green)}
.msg-bubble p{margin:6px 0}.msg-bubble p:first-child{margin-top:0}.msg-bubble p:last-child{margin-bottom:0}
.msg-bubble code{background:rgba(0,0,0,.35);padding:1px 5px;border-radius:3px;font-size:12px;font-family:"JetBrains Mono","Fira Code",monospace}
.msg-bubble pre{background:#0d1117;border-radius:var(--radius-sm);padding:10px 14px;overflow-x:auto;margin:8px 0;border:1px solid var(--border);position:relative}
.msg-bubble pre code{background:none;padding:0;font-size:12px}
.code-copy{position:absolute;top:6px;right:6px;background:var(--bg4);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text3);cursor:pointer;padding:2px 8px;font-size:10px;opacity:0;transition:opacity var(--tr)}
.msg-bubble pre:hover .code-copy{opacity:1}
.code-copy:hover{color:var(--accent2);border-color:var(--accent)}
.code-copy.copied{color:var(--green);border-color:var(--green)}
.msg-bubble ul,.msg-bubble ol{padding-left:18px;margin:6px 0}
.msg-bubble blockquote{border-left:3px solid var(--accent);padding-left:10px;color:var(--text2);margin:6px 0}
.msg-bubble table{border-collapse:collapse;margin:6px 0;font-size:12px}
.msg-bubble th,.msg-bubble td{border:1px solid var(--border);padding:4px 8px}
.msg-bubble th{background:var(--bg4)}
.msg-stopped-tag{font-size:11px;color:var(--text3);margin-top:6px;padding:3px 8px;background:var(--bg4);border-radius:var(--radius-sm);display:inline-block;border:1px solid var(--border)}
.msg-actions{display:flex;gap:6px;margin-top:4px;opacity:0;transition:opacity var(--tr)}
.msg-row:hover .msg-actions{opacity:1}
.msg-action-btn{background:none;border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text3);cursor:pointer;padding:2px 8px;font-size:11px;transition:all var(--tr)}
.msg-action-btn:hover{border-color:var(--accent);color:var(--accent2)}

/* Thinking */
.thinking{max-width:760px;margin:0 auto;padding:8px 0;display:flex;align-items:center;gap:10px}
.thinking-bubble{display:flex;align-items:center;gap:4px;padding:10px 16px;background:var(--bg3);border:1px solid var(--border);border-radius:var(--radius)}
.dot{width:6px;height:6px;border-radius:50%;background:var(--accent);animation:pulse 1.2s infinite ease-in-out}
.dot:nth-child(2){animation-delay:.2s}.dot:nth-child(3){animation-delay:.4s}
@keyframes pulse{0%,80%,100%{transform:scale(.5);opacity:.4}40%{transform:scale(1);opacity:1}}

/* Footer / Input */
#footer{padding:10px 12px;border-top:1px solid var(--border);background:var(--bg2);flex-shrink:0}
.file-chips{display:flex;flex-wrap:wrap;gap:6px;padding-bottom:8px;max-width:760px;margin:0 auto}
.file-chip{display:flex;align-items:center;gap:4px;padding:3px 8px;background:var(--bg3);border:1px solid var(--border);border-radius:12px;font-size:11px;color:var(--text2)}
.file-chip .x{cursor:pointer;color:var(--text3);margin-left:2px}.file-chip .x:hover{color:var(--red)}
.input-row{display:flex;align-items:flex-end;gap:6px;max-width:760px;margin:0 auto;background:var(--bg3);border:1px solid var(--border);border-radius:var(--radius);padding:6px 10px;transition:border-color var(--tr)}
.input-row:focus-within{border-color:var(--accent)}
#input{flex:1;background:none;border:none;color:var(--text);font-size:14px;resize:none;outline:none;max-height:140px;line-height:1.5;font-family:inherit;padding:4px 0}
.input-btn{width:32px;height:32px;border:none;border-radius:var(--radius-sm);cursor:pointer;display:flex;align-items:center;justify-content:center;background:none;color:var(--text3);transition:all var(--tr);flex-shrink:0}
.input-btn:hover{background:var(--bg4);color:var(--text)}
.input-btn.primary{background:var(--accent);color:#fff}
.input-btn.primary:hover{opacity:.85}
.input-btn.danger{background:var(--red);color:#fff}
  ''';

  // ─── CSS Part 3: Artifacts panel + Dialog + Mobile ───

  static const String _css3 = r'''
/* Artifacts panel */
.artifacts-panel{width:280px;background:var(--bg2);border-left:1px solid var(--border);display:flex;flex-direction:column;transition:transform var(--tr),opacity var(--tr);flex-shrink:0;overflow:hidden;position:relative}
.artifacts-panel.collapsed{width:0;border:none;opacity:0;pointer-events:none}
.panel-header{display:flex;align-items:center;justify-content:space-between;padding:10px 12px;border-bottom:1px solid var(--border);font-size:13px;font-weight:500}
.panel-btn{background:none;border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text2);cursor:pointer;padding:3px 8px;font-size:11px;transition:all var(--tr)}
.panel-btn:hover{border-color:var(--accent);color:var(--accent2)}
.artifacts-list{flex:1;overflow-y:auto;padding:8px}
.artifact-item{display:flex;align-items:center;gap:8px;padding:8px 10px;border-radius:var(--radius-sm);cursor:pointer;transition:background var(--tr);margin-bottom:4px}
.artifact-item:hover{background:var(--bg3)}
.artifact-item .icon{font-size:16px}
.artifact-item .info{flex:1;min-width:0}
.artifact-item .name{font-size:12px;color:var(--text);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.artifact-item .meta{font-size:10px;color:var(--text3)}
.artifact-item .dl-btn{background:none;border:none;color:var(--text3);cursor:pointer;padding:4px;font-size:14px}
.artifact-item .dl-btn:hover{color:var(--accent2)}
.artifact-preview{position:absolute;inset:0;background:var(--bg2);display:flex;flex-direction:column;z-index:10;overflow:hidden}
.preview-header{display:flex;align-items:center;gap:8px;padding:10px 12px;border-bottom:1px solid var(--border);flex-shrink:0}
.preview-header span{flex:1;font-size:12px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.artifact-preview pre{flex:1;overflow:auto;margin:0;padding:12px;font-size:12px;background:var(--bg);border-radius:0;min-height:0}
.artifact-preview pre code{font-family:"JetBrains Mono","Fira Code",monospace;white-space:pre-wrap;word-break:break-all}

/* Inline artifact cards (Claude-style, below assistant messages) */
.msg-artifacts{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px;padding:0}
.msg-artifact-card{display:flex;align-items:center;gap:6px;padding:6px 10px;background:var(--bg4);border:1px solid var(--border);border-radius:var(--radius-sm);cursor:pointer;transition:all var(--tr);font-size:12px;max-width:220px}
.msg-artifact-card:hover{border-color:var(--accent);background:var(--accent-bg)}
.msg-artifact-card .af-icon{font-size:14px;flex-shrink:0}
.msg-artifact-card .af-name{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:var(--text)}
.msg-artifact-card .af-dl{background:none;border:none;color:var(--text3);cursor:pointer;padding:2px;font-size:13px;flex-shrink:0;transition:color var(--tr)}
.msg-artifact-card .af-dl:hover{color:var(--accent2)}
.msg-artifacts-zip{display:flex;align-items:center;gap:4px;padding:5px 10px;background:var(--accent-bg);border:1px solid var(--accent);border-radius:var(--radius-sm);color:var(--accent2);font-size:11px;cursor:pointer;transition:all var(--tr)}
.msg-artifacts-zip:hover{background:var(--accent);color:#fff}

/* Terminal panel */
.terminal-panel{border-top:1px solid var(--border);background:var(--bg);display:flex;flex-direction:column;transition:height var(--tr);overflow:hidden;flex-shrink:0}
.terminal-panel.collapsed{height:0;border:none}
.terminal-panel:not(.collapsed){height:180px}
.terminal-header{display:flex;align-items:center;justify-content:space-between;padding:6px 12px;background:var(--bg2);border-bottom:1px solid var(--border);font-size:12px;font-weight:500;flex-shrink:0}
.terminal-actions{display:flex;gap:4px}
.terminal-output{flex:1;overflow-y:auto;padding:8px 12px;font-family:"JetBrains Mono","Fira Code",monospace;font-size:11px;line-height:1.6;white-space:pre-wrap;word-break:break-all;color:var(--text2)}
.terminal-output .t-line{margin:0;padding:1px 0}
.terminal-output .t-time{color:var(--text3);margin-right:6px}
.terminal-output .t-info{color:var(--text2)}
.terminal-output .t-tool{color:var(--accent2)}
.terminal-output .t-result{color:var(--green)}
.terminal-output .t-error{color:var(--red)}
.terminal-output .t-warn{color:var(--yellow)}
.terminal-output .t-system{color:var(--text3);font-style:italic}

/* Admin panel */
.admin-list{max-height:240px;overflow-y:auto;display:flex;flex-direction:column;gap:4px;margin:8px 0}
.admin-item{display:flex;align-items:center;gap:8px;padding:8px 10px;background:var(--bg3);border:1px solid var(--border);border-radius:var(--radius-sm)}
.admin-item .ai-name{flex:1;font-size:12px;color:var(--text);min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.admin-item .ai-meta{font-size:10px;color:var(--text3)}
.admin-item .ai-toggle{width:36px;height:20px;border-radius:10px;background:var(--bg4);border:1px solid var(--border);cursor:pointer;position:relative;transition:all var(--tr);flex-shrink:0}
.admin-item .ai-toggle.on{background:var(--accent);border-color:var(--accent)}
.admin-item .ai-toggle::after{content:"";position:absolute;top:2px;left:2px;width:14px;height:14px;border-radius:50%;background:#fff;transition:transform var(--tr)}
.admin-item .ai-toggle.on::after{transform:translateX(16px)}
.search-options{display:flex;flex-direction:column;gap:8px;margin:8px 0}
.radio-option{display:flex;align-items:center;gap:8px;padding:8px 10px;background:var(--bg3);border:1px solid var(--border);border-radius:var(--radius-sm);cursor:pointer;font-size:13px;transition:all var(--tr)}
.radio-option:has(input:checked){border-color:var(--accent);background:var(--accent-bg)}
.radio-option input{accent-color:var(--accent)}

/* Dialog */
dialog{border:none;border-radius:var(--radius);background:var(--bg2);color:var(--text);padding:0;box-shadow:var(--shadow);max-width:400px;width:90vw}
dialog::backdrop{background:rgba(0,0,0,.6)}
.dialog-content{padding:20px;display:flex;flex-direction:column;gap:12px}
.dialog-content h3{font-size:16px;font-weight:600;margin-bottom:4px}
.dialog-content label{display:flex;flex-direction:column;gap:4px;font-size:12px;color:var(--text2)}
.dialog-content input,.dialog-content select{background:var(--bg3);border:1px solid var(--border);border-radius:var(--radius-sm);padding:8px 10px;color:var(--text);font-size:13px;outline:none;transition:border-color var(--tr)}
.dialog-content input:focus,.dialog-content select:focus{border-color:var(--accent)}
.small-btn{background:var(--accent-bg);border:1px solid var(--accent);border-radius:var(--radius-sm);color:var(--accent2);padding:4px 10px;font-size:11px;cursor:pointer;margin-top:4px;align-self:flex-start;transition:all var(--tr)}
.small-btn:hover{background:var(--accent);color:#fff}
.model-list{max-height:120px;overflow-y:auto;border:1px solid var(--border);border-radius:var(--radius-sm);padding:4px}
.model-list-item{padding:4px 8px;border-radius:3px;cursor:pointer;font-size:12px;color:var(--text2)}
.model-list-item:hover{background:var(--bg4);color:var(--text)}
.dialog-status{font-size:12px;min-height:18px}
.dialog-actions{display:flex;gap:8px;justify-content:flex-end;margin-top:4px}
.btn{padding:7px 16px;border-radius:var(--radius-sm);font-size:13px;cursor:pointer;border:none;transition:all var(--tr)}
.btn.primary{background:var(--accent);color:#fff}.btn.primary:hover{opacity:.85}
.btn.outline{background:none;border:1px solid var(--border);color:var(--text2)}.btn.outline:hover{border-color:var(--text2);color:var(--text)}

/* Scrollbar */
::-webkit-scrollbar{width:5px}::-webkit-scrollbar-track{background:transparent}::-webkit-scrollbar-thumb{background:var(--border);border-radius:3px}

/* Mobile */
@media(max-width:640px){
  #sidebar{position:fixed;left:0;top:0;height:100%;z-index:100;box-shadow:var(--shadow)}
  #sidebar.hide{transform:translateX(-240px)}
  .artifacts-panel{position:fixed;right:0;top:0;height:100%;z-index:100;width:85vw;max-width:300px;box-shadow:var(--shadow)}
  .artifacts-panel.collapsed{transform:translateX(100%)}
  .msg-body{max-width:85%}
  .msg-artifact-card{max-width:180px}
  #model-select{max-width:120px}
  .input-row{padding:5px 8px}
  #input{font-size:16px}
  .dialog-content{padding:16px}
}
@media(max-width:380px){
  .hdr-center{gap:4px}
  #model-select{max-width:90px;font-size:11px}
  .msg-body{max-width:90%}
}
  ''';

  // ─── JavaScript ─────────────────────────────────────

  static const String _js = r'''
(function(){
"use strict";

// ── i18n ──
var _zh={connected:"已连接",disconnected:"已断开 (重连中...)",newChat:"新对话",clearAll:"清空全部",clearConfirm:"清空所有记录？",noModel:"无可用模型",send:"发送",stop:"停止",copy:"复制",copied:"✓",copyCode:"复制代码",codeCopied:"✓ 已复制",stopped:"⏹ 已停止生成",welcome:"AI 在线服务",welcomeHint:"输入消息开始对话，支持 Markdown 渲染",files:"文件产物",zipAll:"⬇ ZIP",close:"✕",clear:"清空",debug:"🖥 调试终端",addModel:"添加自定义模型",protocol:"协议类型",baseUrl:"Base URL",apiKey:"API Key",modelName:"模型名称 (显示用)",modelId:"模型 ID",fetchModels:"获取模型列表",testing:"测试中...",testOk:"✓ 连接成功，发现 {n} 个模型",testFail:"✗ {e}",fillAll:"请填写完整",cancel:"取消",add:"添加",testConn:"测试连接",download:"下载",preview:"预览",search:"联网搜索",searchOff:"关闭",mcpServers:"MCP 服务器",skills:"Skills",closeDlg:"关闭"};
var _en={connected:"Connected",disconnected:"Disconnected (reconnecting...)",newChat:"New Chat",clearAll:"Clear All",clearConfirm:"Clear all history?",noModel:"No model available",send:"Send",stop:"Stop",copy:"Copy",copied:"✓",copyCode:"Copy code",codeCopied:"✓ Copied",stopped:"⏹ Generation stopped",welcome:"AI Online Service",welcomeHint:"Type a message to start, Markdown supported",files:"Artifacts",zipAll:"⬇ ZIP",close:"✕",clear:"Clear",debug:"🖥 Debug Terminal",addModel:"Add Custom Model",protocol:"Protocol",baseUrl:"Base URL",apiKey:"API Key",modelName:"Display Name",modelId:"Model ID",fetchModels:"Fetch Models",testing:"Testing...",testOk:"✓ Connected, found {n} models",testFail:"✗ {e}",fillAll:"Please fill in all fields",cancel:"Cancel",add:"Add",testConn:"Test Connection",download:"Download",preview:"Preview",search:"Web Search",searchOff:"Off",mcpServers:"MCP Servers",skills:"Skills",closeDlg:"Close"};
var T=(navigator.language||"").startsWith("zh")?_zh:_en;

// ── State ──
var ws=null, streaming=false, streamingEl=null, streamingBody=null, currentChatId=null, pendingFiles=[], artifacts=[], prevArtifactCount=0, _dlFilename=null;

// ── DOM ──
var $=function(s){return document.getElementById(s)};
var messagesEl=$("messages"),inputEl=$("input"),sendBtn=$("send-btn"),stopBtn=$("stop-btn");
var statusEl=$("status"),thinkingEl=$("thinking"),welcomeEl=$("welcome-screen");
var historyList=$("history-list"),fileInput=$("file-input"),fileChips=$("file-chips");
var modelSelect=$("model-select"),sidebar=$("sidebar"),sidebarToggle=$("sidebar-toggle");
var newChatBtn=$("new-chat-btn"),clearAllBtn=$("clear-all-btn");
var artifactsToggle=$("artifacts-toggle"),artifactsPanel=$("artifacts-panel");
var artifactsList=$("artifacts-list"),artifactCount=$("artifact-count");
var closePanelBtn=$("close-panel-btn"),downloadAllBtn=$("download-all-btn");
var previewEl=$("artifact-preview"),previewCode=$("preview-code"),previewFilename=$("preview-filename");
var previewDownload=$("preview-download"),previewClose=$("preview-close");
var addModelBtn=$("add-model-btn"),modelDialog=$("model-dialog");
var mdProvider=$("md-provider"),mdUrl=$("md-url"),mdKey=$("md-key");
var mdName=$("md-name"),mdModel=$("md-model"),mdFetch=$("md-fetch");
var mdModelList=$("md-model-list"),mdStatus=$("md-status");
var mdTest=$("md-test"),mdCancel=$("md-cancel"),mdConfirm=$("md-confirm");
var termPanel=$("terminal-panel"),termOutput=$("terminal-output"),termToggle=$("terminal-toggle"),termClear=$("terminal-clear"),termClose=$("terminal-close");

// ── Markdown ──
if(window.marked){marked.setOptions({highlight:function(c,l){if(window.hljs&&l&&hljs.getLanguage(l))return hljs.highlight(c,{language:l}).value;return c},breaks:true})}

// ── Terminal ──
function tlog(type,text){
  var line=document.createElement("div");line.className="t-line";
  var ts=new Date().toLocaleTimeString("zh-CN",{hour12:false,hour:"2-digit",minute:"2-digit",second:"2-digit"});
  line.innerHTML="<span class='t-time'>["+ts+"]</span><span class='t-"+type+"'>"+escHtml2(text)+"</span>";
  termOutput.appendChild(line);
  termOutput.scrollTop=termOutput.scrollHeight;
}
function escHtml2(s){return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")}

// ── Storage ──
function loadChats(){try{return JSON.parse(localStorage.getItem("ols_chats")||"{}")}catch(e){return {}}}
function saveChats(c){localStorage.setItem("ols_chats",JSON.stringify(c))}
function loadCurrent(){return localStorage.getItem("ols_cur")}
function saveCurrent(id){localStorage.setItem("ols_cur",id)}
function loadUserModels(){try{return JSON.parse(localStorage.getItem("ols_models")||"[]")}catch(e){return []}}
function saveUserModels(m){localStorage.setItem("ols_models",JSON.stringify(m))}
function addUserModel(cfg){var ms=loadUserModels();ms=ms.filter(function(x){return x.id!==cfg.id});ms.push(cfg);saveUserModels(ms)}
function removeUserModel(id){var ms=loadUserModels();ms=ms.filter(function(x){return x.id!==id});saveUserModels(ms)}

// ── Chat management ──
function newChat(){
  var id=Date.now().toString(36)+Math.random().toString(36).slice(2,5);
  var chats=loadChats();chats[id]={title:"新对话",messages:[],ts:Date.now()};
  saveChats(chats);switchChat(id);
  if(ws&&ws.readyState===1)ws.send(JSON.stringify({type:"clear"}));
}
function switchChat(id){currentChatId=id;saveCurrent(id);renderHistory();renderMessages();artifacts=[];renderArtifacts();if(ws&&ws.readyState===1)syncHistory()}
function renderHistory(){
  var chats=loadChats();
  var keys=Object.keys(chats).sort(function(a,b){return(chats[b].ts||0)-(chats[a].ts||0)});
  historyList.innerHTML="";
  keys.forEach(function(id){
    var d=document.createElement("div");d.className="history-item"+(id===currentChatId?" active":"");
    d.textContent=chats[id].title||"新对话";d.onclick=function(){switchChat(id)};
    historyList.appendChild(d);
  });
}
function renderMessages(){
  var chats=loadChats(),chat=chats[currentChatId];
  messagesEl.innerHTML="";
  if(!chat||chat.messages.length===0){welcomeEl.style.display="flex";return}
  welcomeEl.style.display="none";
  chat.messages.forEach(function(m){appendBubble(m.role,m.content,m.artifacts||null)});
  forceScrollBottom();
}
function saveMsg(role,content,arts){
  var chats=loadChats();if(!chats[currentChatId])return;
  var entry={role:role,content:content};
  if(arts&&arts.length)entry.artifacts=arts;
  chats[currentChatId].messages.push(entry);
  if(role==="user"&&chats[currentChatId].messages.length===1){
    chats[currentChatId].title=content.slice(0,28)+(content.length>28?"…":"");renderHistory();
  }
  saveChats(chats);
}

// ── DOM helpers ──
function appendBubble(role,content,inlineArtifacts){
  welcomeEl.style.display="none";
  var row=document.createElement("div");row.className="msg-row "+role;
  var ava=document.createElement("div");ava.className="msg-ava";ava.textContent=role==="user"?"我":"AI";
  var body=document.createElement("div");body.className="msg-body";
  var bubble=document.createElement("div");bubble.className="msg-bubble";
  bubble._raw=content||"";
  if(role==="assistant"&&window.marked){bubble.innerHTML=marked.parse(content||"")}else{bubble.textContent=content}
  var copyBtn=document.createElement("button");copyBtn.className="msg-copy";copyBtn.textContent=T.copy;
  copyBtn.onclick=function(){
    navigator.clipboard.writeText(bubble._raw).then(function(){copyBtn.textContent=T.copied;copyBtn.classList.add("copied");setTimeout(function(){copyBtn.textContent=T.copy;copyBtn.classList.remove("copied")},1500)});
  };
  bubble.appendChild(copyBtn);
  if(role==="assistant")addCodeCopyBtns(bubble);
  body.appendChild(bubble);
  if(role==="assistant"){
    var actions=document.createElement("div");actions.className="msg-actions";
    var copyAll=document.createElement("button");copyAll.className="msg-action-btn";copyAll.textContent="📋 "+T.copy;
    copyAll.onclick=function(){navigator.clipboard.writeText(bubble._raw).then(function(){copyAll.textContent="✓ "+T.copied;setTimeout(function(){copyAll.textContent="📋 "+T.copy},1500)})};
    actions.appendChild(copyAll);
    body.appendChild(actions);
  }
  if(inlineArtifacts&&inlineArtifacts.length){body.appendChild(buildInlineArtifacts(inlineArtifacts))}
  row.appendChild(ava);row.appendChild(body);
  messagesEl.appendChild(row);return{bubble:bubble,body:body};
}
function addCodeCopyBtns(el){
  el.querySelectorAll("pre").forEach(function(pre){
    if(pre.querySelector(".code-copy"))return;
    var btn=document.createElement("button");btn.className="code-copy";btn.textContent=T.copyCode;
    btn.onclick=function(e){e.stopPropagation();var code=pre.querySelector("code");
      navigator.clipboard.writeText(code?code.textContent:pre.textContent).then(function(){btn.textContent=T.codeCopied;btn.classList.add("copied");setTimeout(function(){btn.textContent=T.copyCode;btn.classList.remove("copied")},1500)})};
    pre.appendChild(btn);
  });
}
function scrollBottom(){var a=$("chat-area");var atBottom=a.scrollHeight-a.scrollTop-a.clientHeight<80;if(atBottom)a.scrollTop=a.scrollHeight}
function forceScrollBottom(){var a=$("chat-area");a.scrollTop=a.scrollHeight}

// ── WebSocket ──
function connect(){
  var proto=location.protocol==="https:"?"wss:":"ws:";
  ws=new WebSocket(proto+"//"+location.host+"/ws");
  ws.onopen=function(){statusEl.className="status-dot ok";reregisterModels();syncHistory();ws.send(JSON.stringify({type:"list_models"}))};
  ws.onclose=function(){statusEl.className="status-dot err";tlog("warn","连接断开, 3秒后重连...");setTimeout(connect,3000)};
  ws.onerror=function(){statusEl.className="status-dot err"};
  ws.onmessage=function(e){handleMsg(JSON.parse(e.data))};
}
function reregisterModels(){
  var ms=loadUserModels();
  ms.forEach(function(m){ws.send(JSON.stringify({type:"add_model",model:m}))});
}
function syncHistory(){
  if(!currentChatId)return;
  var chats=loadChats(),chat=chats[currentChatId];
  if(!chat||!chat.messages||!chat.messages.length)return;
  var msgs=chat.messages.map(function(m){return{role:m.role,content:m.content}});
  ws.send(JSON.stringify({type:"sync_history",messages:msgs}));
}
function handleMsg(msg){
  switch(msg.type){
    case "welcome":
      window._sessionId=msg.sessionId;
      isAdmin=!!msg.isAdmin;
      if(isAdmin){document.querySelectorAll(".admin-only").forEach(function(el){el.style.display="flex"})}
      if(msg.searchProvider&&msg.searchProvider!=="none")initAdminSearch(msg.searchProvider);
      tlog("system","已连接 session="+msg.sessionId+(isAdmin?" [管理员]":""));
      break;
    case "models":renderModels(msg.data||[]);tlog("info","加载模型 x"+(msg.data||[]).length);break;
    case "token":
      thinkingEl.style.display="none";
      if(!streamingEl){var r=appendBubble("assistant","");streamingEl=r.bubble;streamingBody=r.body;streamingEl._raw="";prevArtifactCount=artifacts.length}
      streamingEl._raw+=msg.text;
      if(window.marked){streamingEl.innerHTML=marked.parse(streamingEl._raw)}else{streamingEl.textContent=streamingEl._raw}
      scrollBottom();break;
    case "done":
      thinkingEl.style.display="none";
      if(streamingEl){
        addCodeCopyBtns(streamingEl);
        var newArts=artifacts.slice(prevArtifactCount);
        saveMsg("assistant",streamingEl._raw||msg.content||"",newArts);
        if(newArts.length&&streamingBody){streamingBody.appendChild(buildInlineArtifacts(newArts))}
        streamingEl=null;streamingBody=null;
      }
      tlog("info","生成完成");
      setStreaming(false);scrollBottom();break;
    case "stopped":
      thinkingEl.style.display="none";
      if(streamingEl){
        addCodeCopyBtns(streamingEl);
        saveMsg("assistant",streamingEl._raw||"",null);
        if(streamingBody){var tag=document.createElement("div");tag.className="msg-stopped-tag";tag.textContent=T.stopped;streamingBody.appendChild(tag)}
        streamingEl=null;streamingBody=null;
      }
      tlog("warn","用户中断生成");
      setStreaming(false);break;
    case "error":
      thinkingEl.style.display="none";_dlFilename=null;appendBubble("assistant","⚠️ "+msg.message);setStreaming(false);
      tlog("error","错误: "+msg.message);break;
    case "artifacts_updated":
      artifacts=msg.artifacts||[];renderArtifacts();
      tlog("info","产物更新, 共 "+artifacts.length+" 个文件");break;
    case "artifact_content":
      if(_dlFilename){downloadBlob(msg.content,_dlFilename);_dlFilename=null}else{showPreview(msg)}
      break;
    case "test_result":
      handleTestResult(msg);tlog("info","模型测试: "+(msg.success?"成功":"失败"));break;
    case "model_added":tlog("info","模型已添加");break;
    case "model_removed":tlog("info","模型已移除");break;
    case "mcp_servers":renderMcpServers(msg.data||[]);tlog("info","MCP 服务器列表已更新");break;
    case "skills":renderSkills(msg.data||[]);tlog("info","Skills 列表已更新");break;
    case "search_updated":initAdminSearch(msg.provider||"none");tlog("info","搜索引擎切换: "+msg.provider);break;
    case "tool_call":tlog("tool","⚡ 调用工具: "+msg.name+" "+JSON.stringify(msg.args||{}));break;
    case "tool_result":tlog("result","✓ 工具返回 ["+msg.name+"]: "+(msg.truncated||""));break;
    case "debug_skills":
      var pl=msg.promptLength||0;
      tlog("tool","🧩 激活 Skills: ["+msg.skills.join(", ")+"] | 工具数: "+msg.toolCount+" | system prompt: "+pl+"字");
      if(pl===0)tlog("warn","⚠ Skill 的 SKILL.md 内容为空，未注入系统提示！");
      break;
    case "debug_skills_warn":tlog("error","⚠ "+msg.message);break;
  }
}

// ── Models ──
function renderModels(models){
  modelSelect.innerHTML="";
  if(!models.length){var o=document.createElement("option");o.textContent=T.noModel;modelSelect.appendChild(o);return}
  models.forEach(function(m){
    var o=document.createElement("option");o.value=m.id;
    o.textContent=(m.source==="user"?"[自] ":"")+( m.name||m.modelId);
    modelSelect.appendChild(o);
  });
}

// ── Send ──
function send(){
  var text=inputEl.value.trim();if(!text||!ws||ws.readyState!==1)return;
  appendBubble("user",text);saveMsg("user",text);
  var payload={type:"chat",content:text,modelId:modelSelect.value};
  if(pendingFiles.length>0){
    var ctx=pendingFiles.map(function(f){return"--- "+f.name+" ---\\n"+f.content}).join("\\n\\n");
    payload.content=ctx+"\\n\\n"+text;clearFiles();
  }
  tlog("info","发送请求 → model="+modelSelect.value);
  ws.send(JSON.stringify(payload));inputEl.value="";inputEl.style.height="auto";
  setStreaming(true);thinkingEl.style.display="flex";forceScrollBottom();
}
function stopGen(){if(ws&&ws.readyState===1){ws.send(JSON.stringify({type:"stop"}));stopBtn.disabled=true;stopBtn.style.opacity="0.5"}}
function setStreaming(v){streaming=v;sendBtn.style.display=v?"none":"flex";stopBtn.style.display=v?"flex":"none";stopBtn.disabled=false;stopBtn.style.opacity="1"}

// ── Files ──
function handleFiles(files){
  Array.from(files).forEach(function(f){
    if(f.size>2*1024*1024){alert(f.name+" 超过 2MB");return}
    var r=new FileReader();r.onload=function(e){pendingFiles.push({name:f.name,content:e.target.result});renderChips()};
    r.readAsText(f);
  });
}
function renderChips(){
  if(!pendingFiles.length){fileChips.style.display="none";return}
  fileChips.style.display="flex";fileChips.innerHTML="";
  pendingFiles.forEach(function(f,i){
    var d=document.createElement("div");d.className="file-chip";
    d.innerHTML="📄 "+f.name+" <span class='x' data-i='"+i+"'>×</span>";
    fileChips.appendChild(d);
  });
}
function clearFiles(){pendingFiles=[];fileChips.style.display="none";fileChips.innerHTML=""}

// ── Inline Artifacts (Claude-style) ──
function buildInlineArtifacts(arts){
  var wrap=document.createElement("div");wrap.className="msg-artifacts";
  arts.forEach(function(a){
    var card=document.createElement("div");card.className="msg-artifact-card";
    card.innerHTML="<span class='af-icon'>📄</span><span class='af-name'>"+escHtml(a.filename)+"</span><button class='af-dl'>⬇</button>";
    card.querySelector(".af-name").onclick=function(){ws.send(JSON.stringify({type:"get_artifact",artifactId:a.id}));artifactsPanel.classList.remove("collapsed")};
    card.querySelector(".af-dl").onclick=function(e){e.stopPropagation();_dlFilename=a.filename;ws.send(JSON.stringify({type:"get_artifact",artifactId:a.id}))};
    wrap.appendChild(card);
  });
  if(arts.length>1){
    var zip=document.createElement("button");zip.className="msg-artifacts-zip";
    zip.innerHTML="⬇ 打包 ZIP";zip.onclick=function(){if(window._sessionId)window.open("/download/"+window._sessionId,"_blank")};
    wrap.appendChild(zip);
  }
  return wrap;
}
function escHtml(s){var d=document.createElement("span");d.textContent=s;return d.innerHTML}

// ── Artifacts Panel ──
function renderArtifacts(){
  artifactCount.style.display=artifacts.length?"inline":"none";
  artifactCount.textContent=artifacts.length;
  downloadAllBtn.style.display=artifacts.length?"inline":"none";
  artifactsList.innerHTML="";
  artifacts.forEach(function(a){
    var d=document.createElement("div");d.className="artifact-item";
    d.innerHTML="<span class='icon'>📄</span><div class='info'><div class='name'>"+a.filename+"</div><div class='meta'>"+a.language+" · "+formatSize(a.size)+"</div></div><button class='dl-btn' data-id='"+a.id+"'>⬇</button>";
    d.querySelector(".info").onclick=function(){ws.send(JSON.stringify({type:"get_artifact",artifactId:a.id}))};
    d.querySelector(".dl-btn").onclick=function(e){e.stopPropagation();downloadSingle(a.id,a.filename)};
    artifactsList.appendChild(d);
  });
}
function showPreview(a){
  previewEl.style.display="flex";previewFilename.textContent=a.filename;
  if(window.hljs&&a.language){previewCode.innerHTML=hljs.highlight(a.content,{language:a.language}).value}
  else{previewCode.textContent=a.content}
  previewDownload.onclick=function(){downloadBlob(a.content,a.filename)};
}
function downloadSingle(id,name){ws.send(JSON.stringify({type:"get_artifact",artifactId:id}))}
function downloadBlob(content,name){
  var b=new Blob([content],{type:"text/plain"});var u=URL.createObjectURL(b);
  var a=document.createElement("a");a.href=u;a.download=name;a.click();URL.revokeObjectURL(u);
}
function formatSize(n){if(n<1024)return n+"B";return(n/1024).toFixed(1)+"KB"}

// ── Custom Model Dialog ──
addModelBtn.onclick=function(){modelDialog.showModal();mdStatus.textContent="";mdModelList.style.display="none"};
mdCancel.onclick=function(){modelDialog.close()};
mdTest.onclick=function(){
  mdStatus.textContent=T.testing;mdStatus.style.color="var(--yellow)";
  ws.send(JSON.stringify({type:"test_model",baseUrl:mdUrl.value.trim(),apiKey:mdKey.value.trim(),provider:mdProvider.value}));
};
mdFetch.onclick=function(){mdTest.click()};
function handleTestResult(msg){
  if(msg.success){
    mdStatus.textContent=T.testOk.replace("{n}",msg.models.length);mdStatus.style.color="var(--green)";
    if(msg.models.length){
      mdModelList.style.display="block";mdModelList.innerHTML="";
      msg.models.slice(0,30).forEach(function(m){
        var d=document.createElement("div");d.className="model-list-item";d.textContent=m;
        d.onclick=function(){mdModel.value=m;mdModelList.style.display="none"};
        mdModelList.appendChild(d);
      });
    }
  }else{
    mdStatus.textContent=T.testFail.replace("{e}",msg.error);mdStatus.style.color="var(--red)";
  }
}
mdConfirm.onclick=function(){
  var cfg={id:Date.now().toString(36)+Math.random().toString(36).slice(2,5),name:mdName.value.trim()||mdModel.value,baseUrl:mdUrl.value.trim(),apiKey:mdKey.value.trim(),modelId:mdModel.value.trim(),provider:mdProvider.value};
  if(!cfg.baseUrl||!cfg.apiKey||!cfg.modelId){mdStatus.textContent=T.fillAll;mdStatus.style.color="var(--red)";return}
  addUserModel(cfg);
  ws.send(JSON.stringify({type:"add_model",model:cfg}));
  modelDialog.close();mdUrl.value="";mdKey.value="";mdName.value="";mdModel.value="";
};

// ── Admin Panel (MCP / Skill / Search) ──
var isAdmin=false, adminDialog=document.getElementById("admin-dialog");
var mcpToggleBtn=document.getElementById("mcp-toggle"),skillToggleBtn=document.getElementById("skill-toggle"),searchToggleBtn=document.getElementById("search-toggle");
var mcpList=document.getElementById("mcp-list"),skillList=document.getElementById("skill-list");
var adminClose=document.getElementById("admin-close");

function showAdminPanel(panel){
  document.getElementById("admin-panel-mcp").style.display=panel==="mcp"?"block":"none";
  document.getElementById("admin-panel-skill").style.display=panel==="skill"?"block":"none";
  document.getElementById("admin-panel-search").style.display=panel==="search"?"block":"none";
  adminDialog.showModal();
  if(panel==="mcp")ws.send(JSON.stringify({type:"list_mcp_servers"}));
  if(panel==="skill")ws.send(JSON.stringify({type:"list_skills"}));
}
function renderMcpServers(data){
  mcpList.innerHTML="";
  data.forEach(function(s){
    var d=document.createElement("div");d.className="admin-item";
    var status=s.connected?"🟢":"⚪";
    d.innerHTML="<span>"+status+"</span><span class='ai-name'>"+escHtml(s.name)+"</span><span class='ai-meta'>"+s.toolCount+" tools</span><div class='ai-toggle"+(s.active?" on":"")+"'></div>";
    d.querySelector(".ai-toggle").onclick=function(){ws.send(JSON.stringify({type:"toggle_mcp",serverId:s.id,active:!s.active}))};
    mcpList.appendChild(d);
  });
}
function renderSkills(data){
  skillList.innerHTML="";
  data.forEach(function(s){
    var d=document.createElement("div");d.className="admin-item";
    d.innerHTML="<span class='ai-name'>"+escHtml(s.name)+"</span><span class='ai-meta'>"+escHtml(s.description||"").slice(0,30)+"</span><div class='ai-toggle"+(s.active?" on":"")+"'></div>";
    d.querySelector(".ai-toggle").onclick=function(){ws.send(JSON.stringify({type:"toggle_skill",skillId:s.id,active:!s.active}))};
    skillList.appendChild(d);
  });
}
function initAdminSearch(current){
  var radios=document.querySelectorAll("input[name='search-p']");
  radios.forEach(function(r){r.checked=(r.value===current);r.onchange=function(){ws.send(JSON.stringify({type:"set_search",provider:r.value}))}});
}
if(mcpToggleBtn)mcpToggleBtn.onclick=function(){showAdminPanel("mcp")};
if(skillToggleBtn)skillToggleBtn.onclick=function(){showAdminPanel("skill")};
if(searchToggleBtn)searchToggleBtn.onclick=function(){showAdminPanel("search")};
if(adminClose)adminClose.onclick=function(){adminDialog.close()};

// ── Events ──
inputEl.addEventListener("input",function(){inputEl.style.height="auto";inputEl.style.height=Math.min(inputEl.scrollHeight,140)+"px"});
inputEl.addEventListener("keydown",function(e){if(e.key==="Enter"&&!e.shiftKey){e.preventDefault();send()}});
sendBtn.addEventListener("click",send);
stopBtn.addEventListener("click",stopGen);
$("attach-btn").addEventListener("click",function(){fileInput.click()});
fileInput.addEventListener("change",function(){handleFiles(fileInput.files);fileInput.value=""});
fileChips.addEventListener("click",function(e){if(e.target.classList.contains("x")){pendingFiles.splice(+e.target.dataset.i,1);renderChips()}});
sidebarToggle.addEventListener("click",function(){sidebar.classList.toggle("hide")});
newChatBtn.addEventListener("click",newChat);
clearAllBtn.addEventListener("click",function(){if(confirm(T.clearConfirm)){localStorage.removeItem("ols_chats");localStorage.removeItem("ols_cur");newChat()}});
artifactsToggle.addEventListener("click",function(){artifactsPanel.classList.toggle("collapsed")});
closePanelBtn.addEventListener("click",function(){artifactsPanel.classList.add("collapsed")});
downloadAllBtn.addEventListener("click",function(){if(window._sessionId){window.open("/download/"+window._sessionId,"_blank")}});
previewClose.addEventListener("click",function(){previewEl.style.display="none"});
termToggle.addEventListener("click",function(){termPanel.classList.toggle("collapsed")});
termClear.addEventListener("click",function(){termOutput.innerHTML=""});
termClose.addEventListener("click",function(){termPanel.classList.add("collapsed")});
document.addEventListener("dragover",function(e){e.preventDefault()});
document.addEventListener("drop",function(e){e.preventDefault();if(e.dataTransfer.files.length)handleFiles(e.dataTransfer.files)});

// ── Init ──
(function(){
  // 国际化 HTML 静态文本
  document.title=T.welcome;
  var welH2=document.querySelector("#welcome-screen h2");if(welH2)welH2.textContent=T.welcome;
  var welP=document.querySelector("#welcome-screen p");if(welP)welP.textContent=T.welcomeHint;
  inputEl.placeholder=T.welcomeHint.slice(0,15)+"…";

  var chats=loadChats(),saved=loadCurrent();
  if(saved&&chats[saved])currentChatId=saved;
  else{var k=Object.keys(chats);if(k.length)currentChatId=k[k.length-1];else{newChat();connect();return}}
  saveCurrent(currentChatId);renderHistory();renderMessages();connect();
})();
})();
''';
}

