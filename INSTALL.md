# 下载与安装右键助手

## 下载

打开 [GitHub Releases](https://github.com/DeadPool0o/rightmenu-helper/releases/latest)，在 **Assets** 中选择：

| 文件 | 用途 |
| --- | --- |
| `RightClickAssistant-版本号-macos-universal.pkg` | 推荐。双击后使用 macOS 安装程序安装到“应用程序” |
| `RightClickAssistant-版本号-macos-universal.zip` | 便携版本。解压后将“右键助手.app”放入“应用程序” |
| `SHA256SUMS.txt` | 下载文件的 SHA-256 校验值 |
| `release-info.json` | 版本、架构、最低系统要求、源码提交及签名状态 |

最低系统要求为 macOS 13。同一安装包同时包含 Apple 芯片（arm64）和 Intel（x86_64）版本。应用使用原生 AppKit 和 Finder Sync，仅支持 macOS。安装包包含程序和内置模板，使用者无需安装开发工具。

## 安装

1. 下载 `.pkg` 文件并双击打开。
2. 按安装程序提示继续，并授权安装到 `/Applications/右键助手.app`。
3. 从“应用程序”打开“右键助手”。
4. 进入“通用设置”，打开 Finder 扩展设置并启用“右键助手”。
5. 在访达或桌面右键，查看新增菜单。

升级前请退出运行中的右键助手。安装程序固定更新“应用程序”中的版本，不会搜索并覆盖其他目录中的开发副本；用户设置与自定义模板保存在用户资源库中。

## 首次打开与签名

当前发布版本的应用使用 **ad-hoc 本地签名**，安装包**未使用 Developer ID Installer 证书签名，未经过 Apple 公证**。这不等同于 Apple 认证的开发者签名。

macOS 可能阻止首次打开从网上下载的安装包或应用。确认下载来源为本项目的 GitHub Releases 后，可在首次尝试打开后，前往“系统设置 → 隐私与安全性”，对该安装包或应用选择“仍要打开”，并按系统提示确认。安装包与应用可能分别触发检查。详细流程参见 [Apple 官方说明](https://support.apple.com/102445)。

## 校验下载

将安装包、ZIP、`release-info.json` 和 `SHA256SUMS.txt` 放入同一目录，在该目录执行：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

校验值用于确认下载文件与本次发布一致，不能替代 Developer ID 签名和公证。

## 卸载

先在 Finder 扩展设置中关闭“右键助手”，再从菜单栏退出应用，将“应用程序”中的“右键助手.app”移到废纸篓。用户设置会保留，便于以后重新安装。
