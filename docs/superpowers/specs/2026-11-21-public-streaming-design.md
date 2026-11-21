# 公网串流

上游 DiscoveryManager.isProhibitedAddress 为 App Store 指南 4.2.7a 增加了 IPv4 地址限制，项目 Release 配置启用 ENABLE_APP_STORE_RESTRICTIONS，Debug 未启用，因此真机 Release 会出现仅支持局域网的提示。

SideLantern iOS 的 Debug、Release 目标新增 SIDELANTERN_ALLOW_WAN_HOSTS，地址检查在此配置下允许公网主机。保留其他目标与原有应用列表筛选行为。本轮不改变配对、证书校验、主机存储和串流协议。

手动添加支持公网 IPv4、域名/DDNS、自定义 HTTP 端口与方括号 IPv6 地址；输入提示和键盘按地址输入调整。现有 Connection 使用 STREAM_CFG_AUTO 自动识别公网连接，VPN 使用 STREAM_CFG_REMOTE；底层已有远程 IPv4、IPv6 的数据包大小适配。

已通过签名 iOS Release 与模拟器 Release 编译。使用模拟器 Release 的原始对象文件链接独立检查库，在模拟器进程内替换 server-info 请求为模拟响应，验证公网 IPv4、域名、HTTP 自定义端口与 IPv6 的地址解析、主机添加、保留手动端点、不额外要求 LAN 可达、连接失败提示，以及已配对主机更新地址时保留证书和配对状态。该检查不创建凭据、不写主机数据库，也不发送网络请求。

公网实际串流需要服务端的控制、视频、音频与输入 TCP/UDP 端口可达。仅转发 Sunshine 管理网页端口不提供串流能力。本轮未进行真实公网串流联调，也未更新真机安装。
