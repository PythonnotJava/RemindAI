// AI 在线服务 — WebSocket 客户端
(function() {
  const messagesEl = document.getElementById('messages');
  const inputEl = document.getElementById('input');
  const sendBtn = document.getElementById('send-btn');
  const stopBtn = document.getElementById('stop-btn');
  const statusEl = document.getElementById('status');

  let ws = null;
  let streaming = false;
  let streamingEl = null;

  function connect() {
    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const url = `${protocol}//${location.host}/ws`;
    ws = new WebSocket(url);

    ws.onopen = () => {
      statusEl.textContent = '已连接';
      statusEl.className = 'connected';
    };

    ws.onclose = () => {
      statusEl.textContent = '已断开 (重连中...)';
      statusEl.className = 'error';
      setTimeout(connect, 3000);
    };

    ws.onerror = () => {
      statusEl.textContent = '连接错误';
      statusEl.className = 'error';
    };

    ws.onmessage = (event) => {
      const msg = JSON.parse(event.data);
      handleMessage(msg);
    };
  }

  function handleMessage(msg) {
    switch (msg.type) {
      case 'welcome':
        addSystem(`欢迎, ${msg.nickname}`);
        break;
      case 'token':
        if (!streamingEl) {
          streamingEl = addMessage('assistant', '', true);
        }
        streamingEl.textContent += msg.text;
        scrollToBottom();
        break;
      case 'done':
        if (streamingEl) {
          streamingEl.classList.remove('streaming');
          streamingEl = null;
        }
        setStreaming(false);
        break;
      case 'stopped':
        if (streamingEl) {
          streamingEl.classList.remove('streaming');
          streamingEl.textContent += '\n[已停止]';
          streamingEl = null;
        }
        setStreaming(false);
        break;
      case 'error':
        addSystem(`错误: ${msg.message}`);
        setStreaming(false);
        break;
      case 'disconnect':
        addSystem(`连接已断开: ${msg.reason}`);
        break;
      case 'cleared':
        messagesEl.innerHTML = '';
        addSystem('对话已清空');
        break;
    }
  }

  function send() {
    const text = inputEl.value.trim();
    if (!text || !ws || ws.readyState !== WebSocket.OPEN) return;

    addMessage('user', text);
    ws.send(JSON.stringify({ type: 'chat', content: text }));
    inputEl.value = '';
    inputEl.style.height = 'auto';
    setStreaming(true);
  }

  function stop() {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'stop' }));
    }
  }

  function addMessage(role, text, isStreaming = false) {
    const el = document.createElement('div');
    el.className = `message ${role}${isStreaming ? ' streaming' : ''}`;
    el.textContent = text;
    messagesEl.appendChild(el);
    scrollToBottom();
    return el;
  }

  function addSystem(text) {
    const el = document.createElement('div');
    el.className = 'message system';
    el.textContent = text;
    messagesEl.appendChild(el);
    scrollToBottom();
  }

  function setStreaming(val) {
    streaming = val;
    sendBtn.style.display = val ? 'none' : 'flex';
    stopBtn.style.display = val ? 'flex' : 'none';
    sendBtn.disabled = val;
  }

  function scrollToBottom() {
    const main = document.querySelector('main');
    main.scrollTop = main.scrollHeight;
  }

  // 输入框自适应高度
  inputEl.addEventListener('input', () => {
    inputEl.style.height = 'auto';
    inputEl.style.height = Math.min(inputEl.scrollHeight, 120) + 'px';
  });

  // Enter 发送, Shift+Enter 换行
  inputEl.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      send();
    }
  });

  sendBtn.addEventListener('click', send);
  stopBtn.addEventListener('click', stop);

  // 启动连接
  connect();
})();
