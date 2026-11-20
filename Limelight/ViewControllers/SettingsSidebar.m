#import "SettingsSidebar.h"
#import "StreamSettingsContainerViewController.h"

// Coordinates presentation; all region layout and containment belongs to the container VC.
@implementation SettingsSidebar {
    __weak UIViewController *_parent;
    __weak UIViewController *_overlayParent;
    StreamSettingsContainerViewController *_container;
}

- (instancetype)initWithParent:(UIViewController *)parent {
    return [self initWithParent:parent overlayParent:parent];
}

- (instancetype)initWithParent:(UIViewController *)parent overlayParent:(UIViewController *)overlayParent {
    if ((self = [super init])) {
        _parent = parent;
        _overlayParent = overlayParent;
        _onScreenControlsAvailable = YES;
    }
    return self;
}

- (SettingsViewController *)settings { return _container.settings; }
- (UIView *)view { return _container.dismissMaskView; }
- (BOOL)isVisible { return _container != nil; }

- (void)showForHost:(TemporaryHost *)host frame:(CGRect)frame streaming:(BOOL)streaming {
    if (self.visible) { [self close]; return; }
    if (_parent == nil || !streaming) return;
    _container = [[StreamSettingsContainerViewController alloc] initWithStoryboard:_overlayParent.storyboard host:host];
    _container.onScreenControlsAvailable = self.onScreenControlsAvailable;
    __weak typeof(self) weakSelf = self;
    _container.settingsChanged = ^{ if (weakSelf.settingsChanged) weakSelf.settingsChanged(); };
    _container.dismissHandler = ^{ [weakSelf close]; };
    _container.exitStreamHandler = ^{ if (weakSelf.exitStreamHandler) weakSelf.exitStreamHandler(); };
    _container.videoSettingsChanged = ^(ManualVideoSettings *settings, ManualVideoFields fields) {
        if (weakSelf.videoSettingsChanged) weakSelf.videoSettingsChanged(settings, fields);
    };
    [_parent addChildViewController:_container];
    _container.view.frame = _parent.view.bounds;
    _container.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_parent.view addSubview:_container.view];
    [self layoutInFrame:frame];
    [_container didMoveToParentViewController:_parent];
    if (self.visibilityChanged) self.visibilityChanged(YES);
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, _container.view);
}

- (void)layoutInFrame:(CGRect)frame {
    if (_container == nil) return;
    _container.view.frame = _parent.view.bounds;
    CGRect localFrame = [_overlayParent.view convertRect:frame toView:_parent.view];
    [_container layoutSidebarInFrame:localFrame];
    [_container placeDismissMaskInView:_overlayParent.view excludingFrame:frame];
}

- (void)close {
    if (_container == nil) return;
    [_container saveSettings];
    if (self.settingsChanged) self.settingsChanged();
    [_container willMoveToParentViewController:nil];
    [_container.dismissMaskView removeFromSuperview];
    [_container.view removeFromSuperview];
    [_container removeFromParentViewController];
    _container = nil;
    if (self.visibilityChanged) self.visibilityChanged(NO);
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
}

- (void)updateManualVideoSettings:(ManualVideoSettings *)settings available:(BOOL)available updating:(BOOL)updating message:(NSString *)message {
    [_container updateManualVideoSettings:settings available:available updating:updating message:message];
}
@end
