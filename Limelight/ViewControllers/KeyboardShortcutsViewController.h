#import <UIKit/UIKit.h>
#import "KeyboardShortcut.h"

@interface KeyboardShortcutsViewController : UIViewController
@property (nonatomic, copy) void (^shortcutHandler)(KeyboardShortcut *shortcut);
@property (nonatomic, copy) void (^editingHandler)(void);
@end
