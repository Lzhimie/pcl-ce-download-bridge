'use strict';
const $ = (id) => document.getElementById(id);

function setStatus(t, err) {
  const el = $('status');
  el.textContent = t || '';
  el.className = 'status' + (err ? ' err' : '');
}

async function load() {
  const s = (await chrome.storage.local.get({
    enabled: true, silent: true, useSelectedFolder: true, pclPath: ''
  }));
  $('enabled').checked = !!s.enabled;
  $('silent').checked = !!s.silent;
  $('useSelectedFolder').checked = !!s.useSelectedFolder;
  $('pclPath').value = s.pclPath || '';
}

async function save() {
  await chrome.storage.local.set({
    enabled: $('enabled').checked,
    silent: $('silent').checked,
    useSelectedFolder: $('useSelectedFolder').checked,
    pclPath: $('pclPath').value.trim()
  });
  setStatus('已保存。');
}

['enabled', 'silent', 'useSelectedFolder'].forEach((id) =>
  $(id).addEventListener('change', save));

$('save').addEventListener('click', save);

$('test').addEventListener('click', async () => {
  setStatus('正在测试原生宿主…');
  const r = await chrome.runtime.sendMessage({ type: 'testHost' });
  if (r && r.ok) setStatus('原生宿主正常：' + (r.message || JSON.stringify(r)));
  else setStatus('原生宿主不可用：' + ((r && r.error) || '未知错误'), true);
});

$('pick').addEventListener('click', async () => {
  await save();
  const r = await chrome.runtime.sendMessage({ type: 'pickPcl', path: $('pclPath').value.trim() });
  if (r && r.ok) setStatus(r.message || ('已找到 PCL：' + r.path));
  else setStatus('未找到 PCL：' + ((r && r.error) || '未知错误'), true);
});

$('copyInstall').addEventListener('click', async () => {
  const cmd = 'powershell -ExecutionPolicy Bypass -File install-native-host.ps1';
  try {
    await navigator.clipboard.writeText(cmd);
    setStatus('已复制安装命令。请在 …\\pcl-download-bridge\\native-host 目录中粘贴执行。');
  } catch (e) {
    setStatus('复制失败，请手动输入：' + cmd, true);
  }
});

load();
