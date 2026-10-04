'use strict';
const $ = (id) => document.getElementById(id);

function setStatus(t, isErr) {
  const el = $('status');
  el.textContent = t || '';
  el.className = isErr ? 'err' : '';
}

function setDot(id, state, text) {
  $(id).className = 'dot ' + state;
  $(id.replace('dot', 'txt')).textContent = text;
}

const send = (msg) => new Promise((res) => chrome.runtime.sendMessage(msg, (r) => {
  if (chrome.runtime.lastError) res({ ok: false, error: chrome.runtime.lastError.message });
  else res(r);
}));

async function refresh() {
  // 本地设置
  const s = await chrome.storage.local.get({ enabled: true, useSelectedFolder: true, pclPath: '' });
  $('enabled').checked = !!s.enabled;
  $('useSelectedFolder').checked = !!s.useSelectedFolder;

  // 宿主状态
  setDot('dotHost', 'idle', '正在检查原生宿主…');
  const host = await send({ type: 'testHost' });
  if (host && host.ok) {
    setDot('dotHost', 'ok', '原生宿主正常');
  } else {
    setDot('dotHost', 'bad', '原生宿主不可用：' + ((host && host.error) || '未知'));
    setDot('dotPcl', 'idle', '——');
    $('pclPath').value = s.pclPath || '';
    return;
  }

  // PCL 路径与状态
  const info = await send({ type: 'getPclPath' });
  if (info && info.ok) {
    $('pclPath').value = info.path || s.pclPath || '';
    if (info.pclRunning) {
      setDot('dotPcl', 'ok', 'PCL 正在运行');
    } else if (info.exists) {
      setDot('dotPcl', 'ok', 'PCL 已找到（未运行，点下载会自动启动）');
    } else {
      setDot('dotPcl', 'bad', '未找到 PCL，请在下面填路径');
    }
  } else {
    $('pclPath').value = s.pclPath || '';
    setDot('dotPcl', 'bad', '无法读取 PCL 状态');
  }
}

$('save').addEventListener('click', async () => {
  const p = $('pclPath').value.trim();
  setStatus('正在保存…');
  const r = await send({ type: 'setPclPath', path: p });
  if (r && r.ok) { setStatus('已保存：' + (p || '（留空，自动探测）')); await refresh(); }
  else setStatus('保存失败：' + ((r && r.error) || '未知'), true);
});

$('browse').addEventListener('click', async () => {
  setStatus('正在打开文件夹选择框…（若没看到请查看任务栏）');
  const r = await send({ type: 'pickFolder', initial: $('pclPath').value || '' });
  if (r && r.ok && r.folder) {
    $('pclPath').value = r.folder;
    setStatus('已选目录，点「保存路径」后会自动定位其中的 PCL');
  } else if (r && r.ok && r.cancelled) {
    setStatus('已取消选择。');
  } else {
    setStatus('打开失败：' + ((r && r.error) || '未知'), true);
  }
});

$('detect').addEventListener('click', async () => {
  setStatus('正在自动探测…');
  const r = await send({ type: 'pickPcl', path: '' });
  if (r && r.ok && r.path) { $('pclPath').value = r.path; setStatus('探测到：' + r.path); }
  else setStatus('未探测到，请手动填写。', true);
});

['enabled', 'useSelectedFolder'].forEach((id) =>
  $(id).addEventListener('change', async () => {
    await chrome.storage.local.set({ [id]: $(id).checked });
    setStatus('设置已保存。');
  }));

$('more').addEventListener('click', (e) => { e.preventDefault(); chrome.runtime.openOptionsPage(); });

refresh();
