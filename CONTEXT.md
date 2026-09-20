# 项目约定

## 2026-09-20

- 开发分支为 `yq-dev`，基于 `weimo123/Ice` 的 `codex/complete-zh-hans-localization`（`eb4d2e1`）；推送目标为本仓库 `origin`（`yanquer/Ice`）。提交与推送仍需用户明确授权。
- 用户要求：构建后使用本机有效的 Apple Development 证书签名，安装到 `/Applications/Ice.app` 并验证。通过构建参数或本地签名命令指定身份，不把个人签名配置写入 Xcode 工程。
- 本机 Documents 构建目录可能被附加 Finder 属性，导致 `codesign` 报 `resource fork, Finder information, or similar detritus not allowed`。安装时将产物复制到同步目录外的暂存目录，排除扩展属性后签名；保留旧版本备份。
- macOS 26 会将菜单栏项目托管到控制中心。不能仅按窗口所属应用识别 Ice 分隔符，也不能将同名的 `Item-0` 窗口共用一个缓存键。无法表示为 `CGWindowID` 的 `NSWindow.windowNumber` 必须安全处理。
- 图像平均颜色采样需处理无有效像素的情况，返回空值以使用默认背景，避免透明菜单栏截图产生无效颜色。
- 回归测试命令见 [README](README.md#菜单栏兼容性回归测试)。用户已确认本机可以展开 Ice 栏并打开其中的 Wi-Fi 菜单；布局页的图标及深色背景已经实机检查。
