#import <UIKit/UIKit.h>
#import "ManualVideoSettings.h"

@class TemporaryHost, SettingsViewController, KeyboardShortcut;

// Owns the stream-only settings workspace and its region controllers.
@interface StreamSettingsContainerViewController : UIViewController
@property (nonatomic, readonly) SettingsViewController *settings;
@property (nonatomic, readonly) UIView *dismissMaskView;
@property (nonatomic, copy) void (^settingsChanged)(void);
@property (nonatomic, copy) void (^dismissHandler)(void);
@property (nonatomic, copy) void (^exitStreamHandler)(void);
@property (nonatomic, copy) void (^videoSettingsChanged)(ManualVideoSettings *settings, ManualVideoFields fields);
@property (nonatomic) BOOL onScreenControlsAvailable;
@property (nonatomic) BOOL keyboardVisible;
@property (nonatomic, copy) void (^keyboardToggleHandler)(void);
@property (nonatomic, copy) void (^keyboardShortcutHandler)(KeyboardShortcut *shortcut);
@property (nonatomic, copy) void (^shortcutEditingHandler)(void);
- (instancetype)initWithStoryboard:(UIStoryboard *)storyboard host:(TemporaryHost *)host;
- (void)layoutSidebarInFrame:(CGRect)frame;
- (void)placeDismissMaskInView:(UIView *)view excludingFrame:(CGRect)frame;
- (void)saveSettings;
- (void)updateManualVideoSettings:(ManualVideoSettings *)settings available:(BOOL)available updating:(BOOL)updating message:(NSString *)message;
@end
