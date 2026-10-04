# 参与贡献

欢迎 Issue 与 PR。

## 提交前请确认

| 文件类型 | 编码要求 | 原因 |
|---|---|---|
| `native-host/*.ps1` | **UTF-8 with BOM** | 否则 PowerShell 5.1 会按 GBK 解析，中文注释变成语法错误 |
| `native-host/native-host.cmd` | **纯 ASCII，无 BOM** | 作为原生消息宿主入口，必须是最干净的可执行脚本 |
| 原生消息清单 `*.json` | **UTF-8 无 BOM** | 带 BOM 会导致浏览器拒绝加载宿主 |
| 扩展 JS/HTML/CSS | UTF-8 | — |

## 不要提交

- `native-host/cc.pclc.download_bridge.json`（安装脚本生成，含本机绝对路径与扩展 ID，已在 .gitignore 中）
- 任何本机绝对路径、个人扩展 ID、日志文件
- PCL CE 的完整源码或编译产物（请只提交补丁与改动文件）

## 改动 PCL CE 源码时

1. 先从**确切的上游提交**（当前为 `v2.15.0` / `12bb0ea2`）重新导出干净源码
2. 改动后重新生成补丁，覆盖 `pcl-patch/pcl-download-rpc.patch`
3. 同步更新 `pcl-patch/files/` 中的改动文件
4. 同步更新 `NOTICE` 里的改动清单与 `pcl-patch/README.md` 的基线版本

## 自测

```powershell
# 宿主命令行自测（不经过浏览器）
powershell -ExecutionPolicy Bypass -File native-host\test-native-host.ps1
```

README 截图请放在 `docs/`，并保持文件名稳定（README 里引用它们）。
