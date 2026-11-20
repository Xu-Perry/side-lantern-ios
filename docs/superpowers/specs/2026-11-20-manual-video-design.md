# 当前串流的手动画质设置

依据服务端提交 `03b9ca35e7ec6e96b09acc997af4f001d0d32789` 和同提交的无线副屏接口文档，接入码率、帧率、分辨率实时调整。

模式发现根节点的 `manual_video_version="1"` 表示协议能力。显式模式启动或恢复串流时追加 `sidelantern_manual_video=1`。建立连接后 GET 配对 HTTPS `/sidelantern/v1/manual-video` 获取当前会话 ID、编码宽高、帧率、编码目标码率和状态；编码器不支持时可没有可调整会话。

POST 必须只有 session_id、width、height、fps、bitrate_kbps 五个整数查询参数。客户端按用户实际修改的字段合并，其他值来自该会话最新查询。每次只发送一个请求，连续操作合并到后续请求。202 只表示接受，随后查询 pending/applied/rejected；只有 applied 才确认成功。会话 ID 改变、网络失败、超时和主机拒绝均显示明确反馈，不自动重连，也不切换到另一会话。

独立的 Foundation 参数模型、XML 响应解析器和更新控制器负责验证协议及串行状态管理。HttpManager 复用现有证书和 TLS 校验。设置容器传递用户修改事件和最新状态，串流 VC 管理控制器生命周期。支持实时控制时，页面展示当前会话参数；未确认的修改不覆盖本机视频偏好，确认后保存用户修改的字段。普通统计与虚拟控制调整继续走现有路径。

启动、排队、更新中、已应用、拒绝和不支持均有文案。码率滑动在操作结束后发送，分辨率与帧率只改变所选字段；实时模式不自动重算其他参数。旧服务端维持原有保存和下次连接生效行为。

视频解码已有新关键帧的格式解析。收到实际的新格式后更新视频宽高比例与 StreamView 触控映射，清理过期的缩放与虚拟按下状态；确认帧率后更新 display link 和帧节奏目标。保持连接、音频、编码格式、HDR、显示来源和工作区布局。

验证真实解析器和状态控制器的字段边界、重复/无效 XML、能力协商、POST 参数、pending 到 applied、拒绝、合并、取消和过期会话。构建 iOS Debug、签名 Release、tvOS；完成后更新 iPad 和 Duo 验收用模拟器。真实串流交互由用户验收。

已通过 `BuildScripts/check-manual-video.sh`（含迟到回复、主机上限、无可调整会话和超时）及原有串流目标协议检查；中英文 87 个资源键一致。iOS Debug 模拟器、签名 iOS Release、tvOS Debug 模拟器构建均通过。模拟器产物在 `/private/tmp/sidelantern-manual-video-build`，签名产物在 `/private/tmp/sidelantern-manual-video-release`。

已安装并打开 iPad 与 iPhone Duo 验收用模拟器，校验两者的 Moonlight.debug.dylib 与本次构建一致，启动进程正常。首次使用需重新建立串流，协商 sidelantern_manual_video=1；真实服务端串流交互尚未实测。
