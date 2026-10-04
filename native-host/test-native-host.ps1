# PCL CE 下载接管 —— 原生宿主自测脚本（不依赖浏览器）
# 用法：powershell -ExecutionPolicy Bypass -File test-native-host.ps1 [-Action ping|download] [-Url ...] [-Folder ...]
param(
    [string]$Action = 'ping',
    [string]$Url = 'https://speed.hetzner.de/100MB.bin',
    [string]$Filename = 'test-100MB.bin',
    [string]$Folder = '',
    [string]$PclPath = ''
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$HostScript = Join-Path $ScriptDir 'native-host.ps1'
$Pwsh = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

$payload = [ordered]@{
    action   = $Action
    url      = $Url
    filename = $Filename
    folder   = $Folder
    pclPath  = $PclPath
    autoStart = $true
} | ConvertTo-Json -Compress

$bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
$proc = New-Object System.Diagnostics.Process
$proc.StartInfo.FileName = $Pwsh
$proc.StartInfo.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $HostScript + '"'
$proc.StartInfo.UseShellExecute = $false
$proc.StartInfo.RedirectStandardInput = $true
$proc.StartInfo.RedirectStandardOutput = $true
$proc.StartInfo.RedirectStandardError = $true
$proc.Start() | Out-Null

# 发送 [长度][JSON]
$proc.StandardInput.BaseStream.Write([BitConverter]::GetBytes([int]$bytes.Length), 0, 4)
$proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
$proc.StandardInput.BaseStream.Flush()

# 读响应
$stdout = $proc.StandardOutput.BaseStream
$lenBuf = New-Object byte[] 4
$read = 0
while ($read -lt 4) { $n = $stdout.Read($lenBuf, $read, 4 - $read); if ($n -le 0) { break }; $read += $n }
if ($read -lt 4) {
    Write-Host '宿主没有返回数据。stderr:' -ForegroundColor Red
    Write-Host $proc.StandardError.ReadToEnd()
    $proc.Kill()
    exit 1
}
$len = [BitConverter]::ToInt32($lenBuf, 0)
$buf = New-Object byte[] $len
$read = 0
while ($read -lt $len) { $n = $stdout.Read($buf, $read, $len - $read); if ($n -le 0) { break }; $read += $n }
$json = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)

#$proc.StandardInput.Close()
if (-not $proc.HasExited) { $proc.Kill() }

Write-Host '=== 宿主响应 ===' -ForegroundColor Cyan
Write-Host $json
try { ($json | ConvertFrom-Json) | Format-List } catch { }
