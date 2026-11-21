# 设备列表与详情

按用户提供的两张设备管理参考图重新设计 iPhone、iPad 的设备入口。设备列表采用竖向分组和横向圆角卡片，显示封面、在线状态、主机名称、配对状态和进入箭头。支持全部设备/仅在线筛选、分组折叠、手动添加设备。串流设置入口放在设备详情，不在设备列表提供。

进入已配对设备后，详情页包含返回、状态与名称、设备菜单，桌面封面入口，文件/只看副屏/无线副屏/更多功能栏，以及快速启动应用区域。普通桌面和应用入口默认串流主显示器；只看副屏以独立入口串流副屏并熄灭主屏，无线副屏以独立入口请求扩展显示模式并保持主屏正常使用。串流设置中不再提供目标选择。封面使用主机桌面应用的现有封面；缺少封面时显示电脑插画占位。当前服务端没有主机截图接口，本轮不增加截图协议。文件传输和更多接入现有功能，暂不显示尚未支持的观看模式和终端入口。

快速启动从主机已经发布的应用中选择，多选结果按设备本机保存。不向主机创建应用。首次默认显示可见的非桌面应用；列表只显示已选应用，不显示添加应用卡片，选择应用从右侧“应用管理”进入。保留长按应用的恢复、退出、隐藏等已有菜单，长按只在手势开始时触发，鼠标右键仍可打开；菜单展示及转场期间不重复叠加。桌面入口优先使用用户选择的桌面应用或明确命名的 Desktop/桌面；无法识别时由用户选择入口，不自动启动其他应用。

点击已识别或已选择的桌面应用直接进入串流，不因主机上存在运行中的应用而弹出 Resume/Quit 菜单。StreamManager 查询服务端实时状态，空闲时启动桌面，会话仍在运行时直接恢复，不发送退出应用请求。首次无法识别桌面时保留应用选择步骤，选定后直接串流。

桌面入口回归检查使用当前构建的原始 iOS 代码，覆盖空闲主机、已有桌面会话、其他应用会话、未知运行应用 ID，以及用户自选桌面应用；各场景均只准备一次串流并进入串流页面，不弹出操作菜单或构造退出应用请求。检查过程替换页面跳转和网络终止入口，不连接主机或写客户端设置。iOS Debug、签名 Release 和 tvOS 构建通过。

设备浏览容器分别管理列表和详情子控制器，MainFrameViewController 保留发现、配对、主机/应用更新和串流启动协调。iOS 不再因只有一个已保存设备而跳过设备列表。tvOS 保持已有设备和应用界面。

界面遵循系统浅色/深色外观，手机纵向布局，宽屏设备列表采用多列卡片和自适应应用网格。采用控制器管理状态栏，设备与设置页面显示系统状态栏，串流控制器继续隐藏状态栏。

保留本轮尚未提交的文件传输实现。验证列表、详情、空应用、长名称、设备离线和应用管理布局，构建 iOS Debug/Release 与 tvOS，并更新验收模拟器。真实配对、串流和文件收发由用户验收。

## 实现与验证

已接入独立的 DeviceBrowserViewController，分别用列表、详情与应用选择子控制器管理页面；MainFrameViewController 继续协调原有配对、应用获取、串流和设备菜单。文件传输入口复用现有 FileTransferViewController。详情的齿轮进入已有串流设置页，返回时恢复设备详情。

快速启动按主机 UUID 保存应用 ID，多选保存和应用重启后的恢复已在模拟器实际验证。桌面应用缺少明确命名时提供手动选择，设备离线时禁用串流入口。模拟器预览数据只编译进 Debug 模拟器构建。

已检查 iPhone 浅色/深色列表、iPad 横屏双列列表与详情、Duo 内屏详情与空应用状态，以及真实客户端首页设置的进入和返回。详情视图按安全区布局，iPad 顶部和 Duo 系统状态区域避让已检查。截图位于 Build/DeviceBrowserUI。

iOS Debug 模拟器、签名 iOS Release 与 tvOS Debug 构建通过；文件传输协议、数据完整性与断点续传检查通过。未进行真实 Windows 配对、串流或文件收发。未提交或推送本轮改动。

## 移除设备后的重新发现

列表与详情采用子控制器切换后，返回列表不会触发 MainFrameViewController.viewWillAppear；删除主机也没有清除 MDNSManager 缓存的服务记录，导致相同服务后续广播被视为已经处理。现在返回列表和移除设备时主动清理服务记录并立即重启 Bonjour 搜索，保留其余已保存主机的轮询。

扫描定时器改为可取消的常用运行循环模式定时器，停止扫描时立即失效，重新开始时无需等待旧定时器。清理服务时停止旧的地址解析，并忽略已移除服务的解析重试。

已使用生产 iOS 代码与模拟 Bonjour 服务完成回归检查：先处理已配对设备的服务记录，移除设备后复现缓存阻止解析，再刷新搜索，验证再次解析、发现回调和新设备卡片渲染；同时检查停止与重启的定时器行为。该检查不发送网络请求、不写主机数据库。真实局域网广播与地址解析已通过现有 FUXI 主机确认。

## 横屏边距与原生导航过渡

iPhone 横屏的列表和详情标题距视图顶部至少 32pt，同时保留系统安全区。设备列表不再显示串流设置按钮或设置菜单项；设备详情保留设置入口。

设备页面隐藏导航栏，独立设置页显示系统导航栏。采用 SideLanternNavigationController 在 UINavigationControllerDelegate.willShow 中调用 setNavigationBarHidden:animated:，直接使用本次 push/pop 的 animated 参数，让 UIKit 同步处理页面、导航栏和交互返回。didShow 仅在显示状态不一致时按最终页面纠正，覆盖交互返回取消的情况。页面不再竞争修改共用导航栏的显示状态或明暗外观。

导航栏保持设置所需的深色外观，内容页面各自选择系统或深色外观；设置页面通过自己的 UINavigationItem 配置 standard、scroll-edge、compact 和 compact-scroll-edge 外观。保留系统标题、返回按钮、原生转场和返回手势。iPhone、iPad storyboard 根导航控制器及设备/串流预览共用该实现，tvOS 保留原有行为。

设置页面背景延伸到半透明系统导航栏下方，内容继续按安全区留出顶部空间。避免 UIRectEdgeNone 将黑色页面裁到导航栏下方，造成 push 过程中导航栏背后短暂露出前一页浅色背景。

官方依据：Apple 的 [Navigation Controllers](https://developer.apple.com/library/archive/documentation/WindowsViews/Conceptual/ViewControllerCatalog/Chapters/NavigationControllers.html) 明确支持按页面显示/隐藏导航栏并配合页面切换；[setNavigationBarHidden(_:animated:)](https://developer.apple.com/documentation/uikit/uinavigationcontroller/setnavigationbarhidden(_:animated:)) 说明 animated=false 会立即显示；[willShow](https://developer.apple.com/documentation/uikit/uinavigationcontrollerdelegate/navigationcontroller(_:willshow:animated:)) 在目标页面显示前通知代理并传入本次转场的动画参数。

验证：iOS Debug 模拟器、签名 iOS Release、tvOS Debug 构建通过。Duo 内屏横屏的真实设置页进入和按钮返回已录屏并逐帧检查，设置页面及导航栏背景共同滑入，顶部不再短暂露出前页浅色背景。普通 iPhone 已检查实际侧滑返回的中途取消与完整返回，取消后恢复设置和导航栏，完成后恢复设备详情并隐藏导航栏；iPad 横屏已检查进入和按钮返回，设置内容避开导航栏。更新了 iPhone、iPad、Duo 验收模拟器。截图与录屏位于 Build/DeviceBrowserUI，未提交或推送改动。
