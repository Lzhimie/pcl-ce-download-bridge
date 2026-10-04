# PCL CE 浏览器下载接管 v0.5.0

像 IDM / NDM 那样接管浏览器下载，把文件交给 [PCL CE](https://github.com/PCL-Community/PCL-CE) 的多线程下载引擎。

**网页点下载 → 自动唤起 PCL → 窗口出现时链接和文件名已经填好 → 停在主页等你点「开始下载」。**

> 本扩展只填表，**绝不自动开始下载**，始终由你确认。

## 下载

| 文件 | 大小 | 说明 |
|---|---|---|
| `pcl-download-bridge-v0.5.0.zip` | 63.2 KB | 浏览器扩展 + 原生消息宿主 |
| `PCL-CE-v2.15.0-unofficial-download-bridge-win-x64.zip` | 9.94 MB | PCL CE v2.15.0 的非官方修改版 |

**校验值（SHA256）**

```
B8D032A84E67184AE3D83CF46FB0150CD249B86BBF36CD02DD2B1739901AE066  pcl-download-bridge-v0.5.0.zip
7F1CCD3A97D4F4C0BE5CE265DDA1F0D3453A58BF8B367B935E1F0A6B8326EE4B  PCL-CE-v2.15.0-unofficial-download-bridge-win-x64.zip
```

## 安装

1. **扩展** —— 解压 `pcl-download-bridge-v0.5.0.zip`，打开 `edge://extensions/`，开启「开发人员模式」，点「加载解压缩的扩展」，选 `extension` 文件夹
2. **原生宿主** —— 在解压目录执行：

   ```powershell
   powershell -ExecutionPolicy Bypass -File native-host\install-native-host.ps1
   ```

3. **PCL 修改版** —— 解压 `PCL-CE-v2.15.0-unofficial-download-bridge-win-x64.zip` 到任意目录，双击 `Plain Craft Launcher 2.exe`
   （依赖 .NET 10 Desktop Runtime；必须整个目录一起保留，不能只复制 exe）
4. **指定路径** —— 点扩展图标，填入 `Plain Craft Launcher 2.exe` 的路径，保存

详细步骤见压缩包内的 `安装说明-必读.txt` 与 `重要说明-必读.txt`。

## 本版特性

| 特性 | 说明 |
|---|---|
| 🚀 冷启动即填好 | PCL 没开时用启动参数把链接带进去，窗口出现即为填好（实测 3.3 秒） |
| ⚡ 热启动毫秒级 | PCL 已开时经命名管道 RPC 填入，实测 0.07 秒 |
| 🪟 自动置顶 | 不管 PCL 在后台还是最小化，点下载都会恢复并跳到最前 |
| 🏠 主页就有卡片 | 右侧顶部直接可填，不必进「工具 → 百宝箱」 |
| 🔁 两处双向同步 | 主页与百宝箱的输入内容互相同步 |
| 📊 一键看进度 | 点「开始下载」自动跳「任务管理」页看进度与速度 |
| ✋ 绝不自动下载 | 只填表，开始与否始终由你决定 |
| 🖱️ 不碰鼠标 | 走 RPC 通信，不模拟点击、不抢焦点 |

## PCL 侧基于哪个版本改写

| 项 | 值 |
|---|---|
| 上游仓库 | https://github.com/PCL-Community/PCL-CE |
| 版本标签 | **v2.15.0** |
| 提交 SHA | **12bb0ea2517de810c4d6da3daf63239c8a9d9bdf** |
| 协议 | Apache License 2.0 |

改动共 **6 个文件（新增 2、修改 4），+640 / -3 行**，完整补丁见仓库的 `pcl-patch/` 目录。

## ⚠️ 已知限制

1. **这不是 PCL 官方发布版**，未获 PCL Community 官方背书。问题请反馈到本项目，不要打扰 PCL 官方
2. **PCL 修改版不会自动更新**，官方发布新版后需重新套用补丁编译
3. **缺少官方构建密钥**，以下功能可能不可用：
   - 联机 / 大厅（会提示 `[Link] Failed to get announcement`）
   - CurseForge 下载
   - MirrorChyan CDK
4. **仅支持 Windows**（PCL CE 本身也只支持 Windows）
5. 使用**官方版 PCL** 时扩展仍可用，但会退回较慢的 UI 自动化方式（约 11 秒，且会短暂占用鼠标）

## 许可

Apache License 2.0。PCL 侧改动是 PCL CE 的衍生作品，来源与修改声明见 `NOTICE`。
