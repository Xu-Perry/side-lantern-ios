#import <UIKit/UIKit.h>

// Keeps the video and operation controllers alive while their arrangement changes.
@interface StreamWorkspaceViewController : UIViewController
@property (nonatomic, readonly) UIViewController *operationsController;
@property (nonatomic, readonly) CGRect videoFrame;
@property (nonatomic, readonly) CGRect operationsFrame;
@property (nonatomic, readonly) CGRect sidebarFrame;
@property (nonatomic, copy) void (^layoutChanged)(void);
- (instancetype)initWithVideoSurface:(UIView *)surface renderView:(UIView *)renderView controlsSurface:(UIView *)controlsSurface;
- (void)updateLayoutForFoldRegion:(CGRect)foldRegion settingsVisible:(BOOL)settingsVisible;
@end
