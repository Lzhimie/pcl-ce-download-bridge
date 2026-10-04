# PCL CE 侧改动说明

本目录是给 [PCL CE](https://github.com/PCL-Community/PCL-CE) 的补丁，让它支持浏览器扩展的下载接管。

## 基线版本 ★

| 项 | 值 |
|---|---|
| 仓库 | https://github.com/PCL-Community/PCL-CE |
| 标签 | **`v2.15.0`** |
| 提交 | **`12bb0ea2517de810c4d6da3daf63239c8a9d9bdf`** |
| 源码包 | https://codeload.github.com/PCL-Community/PCL-CE/zip/refs/tags/v2.15.0 |
| 目标框架 | `net10.0-windows` |

> **为什么必须 v2.15.0 及以上**：
>
> - RPC 基础设施（`RpcService`、`[RegisterRpc]`、`PCLCE_RPC@<PID>` 命名管道）在 v2.15.0 才可用
> - 「百宝箱」的自定义下载卡片与 `PageSubType.ToolsTest` 在 v2.15.0 才存在
>
> 实测：**v2.14.x 及更早版本连 RPC 管道都不会创建**，补丁无法工作。

## 文件

| 文件 | 用途 |
|---|---|
| `pcl-download-rpc.patch` | 针对上述提交的 unified diff，用 `git apply` 应用 |
| `files/` | 已改好的 6 个文件，可直接覆盖到源码树 |

## 应用方式

### 方式一：打补丁（推荐）

```bash
curl -L -o pcl-ce.zip https://codeload.github.com/PCL-Community/PCL-CE/zip/refs/tags/v2.15.0
unzip pcl-ce.zip
cd PCL-CE-2.15.0
git init && git add -A && git commit -m baseline   # 便于 git apply 与回滚
git apply /path/to/pcl-download-rpc.patch
```

### 方式二：直接覆盖文件

把 `files/` 下的 6 个文件按相同相对路径覆盖到源码树（其中 2 个是新增文件）。

> **关于行尾符**：补丁本身是 LF。
> 上游 `.gitattributes` 含有 `* text=auto`，因此在 Windows 上 `git apply` 写出的文件会是 CRLF（本机习惯），
> 属正常现象，**代码内容完全相同**，不影响编译。
> 若你的环境提示不匹配，可加 `--ignore-whitespace`：
>
> ```bash
> git apply --ignore-whitespace pcl-download-rpc.patch
> ```

## 编译

需要 **.NET 10 SDK**（仅运行时不够）：

```bash
dotnet build "Plain Craft Launcher 2/Plain Craft Launcher 2.csproj" -c Release -p:Platform=x64
```

产物在 `Plain Craft Launcher 2/bin/Release/net10.0-windows/win-x64/`。

> 这是**框架依赖发布**，`Plain Craft Launcher 2.exe` 只有约 350 KB，
> 必须与同目录的 `PCL.Core.dll`、`Plain Craft Launcher 2.dll` 等一起保留，不能单独复制 exe。

## 改动清单

共 **6 个文件：新增 2、修改 4、删除 0**，合计 **+640 / -3** 行。

### 新增

#### 1. `PCL.Core/App/CustomDownloadState.cs`

「下载自定义文件」的共享输入内容（地址 / 文件名 / 目录），只存内存。

放在 `PCL.Core` 是为了让三方都能**直接访问、无需反射**：

| 使用方 | 场景 |
|---|---|
| `Application` 的启动参数解析 | PCL 冷启动 |
| `RpcDownloadExtension` 的 `download` RPC | PCL 已在运行 |
| 主页卡片 / 百宝箱卡片 | UI 读与写 |

#### 2. `PCL.Core/App/Essentials/RpcDownloadExtension.cs`

注册 `download` RPC：

```csharp
[RegisterRpc("download")]
public static RpcResponse OnRpcDownload(string? argument, string? content, bool indent)
```

它做四件事，**仅此四件**：

1. 解析 `{"url":...,"filename":...,"folder":...}`
2. 写入 `CustomDownloadState`（即使窗口还没创建，卡片稍后也会读到）
3. 切到主页（已在主页则无操作），填入卡片三个输入框，触发校验
4. 用 `AttachThreadInput` 技巧把窗口置顶

**绝不点击「开始下载」，绝不发起下载。**

### 修改

#### 3. `Plain Craft Launcher 2/Application.xaml.cs`（+36）

新增 `ApplyDownloadStartupArguments()`，解析 `--download / --filename / --folder`。

**这是冷启动能做到「窗口出现即填好」的关键**：该方法运行在**主窗口创建之前**，
所以主页卡片一被创建，读到的就已经是填好的状态。

#### 4. `Plain Craft Launcher 2/Pages/PageLaunch/PageLaunchRight.xaml`（+84）

在主页右侧 `PanMain` 最顶部插入一张 `MyCard`「下载自定义文件」，
含地址 / 保存到 / 文件名三个输入框与「开始下载」「打开文件夹」两个按钮，
复用百宝箱同款校验器（`HttpAndUncValidator` / `FolderPathValidator` / `FileNameValidator`）。

#### 5. `Plain Craft Launcher 2/Pages/PageLaunch/PageLaunchRight.xaml.cs`（+163）

卡片逻辑：输入变化写回共享状态、`PageEnter` 时从共享状态读回、按钮可用性刷新、
选目录、打开目录、开始下载（调 `PageToolsTest.StartCustomDownload`，并跳转 `PageType.TaskManager` 看进度）。

#### 6. `Plain Craft Launcher 2/Pages/PageTools/PageToolsTest.xaml.cs`（+44）

只加同步：`TextChanged` 写回共享状态，`PageEnter` 读回。**原有 XAML 与业务逻辑一行未改。**

## 设计中踩过的坑（供评审参考）

这些是 PCL 现有机制的真实行为，本项目据此做了适配：

### 坑 1：`FormMain` 的 `Tools` 分支会丢弃子页参数

```csharp
// FormMain.xaml.cs（上游）
case PageType.Tools:
    ModMain.frmToolsLeft ??= new PageToolsLeft();
    subType = ModMain.frmToolsLeft.pageID;   // ← 无条件覆盖传入的 subType
    PageChangeAnim(ModMain.frmToolsLeft, ModMain.frmToolsLeft.PageGet(subType));
```

对比 `Download` 分支是「传入非 Default 才覆盖」，`Tools` 分支则直接丢弃。
所以**无法通过 `PageChange(PageType.Tools, PageSubType.ToolsTest)` 直接跳到百宝箱**。
本项目改为先设置 `frmToolsLeft.pageID` 再切页。

### 坑 2：`PageToolsLeft` 首次加载会强勾「大厅」并连带拉联机公告

```csharp
// PageToolsLeft.xaml.cs  PageLinkLeft_Loaded（上游）
if (isPageSwitched) return;
if (!hideCfg.ToolsGameLink) ItemGameLink.SetChecked(true, false, false);
```

大厅页一被创建就会去拉公告。若构建时没有注入 `LINK_SERVER_ROOT`，就会弹两条网络报错。
本项目通过预先置位 `isPageSwitched` 跳过该自动勾选。

### 坑 3：`MyPageRight.Loaded` 只触发一次，`PageEnter` 才每次都触发

页面实例会被 PCL 缓存，所以用 `Loaded` 做「进入页面时同步」是不可行的，必须用 `PageEnter` 事件。

### 坑 4：内置 `activate` RPC 顶不上来，却返回 `SUCCESS`

`RpcService._FunctionMap` 里已有 `activate`，实现是：

```csharp
if (!window.Topmost) { window.Topmost = true; window.Topmost = false; }
window.Activate();
```

后台进程调 `Activate()` 会被 Windows 拒绝，**返回值却是 `SUCCESS`**。
本项目不重复注册 `activate`（会被遮蔽），改用 `AttachThreadInput` 强制置前。

## 建议上游考虑的三点

如果这些机制能得到改进，本项目就不必维护自编译版了：

1. **`Tools` 分支尊重传入的 `subType`**（与 `Download` 分支一致）—— 让外部工具能直接跳到指定子页
2. **`activate` RPC 使用 `AttachThreadInput`** —— 目前它在后台调用时实际无效
3. **缺密钥时的联机报错更明确** —— 目前 `"".Split("|")` 会产生 `[""]`，报错信息具有误导性

## 许可

本目录内容是对 PCL CE 的修改，遵循上游的 **Apache License 2.0**。
来源、版本与修改声明见仓库根目录的 [NOTICE](../NOTICE)。
