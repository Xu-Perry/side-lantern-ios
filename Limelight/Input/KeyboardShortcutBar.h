#import <UIKit/UIKit.h>
#import "KeyboardShortcut.h"

@interface KeyboardShortcutBar : UIView
@property (nonatomic, copy) void (^keyHandler)(unsigned short keyCode, BOOL toggleable);
@property (nonatomic, copy) void (^shortcutHandler)(KeyboardShortcut *shortcut);
@property (nonatomic, copy) void (^dismissHandler)(void);
@property (nonatomic) KeyboardShortcutModifiers activeModifiers;
- (instancetype)initWithShortcutStore:(KeyboardShortcutStore *)store;
@end
