namespace PCL.Core.App;

/// <summary>
///     「下载自定义文件」的共享输入内容，被主页右侧卡片与「工具 → 百宝箱」共用，
///     同时也是「浏览器接管」把链接送进 PCL 的落点。
///
///     放在 PCL.Core 是为了让三方都能直接访问，无需反射：
///       · PCL.Core 里的 download RPC（PCL 已在运行时）
///       · 启动参数解析（PCL 冷启动时，见 Application.ApplyDownloadStartupArguments）
///       · 两个 UI 卡片
///
///     刻意只存内存不持久化，避免下次启动残留旧链接；
///     保存目录的持久化由 States.Tool.DownloadFolder 负责。
/// </summary>
public static class CustomDownloadState
{
    /// <summary>下载地址。</summary>
    public static string Url { get; set; } = "";

    /// <summary>文件名。</summary>
    public static string FileName { get; set; } = "";

    /// <summary>保存目录；为空表示由页面按 PCL 记住的位置填充。</summary>
    public static string Folder { get; set; } = "";

    /// <summary>下载启动后清空地址与文件名（与百宝箱原行为一致）。</summary>
    public static void ClearRequest()
    {
        Url = "";
        FileName = "";
    }
}
