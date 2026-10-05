# PCL CE 浏览器下载接管

> 把浏览器下载交给 [PCL CE](https://github.com/PCL-Community/PCL-CE) 的多线程下载引擎，
> 体验类似 IDM / NDM，但**最终由你点「开始下载」**。

在网页上点下载 → PCL 自动弹出 → **下载地址和文件名已经填好** → 停在原地等你确认。

```
🌐 浏览器                    🖥️ PCL CE
   │ 点下载                     │
   ├──→ 扩展拦截 ──→ 原生宿主 ──→ 唤起/置顶 PCL
   │                              │
   │                    下载地址 ✓
   │                    文件名   ✓
   │                    保存到   ✓
   │                              │
   │                    ⏸ 等你点「开始下载」
   ▼
（浏览器下载已被取消，不会重复下载）
```

**核心原则：只填表，绝不自动下载。** 扩展永远不会替你按下「开始下载」。

---

## 目录

- [30 秒了解它做什么](#30-秒了解它做什么)
- [效果演示](#效果演示)
- [安装教程](#安装教程)（**新手从头看这里**）
  - [第 0 步：先搞清两个前置条件](#第-0-步先搞清两个前置条件)
  - [第 1 步：装浏览器扩展](#第-1-步装浏览器扩展)
  - [第 2 步：装原生宿主](#第-2-步装原生宿主)
  - [第 3 步：准备 PCL CE](#第-3-步准备-pcl-ce)
  - [第 4 步：告诉扩展 PCL 在哪](#第-4-步告诉扩展-pcl-在哪)
  - [第 5 步：验证安装成功](#第-5-步验证安装成功)
- [日常使用](#日常使用)
- [设置项说明](#设置项说明)
- [工作原理](#工作原理)
- [基于哪个版本改写 ★](#基于哪个版本改写-)
- [自己编译 PCL CE](#自己编译-pcl-ce)
- [故障排查](#故障排查)
- [已知限制](#已知限制)
- [开发](#开发)
- [协议与致谢](#协议与致谢)

---

## 30 秒了解它做什么

| | 不用本项目 | 用本项目 |
|---|---|---|
| 点下载后 | 浏览器自己下 | PCL 接管，用它的多线程引擎 |
| 能改文件名 | 改不了（除非用别的工具） | 在 PCL 里随便改 |
| 断点续传 | 取决于浏览器 | PCL 支持 |
| 会不会自动开始 | 会 | **不会，永远等你确认** |

一句话：**下载这件交给 PCL 更省心，但按下开始这一步必须由你来。**

---

## 效果演示

| 冷启动：窗口出现即已填好 | 热启动：主页卡片直接填入 |
|---|---|
| ![冷启动即填好](docs/cold-fill.png) | ![主页卡片](docs/home-card.png) |

| 点开始后自动跳进度页 | 工具栏弹窗：状态一目了然 |
|---|---|
| ![进度页](docs/progress-page.png) | ![弹窗](docs/popup-shot.png) |

---

# 安装教程

> **全程大约 5 分钟。** 只需要照着做，不用理解原理。
>
> 只想快速装的话，压缩包里有 [`docs/安装说明-必读.txt`](docs/安装说明-必读.txt)，
> 打印版式的精简步骤。

## 第 0 步：先搞清两个前置条件

这个项目由**两个部分**组成，缺一不可：

| | 是什么 | 从哪来 |
|---|---|---|
| **① 浏览器扩展** | Edge/Chrome 里的一个扩展 | 本仓库的 `extension/` 目录 |
| **② 修改版 PCL CE** | 带 `download` 功能的 PCL CE | [Releases](../../releases) 下载，或自己编译 |

> **关键**：必须是**修改版** PCL CE。官方原版 PCL CE 没有 `download` 功能，
> 虽然扩展仍能工作，但会退化成很慢的「鼠标自动化」方式（约 11 秒且会抢鼠标）。
> 详见[故障排查](#故障排查)。

**环境要求**

| 项 | 要求 |
|---|---|
| 浏览器 | Edge 或 Chrome，102 及以上 |
| 系统 | Windows 10 1809 及以上 |
| 运行 PCL | .NET 10 Desktop Runtime |
| 编译 PCL（仅自己编译时需要） | .NET 10 SDK |

---

## 第 1 步：装浏览器扩展

1. 打开扩展管理页：
   - Edge → 地址栏输入 **`edge://extensions/`**
   - Chrome → 地址栏输入 **`chrome://extensions/`**
2. 打开左下角的 **「开发人员模式」** 开关
   <br>
   <sub>（Edge 在左下角，Chrome 在右上角）</sub>
3. 点 **「加载解压缩的扩展」**
   （Chrome 可能显示为「加载已解压的扩展程序」）
4. 选择文件夹 —— 二选一：
   - **用 Release 包**：解压 [Releases](../../releases) 里的 `pcl-download-bridge-v0.5.0.zip`，选其中的 `extension` 文件夹
   - **用本仓库源码**：选本仓库的 `extension/` 文件夹
5. 成功后会出现一张卡片，标题是 **「PCL CE 下载接管」**
6. **把鼠标移到卡片上，复制扩展 ID**
   <br>
   <sub>（形如 `abcdefghijklmnopabcdefghijklmnop` 的 32 位字符串，下一步要用）</sub>

<details>
<summary><b>💡 建议：把扩展固定到工具栏</b></summary>

点扩展卡片右下角那排小图标里的**图钉（pushpin）**，固定后就能一键打开状态面板，不用每次去扩展菜单里找。

</details>

---

## 第 2 步：装原生宿主

扩展和 PCL 之间需要一座桥 —— **原生宿主**（Native Messaging Host）。
浏览器出于安全限制，不能直接调用本地程序，必须经过这一层。

**这一步只写当前用户注册表，不需要管理员权限。**

1. **打开 PowerShell**（开始菜单搜 `PowerShell`，直接回车即可，无需管理员）
2. **粘贴下面的命令**并回车 —— 把路径换成你实际存放 `install-native-host.ps1` 的位置：

```powershell
cd "<你解压出来的目录>"
powershell -ExecutionPolicy Bypass -File native-host\install-native-host.ps1
```

> 必须在**含有 `native-host` 子文件夹的那个目录**执行（也就是 `install-native-host.ps1` 的上一级）。
> 不确定的话，在文件资源管理器里打开 `native-host` 文件夹，
> **在地址栏输入 `powershell` 回车** —— 会在正确目录弹出 PowerShell，
> 然后只敲 `.\install-native-host.ps1` 就行。

脚本会自动完成三件事：

```
[1/4] 在浏览器 Secure Preferences 中查找已安装的扩展
[3/4] 写入原生消息清单 cc.pclc.download_bridge.json
[4/4] 在注册表注册到 Edge / Chrome（含 Beta / Dev / Canary）
```

**看到 `OK` / `完成` 就说明成功了。**

<details>
<summary><b>🔧 扩展 ID 被自动识别错了怎么办</b></summary>

手动指定即可：

```powershell
powershell -ExecutionPolicy Bypass -File native-host\install-native-host.ps1 -ExtensionId abcdefghijklmnopabcdefghijklmnop
```

如果你装了多个扩展，或浏览器里有其他以 `nibki...` 开头的扩展，可能识别到错的。
用手动参数最稳。
</details>

<details>
<summary><b>🗑️ 以后要卸载</b></summary>

```powershell
powershell -ExecutionPolicy Bypass -File native-host\install-native-host.ps1 -Uninstall
```

然后在 `edge://extensions/` 点扩展卡片上的「移除」即可。
</details>

---

## 第 3 步：准备 PCL CE

### 方式 A：下载现成的（推荐新手）

1. 前往 [Releases](../../releases) 下载
   `PCL-CE-v2.15.0-unofficial-download-bridge-win-x64.zip`
2. 解压到**一个固定不会被移动的目录**，比如 `D:\Apps\PCL-CE`
3. 双击 `Plain Craft Launcher 2.exe`

> ⚠️ **重要**：这是**框架依赖发布**，整个文件夹是一套东西（约 96 个文件）。
> **不要只复制 exe**，必须整个目录一起保留、一起移动。
> 也不要放在会被清理的临时目录里。

### 方式 B：自己编译（想尝鲜 / 想改代码）

见下方 [自己编译 PCL CE](#自己编译-pcl-ce)。

### 确认你拿到的是修改版

打开 PCL CE，在**扩展的设置页**点「测试原生宿主」，或看 PCL 的窗口标题是否正常显示。
最直接的判断方法在[第 5 步](#第-5-步验证安装成功)。

---

## 第 4 步：告诉扩展 PCL 在哪

1. 点浏览器工具栏上的 **「PCL CE 下载接管」** 图标（就是刚固定的那个）
2. 在 **「PCL CE 路径」** 输入框填入路径，两种填法都支持：
   - 直接填 exe：把 `Plain Craft Launcher 2.exe` **从资源管理器拖进输入框**
   - 或只填文件夹：填 `D:\Apps\PCL-CE`，扩展会自己找里面的 exe
3. 点 **「保存路径」**
4. **下面的状态灯应该变绿**：

```
● 原生宿主正常
● PCL 已找到
```

| 灯 | 含义 | 怎么办 |
|---|---|---|
| 🟢 绿 | 正常 | 可以开始用了 |
| 🔴 红 | 有问题 | 看[故障排查](#故障排查) |

> 💡 **一般不用手动填** —— 留空时扩展会自动探测：正在运行的 PCL → 扩展旁边的 `PCL.exe` → 上次用过的路径。
> 但如果你装了多个 PCL，**手动指定最可靠**。

---

## 第 5 步：验证安装成功

找一个**直接的下载链接**（GitHub Release 的文件、网盘直链等，不要是需要登录的页面）：

1. 在网页上点下载
2. 预期：
   - 浏览器**没有**下载进度条（扩展已接管并取消了浏览器下载）
   - **PCL 弹到最前面**，停在主页
   - 主页右侧「下载自定义文件」卡片里，**地址和文件名已经填好了**
   - 「开始下载」按钮**可点击但没有被点**
3. 扩展图标会短暂显示蓝色 `PCL` 角标（红色 `!` 表示失败）

**成了。** 🎉

完整验收清单：

| # | 检查项 | 怎么验 |
|---|---|---|
| 1 | 扩展已加载 | `edge://extensions/` 里有「PCL CE 下载接管」 |
| 2 | 宿主已注册 | 扩展图标 → 状态灯全绿 |
| 3 | 冷启动可用 | **完全关掉 PCL** → 点下载 → PCL 弹出时已填好 |
| 4 | 热启动可用 | PCL 开着 → 点下载 → 立刻被填好并置顶 |
| 5 | 桌面启动不受影响 | 双击 exe 正常打开 → 停在主页，卡片正常显示 |
| 6 | 不自动下载 | 接管后等 10 秒 → 磁盘上不该出现文件 |

---

# 日常使用

## 基本流程

```
1. 在网页上点「下载」
2. PCL 弹出到前台，停在主页
3. 主页卡片里，地址 / 文件名 / 保存目录 都已填好
4. 想改就改（文件名、目录都能改）
5. 点「开始下载」→ 自动跳到任务管理页看进度
```

## 界面说明

**PCL 侧** —— 主页右侧顶部的「下载自定义文件」卡片：

| 元素 | 说明 |
|---|---|
| 下载地址 | 自动从网页填好，一般不用动 |
| 保存到 | PCL 记住的目录，**会保留你上次的修改** |
| 文件名 | 自动从 URL 推断，可以随便改 |
| 开始下载 | **由你点**，扩展永不代劳 |
| 打开文件夹 | 打开保存目录 |

**扩展侧** —— 点工具栏图标：

| 区域 | 内容 |
|---|---|
| 状态 | 两个状态灯：宿主 / PCL，一眼看出哪一环断了 |
| PCL CE 路径 | 手动指定 + 「选择…」+「自动探测」 |
| 接管开关 | 启用接管 / 用浏览器原定目录 |

## 常见用法

**改文件名或目录**
直接在 PCL 卡片里改 → 点开始。改过的目录 PCL 会记住，下次接管时依然是它。

**只想用浏览器下这个文件**
扩展弹窗里设的「用浏览器下载」兜底按钮，或临时关掉「启用下载接管」。

**不想要任何弹窗/接管**
设置页关掉「启用下载接管」，浏览器立刻恢复正常下载。

---

# 设置项说明

点扩展图标 → 右下角 **「更多设置」** 进入完整设置页。

| 设置项 | 默认 | 在哪 | 说明 |
|---|---|---|---|
| **启用下载接管** | ✅ 开 | 弹窗 / 设置页 | 关掉后所有下载交回浏览器 |
| **静默接管** | ✅ 开 | **仅设置页** | 开 = 不弹确认窗，直接唤起 PCL；关 = 每次弹确认窗让你先看一眼 |
| **优先使用浏览器原定保存目录** | ✅ 开 | 弹窗 / 设置页 | 关 = 始终用 PCL 记住的目录 |
| **PCL CE 路径** | 空（自动探测） | 弹窗 / 设置页 | 填 exe 或文件夹都行 |

> **保存目录的记忆由 PCL 自己负责**（`States.Tool.DownloadFolder`）。
> 本项目**不会**用默认目录覆盖你在 PCL 里改过的位置。

**宿主与日志位置**

| 项 | 路径 |
|---|---|
| 宿主配置 | `%LOCALAPPDATA%\PCLDownloadBridge\config.json` |
| 宿主日志 | `%LOCALAPPDATA%\PCLDownloadBridge\bridge.log` |

---

# 工作原理

```
网页点下载
   │
   ↓ ① MV3 扩展 chrome.downloads.onDeterminingFilename 拦截
   │    cancel() 取消浏览器下载，拿到 URL 与文件名
   ↓
   ↓ ② Native Messaging（stdio 协议）交给本机宿主
   ↓
   ↓ ③ 宿主判断 PCL 是否在运行
   │
   ├─ 【没在运行】冷启动 ─ 命令行参数
   │    PCL2.exe --download "<url>" --filename "<name>" [--folder "<dir>"]
   │    PCL 在主窗口创建之前就解析完参数
   │    → 窗口一出现，字段已经是填好的（实测 3.3 秒）
   │
   └─ 【已在运行】热启动 ─ 命名管道 RPC
        管道名：\\.\pipe\PCLCE_RPC@<PID>
        REQ download {"url":"...","filename":"...","folder":"..."}
        → 填入主页卡片 + 把窗口置顶（实测 0.07 秒）
   ↓
停在填好的界面，等你点「开始下载」
```

## 三个关键机制

**1. 命名管道 RPC**

PCL CE v2.15.0 自带 RPC 服务。本项目注册了一个 `download` 函数：

```csharp
[RegisterRpc("download")]
public static RpcResponse OnRpcDownload(string? argument, string? content, bool indent)
```

它会：切到主页 → 填输入框 → 校验 → 置顶窗口。
**注意它只填表，不调用 `StartCustomDownload()`** —— 因为那个方法的语义是「立即开始下载」。

**2. 启动参数（冷启动的关键）**

PCL 在 `Application._ApplicationStartup()` 里解析命令行参数，
而这段代码运行在**主窗口创建之前**。补丁在这里解析 `--download` 系列参数并写入共享状态，
因此主页卡片一被创建就是填好的 —— 没有「窗口先空着、然后再填」的割裂感。

**3. 窗口置顶**

后台进程直接调 `SetForegroundWindow` 会被 Windows 拒绝（只会闪任务栏图标）。
所以用 `AttachThreadInput` 技巧：先把本线程输入队列挂到当前前台线程 → 置顶 → 解除挂接。

> 为什么不用 PCL 自带的 `activate` RPC？因为它只做 `Topmost` 抖动，
> 后台调用**顶不上来却返回 `SUCCESS`** —— 这是 PCL 的一个真实缺陷，见 `pcl-patch/README.md`。

---

# 基于哪个版本改写 ★

本项目的 **PCL CE 侧改动**（`pcl-patch/`）基于以下确切版本：

| 项 | 值 |
|---|---|
| 上游仓库 | https://github.com/PCL-Community/PCL-CE |
| 版本标签 | **`v2.15.0`** |
| 提交 SHA | **`12bb0ea2517de810c4d6da3daf63239c8a9d9bdf`** |
| 源码包 | https://codeload.github.com/PCL-Community/PCL-CE/zip/refs/tags/v2.15.0 |
| 目标框架 | `net10.0-windows`（需 .NET 10 SDK 编译） |
| 协议 | Apache License 2.0 |

> ⚠️ **为什么必须写明版本**：`v2.15.0` 是 PCL CE 完成 C# 重写的版本，
> RPC 基础设施（`RpcService` / `RegisterRpc`）与「百宝箱」都依赖它。
> **更早的版本（如 v2.14.x）没有可用的 RPC 服务**，本补丁无法工作。

## 改动清单（共 6 个文件：新增 2、修改 4、删除 0）

| # | 文件 | 类型 | 作用 |
|---|---|---|---|
| 1 | `PCL.Core/App/CustomDownloadState.cs` | 新增 | 主页/百宝箱/RPC/启动参数共享的输入内容 |
| 2 | `PCL.Core/App/Essentials/RpcDownloadExtension.cs` | 新增 | `download` RPC：切主页、填表、置顶 |
| 3 | `Plain Craft Launcher 2/Application.xaml.cs` | 修改 | 解析 `--download` 等启动参数 |
| 4 | `Plain Craft Launcher 2/Pages/PageLaunch/PageLaunchRight.xaml` | 修改 | 主页右侧新增下载卡片 |
| 5 | `Plain Craft Launcher 2/Pages/PageLaunch/PageLaunchRight.xaml.cs` | 修改 | 卡片逻辑、输入同步、置顶 |
| 6 | `Plain Craft Launcher 2/Pages/PageTools/PageToolsTest.xaml.cs` | 修改 | 与主页双向同步 |

合计 **+640 行 / -3 行**，完整差异见 [`pcl-patch/pcl-download-rpc.patch`](pcl-patch/pcl-download-rpc.patch)。

---

# 自己编译 PCL CE

<details>
<summary><b>需要 .NET 10 SDK · 约 10 分钟 · 点击展开</b></summary>

### 1. 装 .NET 10 SDK

下载安装：https://dotnet.microsoft.com/download/dotnet/10.0

### 2. 取得对应版本源码

```bash
# 方式一：直接下载源码包（推荐，版本绝对准确）
curl -L -o pcl-ce.zip https://codeload.github.com/PCL-Community/PCL-CE/zip/refs/tags/v2.15.0
unzip pcl-ce.zip && cd PCL-CE-2.15.0

# 方式二：git clone 后切标签
git clone https://github.com/PCL-Community/PCL-CE.git
cd PCL-CE && git checkout v2.15.0
```

### 3. 应用补丁

```bash
# 用补丁
git apply /path/to/pcl-patch/pcl-download-rpc.patch

# 或者直接拷贝已改好的文件
cp -r /path/to/pcl-patch/files/* ./
```

### 4. 编译

```bash
dotnet build "Plain Craft Launcher 2/Plain Craft Launcher 2.csproj" -c Release -p:Platform=x64
```

产物在：

```
Plain Craft Launcher 2/bin/Release/net10.0-windows/win-x64/
```

### 5. 部署（重要）

**整个输出目录**复制到你的目标位置，**不能只复制 exe**（框架依赖发布）。
然后在扩展里把 PCL 路径指向它。

> **关于构建密钥**：官方 CI 会注入 `LINK_SERVER_ROOT`、CurseForge 等密钥。
> 自己编译时这些是空的，因此**联机/大厅、CurseForge 下载等功能不可用**（详见[已知限制](#已知限制)）。
> 这不影响下载接管本身。

</details>

---

# 故障排查

## 先看这个：90% 的问题看状态灯

点扩展图标，**先看两个灯**：

| 灯的状态 | 诊断 | 跳转 |
|---|---|---|
| 🟢 宿主 + 🟢 PCL | 装好了，问题在别处 | 往下翻 |
| 🟢 宿主 + 🔴 PCL | **PCL 路径不对** | [下方第 1 条](#1-报找不到-pcl-ce-或-pcl-状态灯是红的) |
| 🔴 宿主 | **宿主没装或没注册** | [下方第 2 条](#2-报-access-to-the-specified-native-messaging-host-is-forbidden) |

再看日志：`%LOCALAPPDATA%\PCLDownloadBridge\bridge.log`
里面有分步记录（收到请求 → 定位 PCL → 启动/RPC → 响应），能直接看出卡在哪一步。

---

### 1. 报「找不到 PCL CE」或 PCL 状态灯是红的

**原因**：扩展没找到带 `download` 功能的 PCL。

**解决**：
- 点扩展图标 → 「PCL CE 路径」填正确路径 → 「保存路径」
- 填**文件夹**也可以，会自动在里面找 `PCL.exe` / `Plain Craft Launcher 2.exe` / `PCL2.exe`
- **确认你填的是修改版 PCL**，官方原版没有 `download` 功能

<details>
<summary><b>机器上有多个 PCL 怎么办</b></summary>

PCL 装多个很容易搞混。逐个确认哪个是修改版：

| 路径 | 大小 | 判断 |
|---|---|---|
| `...\pcl-custom\Plain Craft Launcher 2.exe` | ~350 KB | ✅ 修改版（框架依赖发布） |
| `...\PCL2_CE_Release_v2.15.0_x64.exe` | ~21 MB | ❌ 官方原版（单文件） |
| 其它 | — | 看 FileVersion 是否为本项目构建 |

**大小能一眼区分**：修改版是**框架依赖发布**，exe 只有 350 KB 左右；
官方是**单文件发布**，exe 有 21 MB。

> 本项目在早期版本中就因为自动探测抓到 `E:\pcl\` 下的旧版 PCL2（v2.13.1.1，没有百宝箱页面）
> 而失败过。现在搜索规则已排除旧命名，但仍建议**手动指定路径**。
</details>

---

### 2. 报 `Access to the specified native messaging host is forbidden`

**原因**：扩展 ID 与宿主清单里的 `allowed_origins` 不匹配，或清单文件本身有问题。

**解决**：重跑安装脚本，它会重新读取扩展 ID：

```powershell
powershell -ExecutionPolicy Bypass -File native-host\install-native-host.ps1
```

如果手动改过清单，注意两个**硬性约束**（踩过很多次）：

| 约束 | 正确做法 | 错误后果 |
|---|---|---|
| **清单必须无 BOM** | `UTF8Encoding($false)` | 带 BOM（`EF BB BF`）→ 浏览器 JSON 解析失败 |
| **`path` 必须指向可执行文件** | 指向 `native-host.cmd` | 指向 `.ps1` → Chromium 直接 `CreateProcess` 不解析参数，必然失败 |

---

### 3. 改了扩展代码但没生效

**原因**：浏览器还在跑旧的 Service Worker。

**解决**：`edge://extensions/` → 找到「PCL CE 下载接管」→ 点卡片上的 **🔄 重新加载**。

> ⚠️ **这是本项目最容易踩的坑。** 改了 `extension/` 里的代码但没点重载，
> 浏览器加载的仍是旧副本，会让人以为「代码改了没用」。

---

### 4. PCL 弹出来了，但字段是空的

**原因**：用的是**官方版 PCL**（没有 `download` RPC）。

**判断**：看日志里有没有

```
RPC 不可用，回退 UI 自动化
```

**解决**：换用[修改版 PCL CE](#第-3-步准备-pcl-ce)。

---

### 5. 点下载完全没反应，图标显示红色 `!`

**排查顺序**：

1. 打开 `%LOCALAPPDATA%\PCLDownloadBridge\bridge.log`，看最后几行
2. 常见两种：
   - 停在「正在查找 PCL」→ [问题 1](#1-报找不到-pcl-ce-或-pcl-状态灯是红的)
   - 根本没收到请求 → 宿主没装好，[问题 2](#2-报-access-to-the-specified-native-messaging-host-is-forbidden)
3. 扩展设置页按 **F12** 打开控制台，点「测试原生宿主」，
   看 `chrome.runtime.lastError` 的具体内容（会告诉你是 ID 不匹配还是进程启动失败）

---

### 6. 出现 `[Link] Failed to get announcement` 两条报错

**与下载接管无关**，是 PCL「联机 → 大厅」拉公告失败。

**原因**：PCL 的联机服务器地址来自构建时注入的密钥 `LINK_SERVER_ROOT`。
自编译版不带该密钥时，`"".Split("|")` 得到 `[""]`（长度为 1 的假列表），
于是去请求相对路径 `/api/link/v2/cache.ini`，必然失败 —— 报错信息因此具有误导性。

**本项目的补丁已绕过它**（接管时预设 `isPageSwitched` 跳过自动勾选「大厅」）。
如果你仍看到，说明用的是官方版 PCL。**自编译版的联机功能本来不可用**，需要联机请用官方版。

---

### 7. 下载完成后不知道文件在哪

看 PCL 卡片上的「保存到」，或点「打开文件夹」。
该位置由 PCL 记忆，你改过之后不会被本项目覆盖。

---

### 8. 冷启动太慢 / PCL 启动要等很久

PCL 自身启动约需 **10 秒**（加载 WPF、字体、配置、网络检查），
**从外部无法加速**。实测冷启动 3.3 秒即完成填表，其中包括这段启动时间。

若想更快，可以让 PCL 常驻后台（不最小化），热启动实测 **0.07 秒**。

---

# 已知限制

| # | 限制 | 说明 |
|---|---|---|
| 1 | **非官方版本** | 未获 PCL Community 官方背书。问题请反馈到本项目，不要打扰 PCL 官方 |
| 2 | **修改版不自动更新** | 官方发布新版后，需重新套用补丁编译 |
| 3 | **缺官方构建密钥** | 联机/大厅、CurseForge 下载、MirrorChyan CDK、遥测不可用（不影响下载接管） |
| 4 | **仅支持 Windows** | 宿主依赖注册表 / PowerShell / 命名管道（PCL CE 本身也只支持 Windows） |
| 5 | **带登录 Cookie 的网盘会失败** | PCL 用自己的身份请求，不带浏览器 Cookie（百度网盘等还会被 PCL 自身按 403 拦截） |
| 6 | **不接管网页内嵌视频流** | 只接管「下载行为」，不处理网页播放器里的流 |
| 7 | **PCL 单例限制** | 已有 PCL 实例运行时，命令行启动的自编译版会立即退出，此时自动退回热启动路径 |

---

# 开发

```powershell
# 宿主自测（不经过浏览器，直接喂 native messaging 帧）
powershell -ExecutionPolicy Bypass -File native-host\test-native-host.ps1
```

宿主支持的 action：`ping` / `download` / `getPclPath` / `getDefaultFolder` / `pickPcl` / `pickFolder`

**编码要求（踩过坑，务必遵守）**

| 文件 | 编码 |
|---|---|
| `native-host.ps1` / `install-native-host.ps1` / `test-native-host.ps1` | **UTF-8 with BOM**（否则 PowerShell 5.1 按 GBK 解析中文会乱码） |
| `native-host.cmd` | **纯 ASCII 无 BOM** |
| 原生消息清单 `cc.pclc.download_bridge.json` | **无 BOM 的 UTF-8** |

**PowerShell 5.1 转义注意**

反斜杠在单引号里不会被转义，但 `TrimEnd('\')` 会被解析器当成转义序列而报语法错误。
正确写法：

```powershell
$fallback.TrimEnd([char]92) + [char]92   # ✅
$fallback.TrimEnd('\')                   # ❌ 26 个语法错误
```

---

# 协议与致谢

- 本项目采用 [Apache License 2.0](LICENSE) 授权
- 其中 PCL CE 侧的改动是 [PCL CE](https://github.com/PCL-Community/PCL-CE) 的衍生作品，
  同样采用 Apache License 2.0；来源、版本与修改内容见 [NOTICE](NOTICE)
- 感谢 [PCL Community](https://github.com/PCL-Community) 与 PCL CE 的各位贡献者
- 特别致谢 PCL CE 已有的 RPC 基础设施（`RpcService`），本项目的 `download` 函数正是基于它注册

## 反馈

欢迎提 Issue 与 PR。

`pcl-patch/` 里的改动是**独立、低侵入**的（新增 2 文件、修改 4 文件，+640/-3 行，
主窗口行为不受影响），适合直接合入上游 —— 如果能合并，官方版用户就能直接享受这个功能，
不必再维护自编译版。`pcl-patch/README.md` 里还记录了开发过程中发现的
**4 个上游机制问题**（其中 2 个修好会让这个功能更实用）。
