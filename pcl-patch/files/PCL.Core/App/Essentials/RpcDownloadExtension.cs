using System;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading;
using System.Windows.Controls;

namespace PCL.Core.App.Essentials;

/// <summary>
/// 供外部程序（如浏览器扩展）调用的下载 RPC。
///
/// 行为（严格遵守）：
///   1. 只在被调用时把界面切到【主页】（启动页）；已在主页时不做任何切换；
///   2. 只把【下载地址】【文件名】填进主页右侧的下载卡片（给了 folder 才填【保存到】）；
///   3. **绝不点击“开始下载”，绝不发起下载** —— 由用户自己确认后操作；
///   4. 桌面正常启动 PCL 时本代码不参与，主页行为不受影响。
///
/// 主页卡片与「工具 → 百宝箱」共享输入内容（见 PCL.CustomDownloadState），
/// 这里操作真实控件会触发其 TextChanged，同步逻辑自动生效。
///
/// 用法：向命名管道 PCLCE_RPC@PID 发送
///   REQ download
///   {"url":"...","filename":"..."}
/// </summary>
public static class RpcDownloadExtension
{
    private const BindingFlags Inst = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance;
    private const BindingFlags Stat = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static;

    private static MethodInfo? _pageChange;
    private static MethodInfo? _buttonRefresh;

    private static Type? FindType(string fullName)
    {
        foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
        {
            try
            {
                var t = asm.GetType(fullName, false);
                if (t != null) return t;
            }
            catch { }
        }
        return null;
    }

    private static object? StaticField(string typeName, string fieldName)
    {
        var t = FindType(typeName);
        if (t == null) return null;
        try { return t.GetField(fieldName, Stat)?.GetValue(null); } catch { return null; }
    }

    /// <summary>在 UI 线程执行，并把异常带回来。</summary>
    private static void RunOnUi(object frm, Action act)
    {
        var dispatcher = frm.GetType().GetProperty("Dispatcher")?.GetValue(frm);
        if (dispatcher == null) throw new InvalidOperationException("拿不到 Dispatcher");
        var invoke = dispatcher.GetType().GetMethods()
            .FirstOrDefault(m => m.Name == "Invoke"
                                && m.GetParameters().Length == 2
                                && m.GetParameters()[0].ParameterType == typeof(Delegate)
                                && m.GetParameters()[1].ParameterType == typeof(object[]));
        if (invoke == null) throw new InvalidOperationException("找不到 Dispatcher.Invoke(Delegate, object[])");
        invoke.Invoke(dispatcher, new object[] { act, Array.Empty<object>() });
    }

    /// <summary>把界面切到【主页】。已在主页时 PCL 自己会忽略。必须在 UI 线程调用。</summary>
    private static void SwitchToLaunchPage()
    {
        var frmMain = StaticField("PCL.ModMain", "frmMain");
        if (frmMain == null) throw new InvalidOperationException("主窗口尚未创建");

        var pageType = FindType("PCL.FormMain+PageType");
        var subType = FindType("PCL.FormMain+PageSubType");
        var stackType = FindType("PCL.FormMain+PageStackData");
        if (pageType == null || subType == null || stackType == null)
            throw new InvalidOperationException("找不到 FormMain 的页面类型");

        _pageChange ??= frmMain.GetType().GetMethods()
            .FirstOrDefault(m => m.Name == "PageChange" && m.GetParameters().Length == 2);
        if (_pageChange == null) throw new InvalidOperationException("找不到 FormMain.PageChange");

        var launch = Enum.Parse(pageType, "Launch", true);
        var subDefault = Enum.Parse(subType, "Default", true);
        var stack = Activator.CreateInstance(stackType)!;
        var pageField = stackType.GetField("page", Inst);
        if (pageField == null) throw new InvalidOperationException("找不到 PageStackData.page");
        pageField.SetValue(stack, launch);
        _pageChange.Invoke(frmMain, new[] { stack, subDefault });
    }

    /// <summary>填主页下载卡片。必须在 UI 线程调用；返回填了几个字段。</summary>
    private static int FillLaunchCard(string url, string filename, string folder)
    {
        var page = StaticField("PCL.ModMain", "frmLaunchRight");
        if (page == null) throw new InvalidOperationException("主页尚未创建");

        TextBox? Box(string name) => page.GetType().GetField(name, Inst)?.GetValue(page) as TextBox;

        var urlBox = Box("LaunchTextDownloadUrl");
        var nameBox = Box("LaunchTextDownloadName");
        var folderBox = Box("LaunchTextDownloadFolder");
        if (urlBox == null || nameBox == null)
            throw new InvalidOperationException("主页下载卡片尚未创建");

        var filled = 0;
        // 顺序：先地址（会顺带按地址推一个文件名），再文件名覆盖，最后目录
        if (!string.IsNullOrWhiteSpace(url)) { urlBox.Text = url; filled++; }
        if (!string.IsNullOrWhiteSpace(filename)) { nameBox.Text = filename; filled++; }
        // 保存到：只有明确给了才覆盖，否则保留 PCL 自己记住的合法目录
        if (folderBox != null && !string.IsNullOrWhiteSpace(folder))
        {
            var f = folder.Replace('/', '\\');
            if (!f.EndsWith('\\')) f += '\\';
            folderBox.Text = f;
            filled++;
        }

        // 触发校验，让「开始下载」按钮按校验结果启用/禁用
        foreach (var b in new[] { urlBox, nameBox, folderBox })
        {
            if (b == null) continue;
            try { b.GetType().GetMethod("Validate", Inst)?.Invoke(b, null); } catch { }
        }
        _buttonRefresh ??= page.GetType().GetMethod("LaunchDownloadButtonRefresh", Inst);
        try { _buttonRefresh?.Invoke(page, null); } catch { }

        return filled;
    }

    /// <summary>把 PCL 主窗口顶到最前。</summary>
    /// <remarks>
    /// 后台进程直接 SetForegroundWindow 通常会被 Windows 拒绝（只会闪烁任务栏图标），
    /// 所以这里用经典的 AttachThreadInput 技巧：先把本线程输入队列挂到当前前台线程上，
    /// 再 BringWindowToTop + SetForegroundWindow，最后解除挂接。
    /// 必须在 UI 线程调用。
    /// </remarks>
    public static void BringToFront()
    {
        var win = StaticField("PCL.ModMain", "frmMain") as System.Windows.Window;
        if (win == null) return;

        try
        {
            if (win.WindowState == System.Windows.WindowState.Minimized)
                win.WindowState = System.Windows.WindowState.Normal;

            var hwnd = new System.Windows.Interop.WindowInteropHelper(win).Handle;
            if (hwnd == IntPtr.Zero) return;

            var foreground = Native.GetForegroundWindow();
            var currentThread = Native.GetCurrentThreadId();
            var foregroundThread = foreground == IntPtr.Zero
                ? 0u
                : Native.GetWindowThreadProcessId(foreground, IntPtr.Zero);

            var attached = foregroundThread != 0 && foregroundThread != currentThread &&
                           Native.AttachThreadInput(currentThread, foregroundThread, true);
            try
            {
                Native.ShowWindow(hwnd, Native.SwRestore);
                Native.BringWindowToTop(hwnd);
                Native.SetForegroundWindow(hwnd);
            }
            finally
            {
                if (attached) Native.AttachThreadInput(currentThread, foregroundThread, false);
            }

            // 兜底：Topmost 抖动是常用的“强制置前”手法
            var wasTopmost = win.Topmost;
            win.Topmost = true;
            win.Topmost = wasTopmost;
            win.Activate();
        }
        catch { }
    }

    private static class Native
    {
        public const int SwRestore = 9;

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr processId);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

        [System.Runtime.InteropServices.DllImport("kernel32.dll")]
        public static extern uint GetCurrentThreadId();

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool BringWindowToTop(IntPtr hWnd);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    }

    // 注意：不注册 "activate" —— PCL 自带一个同名的（RpcService._FunctionMap），会遮蔽这里。
    // 内置那个只做 Topmost 抖动 + Activate()，后台调用时会被 Windows 拒绝；
    // 真正管用的是上面 BringToFront 里的 AttachThreadInput 技巧。
    // 宿主侧已改为「看 GetForegroundWindow 验证是否真的置顶，不生效再走 Win32 兜底」。

    [RegisterRpc("download")]
    public static RpcResponse OnRpcDownload(string? argument, string? content, bool indent)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(content))
                return RpcResponse.Err("需要 JSON 内容：{\"url\":\"...\",\"filename\":\"...\"}");

            string url, filename, folder;
            try
            {
                using var doc = JsonDocument.Parse(content);
                var root = doc.RootElement;
                url = root.TryGetProperty("url", out var u) ? (u.GetString() ?? "") : "";
                filename = root.TryGetProperty("filename", out var f) ? (f.GetString() ?? "") : "";
                folder = root.TryGetProperty("folder", out var d) ? (d.GetString() ?? "") : "";
            }
            catch (JsonException ex)
            {
                return RpcResponse.Err("JSON 解析失败：" + ex.Message);
            }

            if (string.IsNullOrWhiteSpace(url)) return RpcResponse.Err("url 不能为空");
            if (!url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) &&
                !url.StartsWith("https://", StringComparison.OrdinalIgnoreCase) &&
                !url.StartsWith("ftp://", StringComparison.OrdinalIgnoreCase))
                return RpcResponse.Err("只支持 http/https/ftp 地址");

            // 先写共享状态：即使主窗口/卡片还没创建，卡片稍后创建时也会读到它，
            // 从而做到「窗口一出现就是填好的」。也是冷启动参数的落点。
            CustomDownloadState.Url = url;
            CustomDownloadState.FileName = filename;
            if (!string.IsNullOrWhiteSpace(folder)) CustomDownloadState.Folder = folder;

            var frmMain = StaticField("PCL.ModMain", "frmMain");
            if (frmMain == null)
                return RpcResponse.Success(RpcResponseType.Text,
                    $"已交给 PCL 预填：{filename}（窗口创建后即显示）");

            string? lastError = null;
            for (var i = 0; i < 60; i++)
            {
                try
                {
                    var filled = 0;
                    RunOnUi(frmMain, () =>
                    {
                        SwitchToLaunchPage();
                        filled = FillLaunchCard(url, filename, folder);
                        // 用户点了下载，就把后台的 PCL 顶到最前，让填好的卡片直接可见
                        if (filled >= 2) BringToFront();
                    });
                    if (filled >= 2)
                        return RpcResponse.Success(RpcResponseType.Text,
                            $"已在 PCL 主页填好：{filename}（等待你点击开始下载）");
                    lastError = "只填入了 " + filled + " 个字段";
                }
                catch (Exception ex)
                {
                    lastError = ex.Message;
                }
                Thread.Sleep(250);
            }

            return RpcResponse.Err("填写超时：" + (lastError ?? "未知"));
        }
        catch (Exception ex)
        {
            // 兜底：绝不把异常抛回 PCL 主流程，避免启动器崩溃
            return RpcResponse.Err("download RPC 内部错误：" + ex.Message);
        }
    }
}
