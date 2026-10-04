// PCL CE 下载接管 —— 确认窗口
'use strict';

const $ = (id) => document.getElementById(id);
let request = null;

function fmtSize(n) {
  if (!n || n <= 0) return '大小未知';
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = 0; let v = n;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return v.toFixed(i === 0 ? 0 : 1) + ' ' + u[i];
}

function setStatus(text, isErr) {
  const el = $('status');
  el.textContent = text || '';
  el.className = 'status' + (isErr ? ' err' : '');
}

function send(msg) {
  return new Promise((resolve) => chrome.runtime.sendMessage(msg, resolve));
}

async function init() {
  const q = new URLSearchParams(location.search).get('d');
  if (q) { try { request = JSON.parse(decodeURIComponent(q)); } catch {} }
  if (!request) {
    const r = await send({ type: 'getPending' });
    request = r && r.request;
  }
  if (!request) {
    setStatus('没有待处理的下载。', true);
    $('confirm').disabled = true;
    return;
  }

  $('url').value = request.url || '';
  $('filename').value = (request.filename || '').replace(/^.*[\\/]/, '');
  // 保存目录：优先用浏览器原定目录，否则读取 PCL CE 的默认下载目录
  $('folder').value = request.folder || '';
  if (request.folder) {
    $('folderHint').textContent = '已使用浏览器原定的保存目录，可修改或点“选择…”。';
  } else {
    loadDefaultFolder();
  }
  $('meta').textContent = '来源：' + (request.referrer || '直接访问') +
    '　·　大小：' + fmtSize(request.totalBytes);

  $('filename').focus();
  $('filename').select();
}

$('openUrl').addEventListener('click', () => send({ type: 'openUrlDirect' }));

$('cancel').addEventListener('click', async () => {
  await send({ type: 'cancel' });
  window.close();
});

$('saveAs').addEventListener('click', async () => {
  // 以“让 PCL 询问保存路径”的方式提交：清空目录
  await submit('', true);
});

$('confirm').addEventListener('click', async () => submit($('folder').value, $('autoStart').checked));

async function submit(folder, autoStart) {
  const filename = $('filename').value.trim();
  if (!filename) { setStatus('请填写文件名。', true); return; }
  $('confirm').disabled = true;
  $('saveAs').disabled = true;
  setStatus('正在唤起 PCL CE…');

  const res = await send({
    type: 'confirm', filename, folder: folder || '', autoStart: !!autoStart
  });

  if (res && res.ok) {
    setStatus(res.message || '已交给 PCL CE 下载，窗口即将关闭。');
    setTimeout(() => window.close(), 1200);
  } else {
    setStatus((res && res.error) || '启动 PCL 失败。', true);
    $('confirm').disabled = false;
    $('saveAs').disabled = false;
    $('browserFallback').style.display = 'inline-block';
  }
}

$('browserFallback').addEventListener('click', async () => {
  setStatus('正在交还给浏览器下载…');
  await send({ type: 'downloadInBrowser' });
  window.close();
});

// ── 读取 PCL CE 的默认下载目录 ──
async function loadDefaultFolder() {
  const res = await send({ type: 'getDefaultFolder' });
  if (res && res.ok && res.folder) {
    $('folder').value = res.folder;
    $('folderHint').textContent = '默认使用 PCL CE 的下载目录，可修改或点“选择…”。';
  } else {
    $('folderHint').textContent = '未能读取 PCL 默认目录，请点“选择…”指定，或留空让 PCL 询问。';
  }
}

// ── 选择目录（由原生宿主弹出系统文件夹选择框）──
$('browse').addEventListener('click', async () => {
  const btn = $('browse');
  btn.disabled = true;
  setStatus('正在打开文件夹选择框…（若没看到，请查看任务栏）');
  const res = await send({ type: 'pickFolder', initial: $('folder').value || '' });
  btn.disabled = false;
  if (res && res.ok && res.folder) {
    $('folder').value = res.folder;
    setStatus('已选择：' + res.folder);
    $('folderHint').textContent = '将保存到该目录。';
  } else if (res && res.ok && res.cancelled) {
    setStatus('已取消选择。');
  } else {
    setStatus('打开文件夹选择框失败：' + ((res && res.error) || '未知错误'), true);
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.isComposing) submit($('folder').value, $('autoStart').checked);
  if (e.key === 'Escape') send({ type: 'cancel' }).then(() => window.close());
});

init();
