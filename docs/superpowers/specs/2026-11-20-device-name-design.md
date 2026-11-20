# 客户端设备名称

删除固定的 roth。配对请求使用当前设备可读取的名称：模拟器优先使用 SIMULATOR_DEVICE_NAME；真实设备优先使用 UIDevice.name 的非通用名称。系统仅提供通用型号时，以设备类型和本机持久化客户端 ID 的前六位大写短标识区分，例如 iPad-3A8F21。保留配对协议原有的共用 uniqueid，不用它生成设备名称。

iOS 16 之后，读取用户自定义名称需要 com.apple.developer.device-information.user-assigned-device-name 权限。当前 provisioning profile 和应用签名均未包含该权限，因此本轮不声称可以读取诸如 iPan 的真实自定义名称，也不增加未授权的签名权限。

设备名称在配对 URL 中正确编码，支持空格、中文和特殊字符。服务端将客户端名称保存到配对记录，当前会话使用该记录的名称；已有 roth 记录不会因客户端更新自动改名，需要用户重新配对。本轮不取消现有配对，不修改服务端记录。

## 验证

- iOS 模拟器 Debug、真机 Release 和 tvOS 模拟器 Debug 编译通过，真机签名权限保持原样。
- 独立模拟器检查进程加载实际构建的 Moonlight.debug.dylib，验证系统名称、模拟器名称优先级、通用名称和本机 ID 的稳定回退。
- 五个配对请求均验证中文、空格、&、+、#、?、%、=、/ 和 emoji 的名称往返；配对参数数量及原有 uniqueid 保持正确。
- iPad 和 iPhone Duo 模拟器分别读取到 SideLantern-iPad-UI 和 iPhone Duo；已安装并启动本轮构建，交互验收由用户完成。
