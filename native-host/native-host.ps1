#requires -Version 5.1
<#
  PCL CE 下载接管 —— 原生消息宿主（Native Messaging Host）
  由浏览器扩展启动。协议：stdin/stdout 上 [4 字节小端长度][UTF-8 JSON]，无 BOM。
  功能：定位/启动 PCL CE，通过 UI Automation 自动填写
        “工具 -> 下载自定义文件”的【下载地址】【文件名】【保存到】。
  约定：本宿主绝不点击“开始下载”，该动作始终由用户在 PCL 界面里自己完成。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:ConfigPath = Join-Path $env:LOCALAPPDATA 'PCLDownloadBridge\config.json'
$script:LogPath    = Join-Path $env:LOCALAPPDATA 'PCLDownloadBridge\bridge.log'
$script:LF  = [string][char]10
$script:ESC = [char]27

function Write-Log([string]$msg) {
    try {
        $dir = Split-Path $script:LogPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Add-Content -Path $script:LogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg) -Encoding UTF8
    } catch { }
}

# 启动即记录：便于确认扩展是否真的调用了宿主
Write-Log ('宿主启动，PID=' + $PID)

function Read-Message {
    $stdin = [Console]::OpenStandardInput()
    $lenBuf = New-Object byte[] 4
    $read = 0
    while ($read -lt 4) {
        $n = $stdin.Read($lenBuf, $read, 4 - $read)
        if ($n -le 0) { return $null }
        $read += $n
    }
    $len = [BitConverter]::ToInt32($lenBuf, 0)
    if ($len -le 0 -or $len -gt 16MB) {
        Write-Log ('收到非法长度字段: ' + $len + '，判定为连接结束')
        return $null
    }
    Write-Log ('收到请求，长度=' + $len)
    $buf = New-Object byte[] $len
    $read = 0
    while ($read -lt $len) {
        $n = $stdin.Read($buf, $read, $len - $read)
        if ($n -le 0) { break }
        $read += $n
    }
    if ($read -lt $len) { Write-Log ('警告：只读到 ' + $read + '/' + $len + ' 字节') }
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
}

function Write-Message($obj) {
    $json = $obj | ConvertTo-Json -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $lenBuf = [BitConverter]::GetBytes([int]$bytes.Length)
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($lenBuf, 0, 4)
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
}

function Get-BridgeConfig {
    $cfg = [PSCustomObject]@{ pclPath = ''; lastUsed = '' }
    try {
        if (Test-Path $script:ConfigPath) {
            $j = Get-Content $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.pclPath)  { $cfg.pclPath  = [string]$j.pclPath }
            if ($j.lastUsed) { $cfg.lastUsed = [string]$j.lastUsed }
        }
    } catch { }
    return $cfg
}

function Save-BridgeConfig($cfg) {
    try {
        $dir = Split-Path $script:ConfigPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $cfg | ConvertTo-Json -Depth 4 | Set-Content -Path $script:ConfigPath -Encoding UTF8
    } catch { Write-Log "保存配置失败: $_" }
}

function Get-CandidatePaths([string]$explicit) {
    $list = New-Object System.Collections.Generic.List[string]
    if ($explicit) { $list.Add($explicit) }
    $cfg = Get-BridgeConfig
    if ($cfg.pclPath)  { $list.Add($cfg.pclPath) }
    if ($cfg.lastUsed) { $list.Add($cfg.lastUsed) }
    # 固定候选位置
    $list.Add((Join-Path $PSScriptRoot 'PCL.exe'))
    $list.Add((Join-Path ([Environment]::GetFolderPath('Desktop')) 'PCL.exe'))
    $list.Add((Join-Path $env:USERPROFILE 'Desktop\PCL.exe'))
    foreach ($root in @($env:LOCALAPPDATA, $env:APPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $root) { continue }
        foreach ($sub in @('PCL', 'PCLCE', 'Plain Craft Launcher', 'Programs\PCL')) {
            $list.Add((Join-Path (Join-Path $root $sub) 'PCL.exe'))
        }
    }

    return $list | Where-Object { $_ } | Select-Object -Unique
}

# 在常见目录里浅层搜索 PCL 可执行文件（找不到时的兜底）
function Find-PclBySearch {
    $roots = @(
        (Join-Path $env:USERPROFILE 'Downloads'),
        ([Environment]::GetFolderPath('Desktop')),
        (Join-Path $env:USERPROFILE 'Documents'),
        $env:USERPROFILE,
        (Join-Path $env:USERPROFILE 'Desktop\PCL'),
        'D:\', 'E:\', 'F:\'
    )
    # 只认新的 PCL / PCL CE；排除旧版「Plain Craft Launcher 2.exe」和各种安装器
    $patterns = @('PCL*.exe')
    $exclude = '(?i)uninst|setup|install|-web|updater|Plain Craft Launcher'
    foreach ($root in $roots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        foreach ($pat in $patterns) {
            try {
                # 只看当前目录和下一层，避免全盘扫描
                $hits = Get-ChildItem -LiteralPath $root -Filter $pat -File -ErrorAction SilentlyContinue
                foreach ($h in $hits) {
                    if ($h.Length -gt 64KB -and $h.Name -notmatch $exclude) { return $h.FullName }
                }
                $dirs = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Select-Object -First 40
                foreach ($d in $dirs) {
                    $hits2 = Get-ChildItem -LiteralPath $d.FullName -Filter $pat -File -ErrorAction SilentlyContinue
                    foreach ($h in $hits2) {
                        if ($h.Length -gt 64KB -and $h.Name -notmatch $exclude) { return $h.FullName }
                    }
                }
            } catch { }
        }
    }
    return $null
}

function Get-RunningPclProcess {
    return Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -like 'PCL*' -or $_.ProcessName -like 'Plain Craft Launcher*' -or
        ($_.MainWindowTitle -and $_.MainWindowTitle -match 'Plain Craft Launcher')
    } | Select-Object -First 1
}

function Resolve-PclPath([string]$explicit) {
    $found = Resolve-PclPathFromList $explicit
    if ($found) { return $found }
    # 固定候选都没有时，去常见目录浅层搜索（并记住结果）
    $searched = Find-PclBySearch
    if ($searched) {
        try {
            $cfg = Get-BridgeConfig
            if ($cfg.pclPath -ne $searched) { $cfg.pclPath = $searched; Save-BridgeConfig $cfg }
        } catch { }
        Write-Log ('搜索找到 PCL: ' + $searched)
    }
    return $searched
}

function Resolve-PclPathFromList([string]$explicit) {
    foreach ($c in Get-CandidatePaths $explicit) {
        try {
            if (Test-Path -LiteralPath $c -PathType Leaf) {
                $item = Get-Item -LiteralPath $c
                if ($item.Length -gt 64KB) { return $item.FullName }
            }
        } catch { }
    }
    return $null
}

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms

# PCL 的 MyButton 是 WPF 自定义控件，在 UIA 中只暴露 TextBlock（无 InvokePattern），
# 因此按钮统一用“移动到元素矩形中心并点击”的方式触发。
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class WinMouse { [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y); [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n); [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); public static void Click(int x, int y) { SetCursorPos(x, y); System.Threading.Thread.Sleep(120); mouse_event(0x0002, 0, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(60); mouse_event(0x0004, 0, 0, 0, IntPtr.Zero); } public static void Front(IntPtr h) { ShowWindow(h, 9); SetForegroundWindow(h); } }'

# ── 默认下载目录检测（与 PCL 自身逻辑保持一致）────────────────
# PCL 的「下载自定义文件」读取 CacheDownloadFolder；为空或无效则回落到 <PCL目录>\PCL\MyDownload\
function Get-PclDefaultFolder {
    $result = Get-PclDefaultFolderRaw
    # PCL 不会预创建 MyDownload 目录，这里补建，便于“选择目录”对话框正确定位
    try {
        if ($result -and -not (Test-Path -LiteralPath $result)) { New-Item -ItemType Directory -Force -Path $result | Out-Null }
    } catch { }
    return $result
}

function Get-PclDefaultFolderRaw {
    $proc = Get-RunningPclProcess
    $exeDir = $null
    if ($proc) {
        try { $exeDir = Split-Path $proc.Path -Parent } catch { }
    }
    if (-not $exeDir) {
        $p = Resolve-PclPath ''
        if ($p) { $exeDir = Split-Path $p -Parent }
    }

    # 1) PCL 配置文件里持久化的 CacheDownloadFolder（用户主动设置过，优先级最高）
    if ($exeDir) {
        $cfg = Join-Path (Join-Path $exeDir 'PCL') 'config.v1.yml'
        if (Test-Path $cfg) {
            try {
                $line = Select-String -Path $cfg -Pattern '^\s*CacheDownloadFolder\s*:' -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($line) {
                    $v = ($line.Line -replace '^\s*CacheDownloadFolder\s*:\s*', '').Trim().Trim('"').Trim("'")
                    if ($v) { return $v }
                }
            } catch { }
        }
    }

    # 2) 运行中的 PCL「下载自定义文件」输入框当前值（PCL 自己会预填的上次使用目录）
    if ($proc) {
        try {
            $win = Get-PclWindow $proc.Id
            if ($win) {
                $box = Find-ById $win 'TextDownloadFolder' 1
                if ($box) {
                    $v = ($box.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)).Current.Value
                    if ($v -and $v.Trim()) { return $v.Trim() }
                }
            }
        } catch { }
    }

    # 3) PCL 的硬编码默认值：<PCL目录>\PCL\MyDownload\
    if ($exeDir) {
        $fallback = Join-Path (Join-Path $exeDir 'PCL') 'MyDownload'
        return ($fallback.TrimEnd([char]92) + [char]92)
    }

    # 4) 最后兜底：Windows 下载目录
    $dl = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
    return ($dl.TrimEnd([char]92) + [char]92)
}

# ── 目录选择对话框（SHBrowseForFolder，原生且轻量）──────────────
if (-not ([System.Management.Automation.PSTypeName]'FolderPicker').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class FolderPicker {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr SHBrowseForFolder(ref BROWSEINFO lpbi);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern bool SHGetPathFromIDList(IntPtr pidl, System.Text.StringBuilder pszPath);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct BROWSEINFO {
        public IntPtr hwndOwner;
        public IntPtr pidlRoot;
        public string pszDisplayName;
        public string lpszTitle;
        public uint ulFlags;
        public IntPtr lpfn;
        public IntPtr lParam;
        public int iImage;
    }
    public static string Show(string title, string initialPath) {
        BROWSEINFO bi = new BROWSEINFO();
        bi.lpszTitle = title;
        bi.ulFlags = 0x0001 | 0x0010 | 0x0040;
        if (!string.IsNullOrEmpty(initialPath)) {
            try {
                Type t = Type.GetTypeFromProgID("Shell.Application");
                object shell = Activator.CreateInstance(t);
                object folder = t.InvokeMember("NameSpace", System.Reflection.BindingFlags.InvokeMethod, null, shell, new object[] { initialPath });
                if (folder != null) { bi.pidlRoot = (IntPtr)folder.GetType().InvokeMember("Self", System.Reflection.BindingFlags.GetProperty, null, folder, null); }
            } catch { }
        }
        IntPtr pidl = SHBrowseForFolder(ref bi);
        if (pidl == IntPtr.Zero) { return null; }
        var sb = new System.Text.StringBuilder(260);
        bool ok = SHGetPathFromIDList(pidl, sb);
        Marshal.FreeCoTaskMem(pidl);
        return ok ? sb.ToString() : null;
    }
}
"@
}

function Select-Folder([string]$title, [string]$initial) {
    try { return [FolderPicker]::Show($title, $initial) }
    catch { Write-Log "目录选择器失败: $_"; return $null }
}
function Get-PclWindow([int]$processId = 0) {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    if ($processId -gt 0) {
        $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $processId)
        $w = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
        if ($w) { return $w }
    }
    $cond2 = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, 'Window')
    foreach ($w in $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond2)) {
        try { if ($w.Current.Name -match 'Plain Craft Launcher') { return $w } } catch { }
    }
    return $null
}

# 自愈：确保原生消息清单与注册表可用（宿主脚本更新后自动重注册）
function Register-NativeHost([string]$extensionId) {
    if (-not $extensionId -or $extensionId -notmatch '^[a-p]{32}$') { return }
    try {
        $hostName = 'cc.pclc.download_bridge'
        $manifestPath = Join-Path $PSScriptRoot 'cc.pclc.download_bridge.json'
        $wantOrigin = 'chrome-extension://' + $extensionId + '/'
        # 清单 path 必须指向可执行文件，因此指向 .cmd 启动器而非 .ps1
        $wantPath = Join-Path $PSScriptRoot 'native-host.cmd'
        $need = $true
        if (Test-Path $manifestPath) {
            try {
                $cur = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($cur.allowed_origins -contains $wantOrigin -and $cur.path -eq $wantPath) { $need = $false }
            } catch { }
        }
        if ($need) {
            $m = [ordered]@{
                name            = $hostName
                description     = 'PCL CE Download Bridge - 把浏览器下载交给 PCL CE'
                path            = $wantPath
                type            = 'stdio'
                allowed_origins = @($wantOrigin)
            }
            # 关键：原生消息清单必须是「无 BOM 的 UTF-8」，否则浏览器解析失败
            $json = $m | ConvertTo-Json -Depth 4
            [System.IO.File]::WriteAllText($manifestPath, $json, (New-Object System.Text.UTF8Encoding($false)))
            Write-Log '已重写原生消息清单'
        }
        # 覆盖 Edge / Chrome 的所有可能位置（含 Edge Beta/Dev/Canary 与 32 位分支）
        $regBases = @(
            'HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\',
            'HKCU:\Software\Microsoft\Edge Beta\NativeMessagingHosts\',
            'HKCU:\Software\Microsoft\Edge Dev\NativeMessagingHosts\',
            'HKCU:\Software\Microsoft\Edge Canary\NativeMessagingHosts\',
            'HKCU:\Software\Google\Chrome\NativeMessagingHosts\',
            'HKCU:\Software\Google\Chrome Beta\NativeMessagingHosts\',
            'HKCU:\Software\Google\Chrome Dev\NativeMessagingHosts\',
            'HKCU:\Software\Chromium\NativeMessagingHosts\',
            'HKCU:\Software\WOW6432Node\Microsoft\Edge\NativeMessagingHosts\',
            'HKCU:\Software\WOW6432Node\Google\Chrome\NativeMessagingHosts\'
        )
        foreach ($base in $regBases) {
            $key = $base + $hostName
            $val = ''
            try { $val = (Get-ItemProperty -Path $key -ErrorAction Stop).'(default)' } catch { }
            if ($val -ne $manifestPath) {
                New-Item -Path $key -Force | Out-Null
                Set-ItemProperty -Path $key -Name '(default)' -Value $manifestPath
                Write-Log ('已重注册原生宿主: ' + $key)
            }
        }
    } catch { Write-Log "自愈注册失败: $_" }
}

function Find-ById($root, [string]$automationId, [int]$timeoutSec = 25) {
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $automationId)
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $el = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
            if ($el) { return $el }
        } catch { }
        Start-Sleep -Milliseconds 400
    }
    return $null
}

function Find-ByName($root, [string]$name, [int]$timeoutSec = 8) {
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name)
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $el = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
            if ($el) { return $el }
        } catch { }
        Start-Sleep -Milliseconds 300
    }
    return $null
}

function Set-ElementText($el, [string]$text) {
    if (-not $el) { return $false }
    try {
        $pat = $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $pat.SetValue($text)
        return $true
    } catch {
        Write-Log "ValuePattern 失败，改用剪贴板: $_"
        try {
            [System.Windows.Forms.Clipboard]::SetText($text)
            $el.SetFocus()
            Start-Sleep -Milliseconds 150
            [System.Windows.Forms.SendKeys]::SendWait('^a')
            [System.Windows.Forms.SendKeys]::SendWait('^v')
            return $true
        } catch { Write-Log "剪贴板方案失败: $_"; return $false }
    }
}

function Invoke-Element($el) {
    if (-not $el) { return $false }
    # 标准按钮优先走 UIA InvokePattern
    try {
        $pat = $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $pat.Invoke()
        return $true
    } catch { }
    # PCL 的 MyButton 只暴露 TextBlock，没有 InvokePattern，退化为鼠标点击矩形中心
    try {
        $r = $el.Current.BoundingRectangle
        if ($r.Width -le 0 -or $r.Height -le 0) { Write-Log '按钮矩形无效'; return $false }
        $cx = [int]($r.X + $r.Width / 2)
        $cy = [int]($r.Y + $r.Height / 2)
        [WinMouse]::Click($cx, $cy)
        Write-Log "鼠标点击 ($cx,$cy)"
        return $true
    } catch { Write-Log "点击失败: $_"; return $false }
}

function Focus-PclWindow($win, [int]$processId) {
    if (-not ([System.Management.Automation.PSTypeName]'WinFocus').Type) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WinFocus {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
}
'@
    }

    $hwnd = [IntPtr]::Zero
    if ($win) { try { $hwnd = [IntPtr]$win.Current.NativeWindowHandle } catch { } }
    if ($hwnd -eq [IntPtr]::Zero -and $processId -gt 0) {
        try { $hwnd = (Get-Process -Id $processId).MainWindowHandle } catch { }
    }

    # ① 先试 PCL 自带的 activate RPC
    if ($processId -gt 0) {
        try {
            $pipeName = 'PCLCE_RPC@' + $processId
            $client = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
            $client.Connect(1500)
            $sw = New-Object System.IO.StreamWriter($client)
            $sw.NewLine = $script:LF
            $sw.AutoFlush = $true
            $sw.Write('REQ activate' + $script:LF + $script:ESC)
            $sr = New-Object System.IO.StreamReader($client)
            $buf = New-Object char[] 512
            $n = $sr.Read($buf, 0, 512)
            $client.Dispose()
            if ($n -gt 0) {
                $resp = (-join $buf[0..($n-1)]).Replace([string][char]27, '').Trim()
                if ($resp -match '^SUCCESS') {
                    Start-Sleep -Milliseconds 350
                    # 关键：它返回 SUCCESS 不代表真的置顶了。
                    # PCL 内置的 activate 只做 Topmost 抖动 + Activate()，
                    # 后台进程调用会被 Windows 拒绝（只闪任务栏图标），所以必须实地验证。
                    if ($hwnd -ne [IntPtr]::Zero -and [WinFocus]::GetForegroundWindow() -eq $hwnd) {
                        Write-Log '已通过 RPC activate 置顶'
                        return $true
                    }
                    Write-Log 'RPC activate 返回成功但未真正置顶，改用 AttachThreadInput 强制置前'
                } else {
                    Write-Log ('RPC activate 不可用（' + $resp + '），改用 AttachThreadInput')
                }
            }
        } catch { Write-Log "RPC activate 失败: $_" }
    }

    # ② 强制置前：AttachThreadInput 技巧（后台进程直接 SetForegroundWindow 会被拒绝）
    if ($hwnd -eq [IntPtr]::Zero) { return $false }
    try {
        [WinFocus]::ShowWindow($hwnd, 9) | Out-Null
        $fg = [WinFocus]::GetForegroundWindow()
        $cur = [WinFocus]::GetCurrentThreadId()
        $fgt = 0
        if ($fg -ne [IntPtr]::Zero) { $fgt = [WinFocus]::GetWindowThreadProcessId($fg, [IntPtr]::Zero) }
        $attached = $false
        if ($fgt -ne 0 -and $fgt -ne $cur) { $attached = [WinFocus]::AttachThreadInput($cur, $fgt, $true) }
        try {
            [WinFocus]::BringWindowToTop($hwnd) | Out-Null
            [WinFocus]::SetForegroundWindow($hwnd) | Out-Null
        } finally {
            if ($attached) { [WinFocus]::AttachThreadInput($cur, $fgt, $false) | Out-Null }
        }
        Start-Sleep -Milliseconds 250
        $ok = ([WinFocus]::GetForegroundWindow() -eq $hwnd)
        Write-Log ('AttachThreadInput 置前结果: ' + $ok)
        return $ok
    } catch { Write-Log "置前失败: $_"; return $false }
}

# 通过自编译版 PCL 的 download RPC 直接填表（毫秒级，不移动鼠标）
# 协议：REQ download + ESC 结尾的 JSON 内容
function Invoke-PclDownloadRpc([int]$processId, [string]$url, [string]$filename, [string]$folder, [string]$ua) {
    $pipeName = 'PCLCE_RPC@' + $processId
    try {
        $payload = @{ url = $url; filename = $filename }
        if ($folder) { $payload.folder = $folder }
        if ($ua) { $payload.userAgent = $ua }
        $json = $payload | ConvertTo-Json -Compress
        $client = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
        $client.Connect(2000)
        $sw = New-Object System.IO.StreamWriter($client)
        $sw.NewLine = $script:LF
        $sw.AutoFlush = $true
        $sw.Write('REQ download' + $script:LF + $json + $script:ESC)
        $sr = New-Object System.IO.StreamReader($client)
        $buf = New-Object char[] 4096
        $n = $sr.Read($buf, 0, 4096)
        $client.Dispose()
        if ($n -le 0) { return @{ ok = $false; error = 'RPC 无响应' } }
        $resp = (-join $buf[0..($n-1)]).Replace([string][char]27, '').Trim()
        # 形如：SUCCESS text 已交给 PCL 下载：xxx.zip
        if ($resp -match '^SUCCESS') {
            $msg = ($resp -split '\s+', 3)[2]
            return @{ ok = $true; message = $msg; via = 'rpc' }
        }
        return @{ ok = $false; error = $resp }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

# 导航到「工具 → 百宝箱」，返回下载地址输入框元素（失败返回 $null）
# PCL 的顶级页签“工具”在 UIA 里只暴露 TextBlock，需要真实鼠标点击；
# 进入工具页后默认停在「大厅」子页，还要再点左侧的「百宝箱」。
function Open-PclToolsPage($win) {
    $urlBox = Find-ById $win 'TextDownloadUrl' 1
    if ($urlBox) { return $urlBox }   # 已在百宝箱，零等待

    $deadline = (Get-Date).AddSeconds(50)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # ① 点顶级页签「工具」
    try {
        $tab = Find-ByName $win '工具' 8
        if ($tab) {
            Invoke-Element $tab | Out-Null
            Write-Log ('点击「工具」用时 ' + $sw.ElapsedMilliseconds + 'ms')
        } else {
            Write-Log '找不到「工具」页签（继续尝试子项）'
        }
    } catch { Write-Log "点击工具页签异常: $_" }

    # ② 等工具页渲染完成后点「百宝箱」，找不到就每 3 秒重试一次（页面很大，渲染可能很慢）
    $clicked = $false
    while ((Get-Date) -lt $deadline) {
        $urlBox = Find-ById $win 'TextDownloadUrl' 1
        if ($urlBox) {
            Write-Log ('导航完成，用时 ' + $sw.ElapsedMilliseconds + 'ms')
            return $urlBox
        }
        $sub = Find-ByName $win '百宝箱' 2
        if ($sub) {
            Invoke-Element $sub | Out-Null
            Write-Log ('点击「百宝箱」用时 ' + $sw.ElapsedMilliseconds + 'ms')
            $clicked = $true
        }
        Start-Sleep -Milliseconds 400
    }

    Write-Log ('导航超时（已点百宝箱=' + $clicked + '），总耗时 ' + $sw.ElapsedMilliseconds + 'ms')
    return (Find-ById $win 'TextDownloadUrl' 1)
}

function Invoke-PclDownload($req) {
    $url      = [string]$req.url
    $filename = if ($req.filename) { [string]$req.filename } else { 'download.bin' }
    $folder   = [string]$req.folder
    $ua       = [string]$req.userAgent
    # 注意：本宿主只负责把信息填进 PCL，绝不点击“开始下载”

    if (-not $url -or $url -notmatch '^(https?|ftp)://') {
        return @{ ok = $false; error = '只支持 http/https/ftp 下载地址：' + $url }
    }

    $proc = Get-RunningPclProcess
    $pclPath = $null
    if (-not $proc) {
        $pclPath = Resolve-PclPath ([string]$req.pclPath)
        if (-not $pclPath) {
            return @{ ok = $false; error = '找不到 PCL CE，请在扩展设置页填写 PCL.exe 的完整路径。' }
        }
        # ── 冷启动：把下载信息作为启动参数带上 ──
        # PCL 在 Application._ApplicationStartup 里解析这些参数，那发生在「主窗口创建之前」，
        # 所以窗口一出现，主页卡片里就已经是填好的 —— 不再有「先弹窗、两秒后才填上」。
        $qUrl  = '"' + ($url -replace '"', '\"') + '"'
        $qName = '"' + ($filename -replace '"', '\"') + '"'
        $argList = @('--download', $qUrl, '--filename', $qName)
        if ($folder) { $argList += @('--folder', ('"' + ($folder -replace '"', '\"') + '"')) }
        Write-Log ("启动 PCL（带下载参数）: $pclPath")
        $wd = Split-Path $pclPath -Parent
        $started = Start-Process -FilePath $pclPath -WorkingDirectory $wd -ArgumentList $argList -PassThru
        Start-Sleep -Milliseconds 1500

        if (-not $started.HasExited) {
            $cfg = Get-BridgeConfig; $cfg.lastUsed = $pclPath; Save-BridgeConfig $cfg
            Write-Log '参数已随启动送入，PCL 会在主页直接预填'
            return @{ ok = $true; via = 'args';
                      message = "已让 PCL 带着链接启动，窗口出现即为填好的状态：$filename" }
        }

        # 带参数启动立刻退出：多半是已有实例（单例检测），退回原来的「等待 + RPC」流程
        Write-Log '带参数启动立刻退出（可能已有实例在跑），改走 RPC 流程'
        $deadline = (Get-Date).AddSeconds(40)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 800
            $proc = Get-RunningPclProcess
            if ($proc) { break }
        }
        if (-not $proc) { return @{ ok = $false; error = 'PCL 启动超时。' } }

        # 冷启动后 UIA 需要时间就绪：轮询等待主窗口 + 导航元素出现（最多 45 秒）
        $ready = (Get-Date).AddSeconds(45)
        while ((Get-Date) -lt $ready) {
            Start-Sleep -Milliseconds 1000
            $w = Get-PclWindow $proc.Id
            if (-not $w) { continue }
            # 出现「工具」页签即视为界面已就绪
            if (Find-ByName $w '工具' 1) { break }
        }
        Start-Sleep -Seconds 2
    }
    if ($pclPath) { $cfg = Get-BridgeConfig; $cfg.lastUsed = $pclPath; Save-BridgeConfig $cfg }

    # ── 优先走自编译版的 download RPC：毫秒级、不碰鼠标 ──
    # 注意：这里「不」给目录兜底。
    # 因为 PCL 自己会用 States.Tool.DownloadFolder 记住用户上次选的位置
    # （PageToolsTest: TextDownloadFolder.Text = States.Tool.DownloadFolder），
    # 若我们塞一个默认目录进去，反而会把用户的选择覆盖掉。
    # RPC 路径不触发下载，所以留空也不会弹模态保存框。
    $rpcResult = Invoke-PclDownloadRpc $proc.Id $url $filename $folder $ua
    if ($rpcResult.ok) {
        Write-Log ("RPC 成功: " + $rpcResult.message)
        # 双保险：PCL 自己也会置顶，这里再试一次（宿主是浏览器的子进程，权限可能更好）
        try {
            $wNow = Get-PclWindow $proc.Id
            if ($wNow) { Focus-PclWindow $wNow $proc.Id | Out-Null }
        } catch { }
        return $rpcResult
    }
    Write-Log ("RPC 不可用，回退 UI 自动化: " + $rpcResult.error)

    # ── 以下是 UI 自动化回退路径 ──
    # 这条路径会走 PCL 的 StartCustomDownload，目录为空会弹模态保存框并阻塞，
    # 所以这里才需要拿一个默认目录兜底。
    if (-not $folder) {
        $folder = Get-PclDefaultFolder
        Write-Log ('回退路径：目录为空，改用 PCL 默认目录: ' + $folder)
    }

    $win = Get-PclWindow $proc.Id
    if (-not $win) { return @{ ok = $false; error = '找不到 PCL 主窗口。' } }
    Focus-PclWindow $win $proc.Id | Out-Null
    Start-Sleep -Milliseconds 300

    # 导航到「工具 → 百宝箱」，然后等下载控件就绪
    $urlBox = Open-PclToolsPage $win
    if (-not $urlBox) {
        return @{ ok = $false; error = '未能在 PCL 中找到“下载自定义文件”控件（导航到 工具→百宝箱 失败），请确认 PCL CE 版本足够新。' }
    }

    if (-not (Set-ElementText $urlBox $url)) {
        return @{ ok = $false; error = '填写下载地址失败。' }
    }
    Start-Sleep -Milliseconds 250
    $uaBox = Find-ById $win 'TextUserAgent' 1
    if ($ua -and $uaBox) { Set-ElementText $uaBox $ua | Out-Null; Start-Sleep -Milliseconds 150 }
    $nameBox = Find-ById $win 'TextDownloadName' 5
    if ($nameBox) { Set-ElementText $nameBox $filename | Out-Null; Start-Sleep -Milliseconds 200 }
    # 保存目录：PCL 要求它必须校验通过，否则「开始下载」按钮永远禁用
    # （PageToolsTest.StartButtonRefresh：三项校验全通过才会启用）
    # 因此没给目录时，用 PCL 自己的默认目录兜底；用户仍可在界面上改。
    $folderBox = Find-ById $win 'TextDownloadFolder' 5
    if ($folderBox) {
        $use = $folder
        if (-not $use) {
            $use = Get-PclDefaultFolder
            Write-Log ('未指定目录，改用 PCL 默认目录: ' + $use)
        }
        $f = $use -replace '/', '\'
        if (-not $f.EndsWith('\')) { $f += '\' }
        Set-ElementText $folderBox $f | Out-Null
        Write-Log ('已填入保存目录: ' + $f)
        Start-Sleep -Milliseconds 200
    }

    # 只填表，绝不点“开始下载”：由用户在 PCL 界面确认后自己点
    Write-Log ("已填好下载信息（未点击开始）: " + $filename)
    return @{ ok = $true; message = '已在 PCL 中填好下载地址和文件名，请确认后点击“开始下载”。' }
}

try {
    while ($true) {
        $raw = Read-Message
        if (-not $raw) { break }
        $req = $null
        try { $req = $raw | ConvertFrom-Json } catch { }
        if (-not $req -or -not $req.action) {
            Write-Message @{ ok = $false; error = '无效请求' }
            continue
        }

        Write-Log ('收到 action=' + $req.action)

        # 每次调用都自愈一次注册状态（幂等且开销极小）
        if ($req.extensionId) { Register-NativeHost ([string]$req.extensionId) }

        switch ($req.action) {
            'ping' {
                $proc = Get-RunningPclProcess
                Write-Message @{
                    ok = $true
                    message = '原生宿主正常'
                    pclRunning = [bool]$proc
                    pclPath = if ($proc) { $proc.Path } else { (Resolve-PclPath '') }
                }
            }
            'getPclPath' {
                $cfg2 = Get-BridgeConfig
                $proc2 = Get-RunningPclProcess
                $running = if ($proc2) { $proc2.Path } else { '' }
                $configured = $cfg2.pclPath
                $exists = $false
                if ($configured) { $exists = Test-Path -LiteralPath $configured }
                $effective = $configured
                if (-not $exists) {
                    $found = Resolve-PclPath ''
                    if ($found) { $effective = $found; $exists = $true }
                }
                Write-Message @{
                    ok = $true
                    path = $effective
                    configured = $configured
                    exists = $exists
                    running = $running
                    pclRunning = [bool]$proc2
                }
            }
            'getDefaultFolder' {
                $f = Get-PclDefaultFolder
                Write-Message @{ ok = $true; folder = $f }
            }
            'pickFolder' {
                $init = [string]$req.initial
                if (-not $init) { $init = Get-PclDefaultFolder }
                $title = [string]$req.title
                if (-not $title) { $title = '选择 PCL CE 的下载保存位置' }
                $picked = Select-Folder $title $init
                if ($picked) {
                    $picked = $picked.TrimEnd([char]92) + [char]92
                    Write-Message @{ ok = $true; folder = $picked }
                } else {
                    Write-Message @{ ok = $true; cancelled = $true }
                }
            }
            'pickPcl' {
                $raw = [string]$req.path

                # 如果给的是文件夹，先在里面找 PCL 可执行文件
                if ($raw -and (Test-Path -LiteralPath $raw -PathType Container)) {
                    $cand = @('PCL.exe', 'Plain Craft Launcher 2.exe', 'PCL2.exe', 'Plain Craft Launcher.exe')
                    foreach ($n in $cand) {
                        $f = Join-Path $raw $n
                        if (Test-Path -LiteralPath $f) { $raw = $f; break }
                    }
                    if (Test-Path -LiteralPath $raw -PathType Container) {
                        $hit = Get-ChildItem -LiteralPath $raw -Filter 'PCL*.exe' -File -ErrorAction SilentlyContinue |
                               Where-Object { $_.Name -notmatch '(?i)uninst|setup|install' } | Select-Object -First 1
                        if (-not $hit) {
                            $hit = Get-ChildItem -LiteralPath $raw -Filter 'Plain Craft Launcher*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
                        }
                        if ($hit) { $raw = $hit.FullName }
                    }
                }

                $p = Resolve-PclPath $raw
                if ($p) {
                    $cfg = Get-BridgeConfig; $cfg.pclPath = $p; Save-BridgeConfig $cfg
                    Write-Message @{ ok = $true; path = $p; message = "已找到并记住 PCL：$p" }
                } else {
                    Write-Message @{ ok = $false; error = '在指定位置没找到 PCL，请确认目录里有 Plain Craft Launcher 2.exe 或 PCL.exe。' }
                }
            }
            'download' {
                try {
                    Write-Log '[步骤1] 进入 download 处理'
                    $reqUrl = [string]$req.url
                    $reqName = [string]$req.filename
                    $reqFolder = [string]$req.folder
                    Write-Log ('[步骤2] url=' + $reqUrl + ' | filename=' + $reqName + ' | folder=' + $reqFolder)
                    $r = Invoke-PclDownload $req
                    Write-Log ('[步骤3] Invoke-PclDownload 返回: ' + ($r | ConvertTo-Json -Compress))
                    Write-Message $r
                    Write-Log '[步骤4] 响应已写出'
                } catch {
                    Write-Log ("[异常] 下载失败: " + $_.Exception.ToString())
                    Write-Message @{ ok = $false; error = [string]$_ }
                }
            }
            default { Write-Message @{ ok = $false; error = ('未知 action: ' + $req.action) } }
        }
    }
} catch {
    Write-Log "致命错误: $_"
} finally {
    Write-Log '宿主退出'
}
