# 串流工作区 Arrangement 布局

用户要求继续在已拆分的设置容器基础上接入 iOS 27.1 的 UIArrangementViewController。增加 StreamWorkspaceViewController，持有稳定的视频子 VC 和操作子 VC；连接、解码、输入和设置持久化仍由原有对象负责。

新系统将视频放在 Primary。Duo 竖屏依据实际 division reserved region 使用垂直 UISplitArrangement，操作子 VC 放在 Secondary，内容避开折痕。普通设备和横屏使用禁止自动分栏的 UIOverlayArrangement，只有视频占据 Primary；操作 VC 位于工作区覆盖层，避免透明操作区域拦截视频输入以及打开设置时缩小视频。布局切换时重用子 VC 和串流对象，不启动或中止连接。旧系统沿用同一子 VC 结构，通过手动布局提供兼容路径。

操作 VC 承载虚拟控制界面和设置容器。设置打开时隐藏虚拟控制界面；侧栏在普通布局贴右，在 Duo 竖屏占据折痕下方的可用区域。设置容器管理透明关闭遮罩，但遮罩挂载到整个串流工作区，以覆盖分区外的视频。遮罩对侧栏本身放行点击，对外部点击执行关闭。

浮动按钮、启动提示和统计显示按工作区实际布局定位。UILayout 更新通知只触发布局，不重建连接或解码器。折痕状态仍由 UIHingeInteraction 驱动，包括 inactive 的 division region，保留已有的展开状态布局约定。

本轮只检查 iOS Debug 模拟器、签名 iOS Release 和 tvOS 共享代码编译；构建使用独立目录，不安装、启动、拖动或操作用户的模拟器和串流会话。

已完成：iOS Debug 模拟器、签名 iOS Release、tvOS Debug 模拟器构建均通过；项目文件格式与 git diff --check 通过。模拟器构建在 `/private/tmp/sidelantern-arrangement-side-build`，签名构建在 `/private/tmp/sidelantern-arrangement-side-release`。折叠、旋转、输入和遮罩交互尚未实测。
