# PCL CE 下载接管 —— 原生宿主安装脚本（当前用户，无需管理员）
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File install-native-host.ps1
#   powershell -ExecutionPolicy Bypass -File install-native-host.ps1 -ExtensionId <32位ID>
#   powershell -ExecutionPolicy Bypass -File install-native-host.ps1 -Uninstall
#
# 不传 -ExtensionId 时会尝试自动识别（需先在浏览器里加载好扩展）。
param(
    [string]$ExtensionId = '',
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$HostName   = 'cc.pclc.download_bridge'
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExtDir     = Join-Path (Split-Path -Parent $ScriptDir) 'extension'
$HostScript = Join-Path $ScriptDir 'native-host.ps1'
$ManifestPath = Join-Path $ScriptDir 'cc.pclc.download_bridge.json'

function Say($t, $c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Ok($t)  { Write-Host ('  [OK] ' + $t) -ForegroundColor Green }
function Bad($t) { Write-Host ('  [!] ' + $t) -ForegroundColor Yellow }

if ($Uninstall) {
    foreach ($k in @(
        ('HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\' + $HostName),
        ('HKCU:\Software\Google\Chrome\NativeMessagingHosts\' + $HostName))) {
        if (Test-Path $k) { Remove-Item $k -Recurse -Force; Ok ('已删除 ' + $k) }
    }
    if (Test-Path $ManifestPath) { Remove-Item $ManifestPath -Force; Ok ('已删除 ' + $ManifestPath) }
    Say '卸载完成。' 'Green'
    exit 0
}

Say ''
Say '=== PCL CE 下载接管 - 原生宿主安装 ===' 'White'

if (-not (Test-Path $HostScript)) { Say ('找不到宿主脚本: ' + $HostScript) 'Red'; exit 1 }

function Find-ExtensionId {
    $target = Resolve-Path $ExtDir -ErrorAction SilentlyContinue
    if (-not $target) { return $null }
    $targetPath = $target.Path.TrimEnd('\')
    $profiles = @()
    foreach ($base in @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'))) {
        if (-not (Test-Path $base)) { continue }
        $profiles += (Join-Path $base 'Default\Secure Preferences')
        $profiles += (Join-Path $base 'Default\Preferences')
        Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $profiles += (Join-Path $_.FullName 'Secure Preferences')
            $profiles += (Join-Path $_.FullName 'Preferences')
        }
    }
    foreach ($f in ($profiles | Select-Object -Unique)) {
        if (-not (Test-Path $f)) { continue }
        try {
            $raw = Get-Content $f -Raw -Encoding UTF8
            if ($raw -notmatch 'extensions') { continue }
            $json = $raw | ConvertFrom-Json
            $settings = $json.extensions.settings
            if (-not $settings) { continue }
            foreach ($prop in $settings.PSObject.Properties) {
                $id  = $prop.Name
                $val = $prop.Value
                $p   = $val.path
                if (-not $p) { continue }
                $norm = ([string]$p).TrimEnd('\')
                if ($norm -ieq $targetPath -and $id -match '^[a-p]{32}$') {
                    Say ('    在 ' + (Split-Path $f -Leaf) + ' 找到扩展: ' + $id)
                    return $id
                }
            }
        } catch { }
    }
    return $null
}

Say ''
Say '[1/4] 识别扩展 ID' 'Cyan'
if (-not $ExtensionId) {
    $ExtensionId = Find-ExtensionId
    if ($ExtensionId) { Ok ('自动识别为 ' + $ExtensionId) }
}
if (-not $ExtensionId) {
    Bad '未能自动识别扩展 ID。'
    Say ''
    Say '请先在浏览器中加载扩展：' 'White'
    Say '  1) Edge 打开  edge://extensions/   （Chrome 为 chrome://extensions/）'
    Say '  2) 打开左下角“开发人员模式”'
    Say ('  3) 点“加载解压缩的扩展”，选择目录：' + $ExtDir)
    Say '  4) 复制扩展卡片上显示的 32 位 ID，然后重新运行本脚本并加 -ExtensionId <ID>'
    exit 1
}
if ($ExtensionId -notmatch '^[a-p]{32}$') { Say ('扩展 ID 格式不正确: ' + $ExtensionId) 'Red'; exit 1 }

Say ''
Say '[2/4] 校验宿主脚本语法' 'Cyan'
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($HostScript, [ref]$null, [ref]$errs)
if ($errs -and $errs.Count -gt 0) {
    $errs | Select-Object -First 5 | ForEach-Object { Say ('    ' + $_.Message) 'Red' }
    exit 1
}
Ok '语法正常'

Say ''
Say '[3/4] 写入原生消息清单' 'Cyan'
$manifest = [ordered]@{
    name            = $HostName
    description     = 'PCL CE Download Bridge - 把浏览器下载交给 PCL CE'
    # 清单 path 必须是可执行文件；.ps1 不能直接用作 native messaging host
    path            = (Join-Path $ScriptDir 'native-host.cmd')
    type            = 'stdio'
    allowed_origins = @('chrome-extension://' + $ExtensionId + '/')
}
# 关键：原生消息清单必须是「无 BOM 的 UTF-8」，否则浏览器拒绝加载（报 communicating with the native messaging host）
$json = $manifest | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText($ManifestPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Ok $ManifestPath

Say ''
Say '[4/4] 注册浏览器原生消息宿主（当前用户）' 'Cyan'
# 覆盖 Edge / Chrome 的所有可能位置（含 Beta/Dev/Canary 与 WOW6432Node）
$regTargets = @(
    @('Edge',         'HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\'),
    @('Edge Beta',    'HKCU:\Software\Microsoft\Edge Beta\NativeMessagingHosts\'),
    @('Edge Dev',     'HKCU:\Software\Microsoft\Edge Dev\NativeMessagingHosts\'),
    @('Edge Canary',  'HKCU:\Software\Microsoft\Edge Canary\NativeMessagingHosts\'),
    @('Chrome',       'HKCU:\Software\Google\Chrome\NativeMessagingHosts\'),
    @('Chrome Beta',  'HKCU:\Software\Google\Chrome Beta\NativeMessagingHosts\'),
    @('Chrome Dev',   'HKCU:\Software\Google\Chrome Dev\NativeMessagingHosts\'),
    @('Chromium',     'HKCU:\Software\Chromium\NativeMessagingHosts\'),
    @('Edge(32)',     'HKCU:\Software\WOW6432Node\Microsoft\Edge\NativeMessagingHosts\'),
    @('Chrome(32)',   'HKCU:\Software\WOW6432Node\Google\Chrome\NativeMessagingHosts\'))
foreach ($pair in $regTargets) {
    $key = $pair[1] + $HostName
    New-Item -Path $key -Force | Out-Null
    Set-ItemProperty -Path $key -Name '(default)' -Value $ManifestPath
    Ok ($pair[0].PadRight(12) + ' -> ' + $key)
}

$dataDir = Join-Path $env:LOCALAPPDATA 'PCLDownloadBridge'
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Force -Path $dataDir | Out-Null }

Say ''
Say '=== 安装完成 ===' 'Green'
Say ('扩展 ID   : ' + $ExtensionId)
Say ('宿主脚本  : ' + $HostScript)
Say ('日志文件  : ' + (Join-Path $dataDir 'bridge.log'))
Say ''
Say '接着在扩展设置页点“测试原生宿主”，应显示“原生宿主正常”。' 'White'
Say '若刚加载扩展，请重新加载扩展后再测试。' 'DarkGray'
