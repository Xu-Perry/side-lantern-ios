#import <UIKit/UIKit.h>
#import "ManualVideoSettings.h"

@class TemporaryHost, SettingsViewController;

@interface SettingsSidebar : NSObject
@property (nonatomic, readonly) SettingsViewController *settings;
@property (nonatomic, readonly, getter=isVisible) BOOL visible;
@property (nonatomic, readonly) UIView *view;
@property (nonatomic, copy) void (^settingsChanged)(void);
@property (nonatomic, copy) void (^visibilityChanged)(BOOL visible);
@property (nonatomic, copy) void (^exitStreamHandler)(void);
@property (nonatomic, copy) void (^videoSettingsChanged)(ManualVideoSettings *settings, ManualVideoFields fields);
@property (nonatomic) BOOL onScreenControlsAvailable;
- (instancetype)initWithParent:(UIViewController *)parent;
- (instancetype)initWithParent:(UIViewController *)parent overlayParent:(UIViewController *)overlayParent;
- (void)showForHost:(TemporaryHost *)host frame:(CGRect)frame streaming:(BOOL)streaming;
- (void)layoutInFrame:(CGRect)frame;
- (void)close;
- (void)updateManualVideoSettings:(ManualVideoSettings *)settings available:(BOOL)available updating:(BOOL)updating message:(NSString *)message;
@end
