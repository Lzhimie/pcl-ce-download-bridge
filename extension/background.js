// PCL CE 下载接管 —— 后台 Service Worker
// 职责：拦截浏览器下载 -> 取消原生下载 -> 弹出确认窗口 -> 交给原生宿主唤起 PCL 下载
'use strict';

const HOST_NAME = 'cc.pclc.download_bridge';
const DEFAULTS = {
  enabled: true,
  silent: true,              // true = 不弹确认窗，直接把信息填进 PCL（默认）
  useSelectedFolder: true,   // true = 优先使用浏览器原定的保存目录
  pclPath: ''                // 手动指定 PCL.exe，留空则自动探测
};

let dialogTab = null;          // 当前确认窗口所在的标签页
let pendingRequest = null;     // 等待确认的下载请求
let lastDownload = null;       // 最近一次被拦截的下载（供退回浏览器使用）

// ─────────────────────────────────────────────
// 初始化
// ─────────────────────────────────────────────
chrome.runtime.onInstalled.addListener(async () => {
  const cur = await chrome.storage.local.get(DEFAULTS);
  await chrome.storage.local.set({ ...DEFAULTS, ...cur });
  console.log('[PCL Bridge] 已安装/更新');
});

chrome.runtime.onStartup.addListener(() => {
  console.log('[PCL Bridge] 浏览器启动');
});

// ─────────────────────────────────────────────
// 1. 拦截所有下载
// ─────────────────────────────────────────────
chrome.downloads.onDeterminingFilename.addListener((item) => {
  // 同步取消，避免浏览器先落地文件
  try {
    chrome.downloads.cancel(item.id).catch(() => {});
    chrome.downloads.erase({ id: item.id }).catch(() => {});
  } catch (e) {
    console.warn('[PCL Bridge] 取消下载失败：', e);
  }

  handleIntercept(item).catch((err) => {
    console.error('[PCL Bridge] 处理下载失败：', err);
  });
});

async function handleIntercept(item) {
  const cfg = { ...DEFAULTS, ...(await chrome.storage.local.get(DEFAULTS)) };

  const url = item.finalUrl || item.url || '';
  const filename = baseName(item.filename || 'download.bin');

  if (isSelfDialogDownload(url)) return;

  if (!cfg.enabled) {
    reDownloadToBrowser(url, filename);
    return;
  }

  lastDownload = { url, filename };

  let dir = cfg.useSelectedFolder ? folderFromPath(item.filename) : '';
  console.log('[PCL Bridge] 已拦截下载：', filename, '保存目录=', dir || '(未提供)');

  // ── 唯一路径：不弹任何窗口，只把「下载地址 + 文件名」填进 PCL ──
  // 绝不点击“开始下载”，那一步始终由用户在 PCL 界面里自己完成。
  const res = await startPclDownload({ url, filename, folder: '', userAgent: '' });
  if (res && res.ok) {
    notifyBadge('PCL', '#3b82f6');
    console.log('[PCL Bridge] 已填好并唤起 PCL：', filename);
  } else {
    notifyBadge('!', '#ef4444');
    console.warn('[PCL Bridge] 交接失败：', res && res.error);
  }
}

// 用角标给出无打扰的操作反馈
function notifyBadge(text, color, ms) {
  try {
    chrome.action.setBadgeBackgroundColor({ color: color || '#3b82f6' });
    chrome.action.setBadgeText({ text: text || '' });
    if (text) {
      setTimeout(() => { try { chrome.action.setBadgeText({ text: '' }); } catch (e) {} }, ms || 4000);
    }
  } catch (e) { }
}

function reDownloadToBrowser(url, filename) {
  if (!url) return;
  try {
    chrome.downloads.download({
      url, filename: baseName(filename), conflictAction: 'uniquify'
    }).catch((e) => console.error('[PCL Bridge] 交还浏览器下载失败：', e));
  } catch (e) {
    console.error('[PCL Bridge] 交还浏览器下载失败：', e);
  }
}

function isSelfDialogDownload(url) {
  return typeof url === 'string' &&
    url.startsWith('chrome-extension://') && url.includes('dialog.html');
}

// 从完整路径取目录（含结尾反斜杠）
function folderFromPath(fullPath) {
  if (!fullPath) return '';
  const norm = String(fullPath).replace(/[/]/g, '\\');
  const idx = norm.lastIndexOf('\\');
  if (idx < 0) return '';
  return norm.slice(0, idx + 1);
}

function baseName(p) {
  if (!p) return 'download.bin';
  const norm = String(p).replace(/\\/g, '/');
  return norm.slice(norm.lastIndexOf('/') + 1) || 'download.bin';
}

// ─────────────────────────────────────────────
// 2. 确认窗口
// ─────────────────────────────────────────────
async function showDialog(req) {
  const data = encodeURIComponent(JSON.stringify(req));
  const url = chrome.runtime.getURL('dialog.html?d=' + data);

  if (dialogTab) {
    try {
      await chrome.tabs.update(dialogTab, { url, active: true });
      const t = await chrome.tabs.get(dialogTab);
      await chrome.windows.update(t.windowId, { focused: true });
      return;
    } catch { dialogTab = null; }
  }
  const tab = await chrome.tabs.create({ url, active: true });
  dialogTab = tab.id;
  try {
    const win = await chrome.windows.create({
      tabId: tab.id, type: 'popup', width: 620, height: 560, focused: true
    });
    if (win && win.tabs && win.tabs[0]) dialogTab = win.tabs[0].id;
  } catch (e) { }
}

chrome.tabs.onRemoved.addListener((tabId) => {
  if (tabId === dialogTab) dialogTab = null;
});

// ─────────────────────────────────────────────
// 3. 与确认窗口 / 设置页通信
// ─────────────────────────────────────────────
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  (async () => {
    switch (msg && msg.type) {
      case 'getPending':
        sendResponse({ ok: true, request: pendingRequest });
        break;

      case 'confirm': {
        const req = pendingRequest;
        if (!req) { sendResponse({ ok: false, error: '没有待处理的下载' }); break; }
        const result = await startPclDownload({
          url: req.url,
          filename: msg.filename || baseName(req.filename),
          folder: msg.folder || '',
          userAgent: ''
        });
        result.url = req.url;
        result.filename = baseName(req.filename);
        if (result.ok) pendingRequest = null;
        sendResponse(result);
        break;
      }

      case 'cancel':
        pendingRequest = null;
        closeDialog();
        sendResponse({ ok: true });
        break;

      case 'downloadInBrowser': {
        const src = pendingRequest || lastDownload;
        if (src) reDownloadToBrowser(src.url, src.filename);
        pendingRequest = null;
        closeDialog();
        sendResponse({ ok: true });
        break;
      }

      case 'openUrlDirect':
        if (pendingRequest) {
          chrome.tabs.create({ url: pendingRequest.url, active: false }).catch(() => {});
        }
        sendResponse({ ok: true });
        break;

      // 弹窗：读取 PCL 路径与状态
      case 'getPclPath':
        sendResponse(await callNative({ action: 'getPclPath' }));
        break;

      // 弹窗：保存 PCL 路径（空 = 清空让宿主自动探测）
      case 'setPclPath': {
        const p = (msg.path || '').trim();
        // 允许填 exe 或所在文件夹，由宿主负责解析
        const r = await callNative({ action: 'pickPcl', path: p, extensionId: chrome.runtime.id });
        if (r && r.ok && r.path) {
          await chrome.storage.local.set({ pclPath: r.path });
          sendResponse({ ok: true, path: r.path, message: '已保存并校验通过' });
        } else if (!p) {
          await chrome.storage.local.set({ pclPath: '' });
          sendResponse({ ok: true, path: '', message: '已清空，将自动探测' });
        } else {
          sendResponse({ ok: false, error: (r && r.error) || '宿主没能识别该位置' });
        }
        break;
      }

      // 读取 PCL CE 的默认下载目录
      case 'getDefaultFolder':
        sendResponse(await callNative({ action: 'getDefaultFolder' }));
        break;

      // 弹出系统文件夹选择框（由原生宿主实现）
      case 'pickFolder':
        sendResponse(await callNative({ action: 'pickFolder', initial: msg.initial || '' }));
        break;

      case 'getSettings':
        sendResponse({ ok: true, settings: await chrome.storage.local.get(DEFAULTS) });
        break;

      case 'saveSettings':
        await chrome.storage.local.set(msg.settings || {});
        sendResponse({ ok: true });
        break;

      case 'testHost':
        sendResponse(await callNative({ action: 'ping', extensionId: chrome.runtime.id }));
        break;

      case 'pickPcl':
        sendResponse(await callNative({
          action: 'pickPcl', path: msg.path || '', extensionId: chrome.runtime.id
        }));
        break;

      default:
        sendResponse({ ok: false, error: '未知消息：' + (msg && msg.type) });
    }
  })().catch((e) => sendResponse({ ok: false, error: String(e) }));
  return true;
});

function closeDialog() {
  if (dialogTab != null) {
    const id = dialogTab; dialogTab = null;
    chrome.tabs.remove(id).catch(() => {});
  }
}

// ─────────────────────────────────────────────
// 4. 调用原生宿主
// ─────────────────────────────────────────────
function callNative(payload) {
  return new Promise((resolve) => {
    let port;
    try {
      port = chrome.runtime.connectNative(HOST_NAME);
    } catch (e) {
      resolve({ ok: false, error: '无法连接原生宿主：' + e.message + '（请先运行 install-native-host.ps1）' });
      return;
    }

    let settled = false;
    const finish = (r) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { port.disconnect(); } catch (e) {}
      resolve(r);
    };

    const timer = setTimeout(() => {
      finish({ ok: false, error: '原生宿主响应超时（90 秒），请查看 %LOCALAPPDATA%\PCLDownloadBridge\bridge.log' });
    }, 90000);

    port.onMessage.addListener((resp) => finish(resp));

    port.onDisconnect.addListener(() => {
      const err = chrome.runtime.lastError;
      finish({
        ok: false,
        error: err ? err.message
                   : '原生宿主断开：未注册或扩展 ID 不匹配，请重新运行 install-native-host.ps1 后重载扩展'
      });
    });

    try { port.postMessage(payload); }
    catch (e) { finish({ ok: false, error: String(e) }); }
  });
}

async function startPclDownload(info) {
  const cfg = { ...DEFAULTS, ...(await chrome.storage.local.get(DEFAULTS)) };
  return await callNative({
    action: 'download',
    url: info.url,
    filename: info.filename,
    folder: info.folder,
    userAgent: info.userAgent || '',
    pclPath: cfg.pclPath || '',
    extensionId: chrome.runtime.id
  });
}
