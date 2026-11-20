# 串流目标界面实现步骤

对应设计：`../specs/2026-11-20-stream-target-ui-design.md`。

1. 新增独立的 Foundation 偏好模型。保存稳定的本机字符串值，校验读取结果，未知值回到主屏幕。
2. 新增 UIKit 单选组件。通过纵向布局支持三种模式的说明、选中状态、动态字体和辅助功能；添加中英文资源。
3. 在现有设置控制器中加载组件并保存选择，按测量高度调整原有控件的位置及滚动范围。保持两个 Storyboard 共用控制器。
4. 注册新增源文件和资源到 Xcode iOS target，保持 tvOS 原有设置入口。
5. 初始化原有 Git 子模块，按现有 CI 的 Xcode scheme 和 simulator SDK 验证构建。
6. 接入 `/sidelantern/v1/stream-modes` 与 `/launch`、`/resume` 的 `sidelantern_mode` 参数。沿用证书认证，处理可用性、拒绝原因及旧主机兼容。
7. 运行 `bash BuildScripts/check-stream-targets.sh` 检查偏好恢复、协议映射、无效 XML 和启动拒绝原因；检查最终 diff。

服务端 API 发布后，按用户后续指示接入其已提交的接口。用户明确本轮以编译通过交付，不进行 Windows 主机联调；三种模式的显示效果和布局恢复留待回家后实测。
