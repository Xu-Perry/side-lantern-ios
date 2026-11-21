#import <UIKit/UIKit.h>
#import "UIComputerView.h"
#import "UIAppView.h"

@interface DeviceBrowserViewController : UIViewController
@property (nonatomic, weak) id<HostCallback> hostDelegate;
@property (nonatomic, weak) id<AppCallback> appDelegate;
@property (nonatomic, copy) void (^openSettings)(TemporaryHost *host);
@property (nonatomic, copy) void (^openDesktop)(TemporaryHost *host, UIView *source);
@property (nonatomic, copy) void (^openFiles)(TemporaryHost *host);
@property (nonatomic, copy) BOOL (^supportsFiles)(TemporaryHost *host);
@property (nonatomic, copy) void (^backToHosts)(void);
@property (nonatomic, copy) void (^didManageApps)(void);
- (instancetype)initWithArtworkCache:(NSCache *)cache;
- (void)updateHosts:(NSArray<TemporaryHost *> *)hosts;
- (void)showHosts;
- (void)showHost:(TemporaryHost *)host allApps:(BOOL)allApps;
- (void)refreshArtwork;
- (void)setInteractionEnabled:(BOOL)enabled;
+ (TemporaryApp *)desktopApplicationForHost:(TemporaryHost *)host;
+ (void)setDesktopApplication:(TemporaryApp *)app forHost:(TemporaryHost *)host;
@end

#if DEBUG && TARGET_OS_SIMULATOR
UIViewController *DeviceBrowserPreview(BOOL detail, BOOL empty);
#endif
