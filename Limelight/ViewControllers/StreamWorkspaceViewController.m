#import "StreamWorkspaceViewController.h"
#import <UIKit/UIArrangementViewController.h>
#import <UIKit/UISplitArrangement.h>
#import <UIKit/UIOverlayArrangement.h>

@interface StreamWorkspacePassthroughView : UIView
@end
@implementation StreamWorkspacePassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

@interface StreamVideoRegionViewController : UIViewController
@property (nonatomic) CGRect contentFrame;
@property (nonatomic, copy) void (^layoutChanged)(void);
- (instancetype)initWithSurface:(UIView *)surface renderView:(UIView *)renderView;
@end

@implementation StreamVideoRegionViewController {
    UIView *_surface;
    UIView *_renderView;
}
- (instancetype)initWithSurface:(UIView *)surface renderView:(UIView *)renderView {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _surface = surface;
        _renderView = renderView;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.clipsToBounds = YES;
    self.view.backgroundColor = UIColor.blackColor;
    self.view.accessibilityIdentifier = @"stream-video-controller";
    [self.view addSubview:_surface];
}
- (void)setContentFrame:(CGRect)contentFrame {
    if (CGRectEqualToRect(_contentFrame, contentFrame)) return;
    _contentFrame = contentFrame;
    [self.viewIfLoaded setNeedsLayout];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _surface.frame = self.contentFrame;
    if (_surface != _renderView && [_surface isKindOfClass:UIScrollView.class] &&
        [(UIScrollView *)_surface zoomScale] == 1) _renderView.frame = _surface.bounds;
    if (self.layoutChanged) self.layoutChanged();
}
@end

@interface StreamOperationsRegionViewController : UIViewController
@property (nonatomic) CGRect contentFrame;
@property (nonatomic, copy) void (^layoutChanged)(void);
- (instancetype)initWithControlsSurface:(UIView *)surface;
@end

@implementation StreamOperationsRegionViewController {
    UIView *_surface;
}
- (instancetype)initWithControlsSurface:(UIView *)surface {
    if ((self = [super initWithNibName:nil bundle:nil])) _surface = surface;
    return self;
}
- (void)loadView {
    self.view = [[StreamWorkspacePassthroughView alloc] init];
    self.view.backgroundColor = UIColor.clearColor;
    self.view.opaque = NO;
    self.view.clipsToBounds = YES;
    self.view.accessibilityIdentifier = @"stream-operations-controller";
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view addSubview:_surface];
}
- (void)setContentFrame:(CGRect)contentFrame {
    if (CGRectEqualToRect(_contentFrame, contentFrame)) return;
    _contentFrame = contentFrame;
    [self.viewIfLoaded setNeedsLayout];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _surface.frame = self.contentFrame;
    if (self.layoutChanged) self.layoutChanged();
}
@end

@implementation StreamWorkspaceViewController {
    StreamVideoRegionViewController *_video;
    StreamOperationsRegionViewController *_operations;
    UIView *_controlsSurface;
    UIViewController *_arrangementHost;
    CGRect _foldRegion;
    CGRect _appliedFoldRegion;
    CGSize _appliedSize;
    BOOL _hasArrangement;
    BOOL _usingNativeSplit;
    BOOL _refreshingGeometry;
}

- (instancetype)initWithVideoSurface:(UIView *)surface renderView:(UIView *)renderView controlsSurface:(UIView *)controlsSurface {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _video = [[StreamVideoRegionViewController alloc] initWithSurface:surface renderView:renderView];
        _operations = [[StreamOperationsRegionViewController alloc] initWithControlsSurface:controlsSurface];
        _controlsSurface = controlsSurface;
        _foldRegion = _appliedFoldRegion = CGRectNull;
        _videoFrame = _operationsFrame = CGRectNull;
    }
    return self;
}

- (UIViewController *)operationsController { return _operations; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.view.accessibilityIdentifier = @"stream-workspace";
    __weak typeof(self) weakSelf = self;
    _video.layoutChanged = ^{ [weakSelf refreshRegionGeometry]; };
    _operations.layoutChanged = ^{ [weakSelf refreshRegionGeometry]; };
    if (@available(iOS 27.1, *)) {
        UIArrangementViewController *arrangement = [[UIArrangementViewController alloc] init];
        _arrangementHost = arrangement;
        [self addChildViewController:arrangement];
        arrangement.view.frame = self.view.bounds;
        arrangement.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:arrangement.view];
        [arrangement didMoveToParentViewController:self];
        [arrangement setViewController:_video forPlacement:UIArrangementViewControllerViewPlacementPrimary];
    }
    else {
        [self addChildViewController:_video];
        [self.view addSubview:_video.view];
        [_video didMoveToParentViewController:self];
    }
    [self attachOperationsOverlay];
}

- (void)attachOperationsOverlay {
    if (_operations.parentViewController == self) return;
    [self addChildViewController:_operations];
    [self.view addSubview:_operations.view];
    [_operations didMoveToParentViewController:self];
}

- (void)updateLayoutForFoldRegion:(CGRect)foldRegion settingsVisible:(BOOL)settingsVisible {
    _foldRegion = foldRegion;
    _controlsSurface.hidden = CGRectIsNull(foldRegion) || settingsVisible;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (void)updateNativeArrangement {
    if (@available(iOS 27.1, *)) {
        UIArrangementViewController *arrangement = (UIArrangementViewController *)_arrangementHost;
        BOOL split = !CGRectIsNull(_foldRegion);
        if (split && !_usingNativeSplit) {
            [_operations willMoveToParentViewController:nil];
            [_operations.view removeFromSuperview];
            [_operations removeFromParentViewController];
            [arrangement setViewController:_operations forPlacement:UIArrangementViewControllerViewPlacementSecondary];
        }
        else if (!split && _usingNativeSplit) {
            [arrangement setViewController:nil forPlacement:UIArrangementViewControllerViewPlacementSecondary];
            [self attachOperationsOverlay];
        }
        _usingNativeSplit = split;
        if (split) {
            UISplitArrangement *layout = [UISplitArrangement splitArrangement];
            layout.axes = UIAxisVertical;
            UISplitArrangementViewProperties *video = [[UISplitArrangementViewProperties alloc] init];
            video.height = [[UISplitArrangementDimensionRange alloc] init];
            video.width = [[UISplitArrangementDimensionRange alloc] init];
            UISplitArrangementDimension *height = [UISplitArrangementDimension absoluteDimension:MAX(0, CGRectGetMinY(_foldRegion))];
            video.height.minimum = video.height.preferred = video.height.maximum = height;
            video.width.minimum = video.width.preferred = video.width.maximum = [UISplitArrangementDimension fractionalDimension:1];
            video.layoutPriority = 1000;
            UISplitArrangementViewProperties *operations = [[UISplitArrangementViewProperties alloc] init];
            operations.height = [[UISplitArrangementDimensionRange alloc] init];
            operations.width = [[UISplitArrangementDimensionRange alloc] init];
            operations.height.minimum = [UISplitArrangementDimension absoluteDimension:0];
            operations.height.preferred = operations.height.maximum =
                [UISplitArrangementDimension absoluteDimension:MAX(0, self.view.bounds.size.height - CGRectGetMinY(_foldRegion))];
            operations.width.minimum = operations.width.preferred = operations.width.maximum = [UISplitArrangementDimension fractionalDimension:1];
            [layout setViewProperties:video forPlacement:UIArrangementViewControllerViewPlacementPrimary];
            [layout setViewProperties:operations forPlacement:UIArrangementViewControllerViewPlacementSecondary];
            [arrangement updateArrangement:layout animated:NO];
        }
        else {
            // A landscape hinge must not turn the stream into a side-by-side layout.
            UIOverlayArrangement *layout = [UIOverlayArrangement overlayArrangement];
            layout.axes = UIAxisNeither;
            [arrangement updateArrangement:layout animated:NO];
        }
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (_arrangementHost) {
        _arrangementHost.view.frame = self.view.bounds;
        if (!_hasArrangement || !CGRectEqualToRect(_foldRegion, _appliedFoldRegion) || !CGSizeEqualToSize(self.view.bounds.size, _appliedSize)) {
            _hasArrangement = YES;
            _appliedFoldRegion = _foldRegion;
            _appliedSize = self.view.bounds.size;
            [self updateNativeArrangement];
        }
        [_arrangementHost.view layoutIfNeeded];
        if (!_usingNativeSplit) _operations.view.frame = self.view.bounds;
    }
    else {
        CGRect video = self.view.bounds;
        CGRect operations = self.view.bounds;
        if (!CGRectIsNull(_foldRegion)) {
            video.size.height = MAX(0, CGRectGetMinY(_foldRegion));
            operations.origin.y = CGRectGetMaxY(_foldRegion);
            operations.size.height = MAX(0, self.view.bounds.size.height - operations.origin.y);
        }
        _video.view.frame = video;
        _operations.view.frame = operations;
    }
    [self refreshRegionGeometry];
}

- (void)refreshRegionGeometry {
    if (_refreshingGeometry || !self.isViewLoaded) return;
    _refreshingGeometry = YES;
    CGRect video = self.view.bounds;
    CGRect operations = self.view.bounds;
    if (!CGRectIsNull(_foldRegion)) {
        video.size.height = MAX(0, CGRectGetMinY(_foldRegion));
        operations.origin.y = CGRectGetMaxY(_foldRegion);
        operations.size.height = MAX(0, self.view.bounds.size.height - operations.origin.y);
    }
    // Native arrangements may already reserve the hinge. Clip in local coordinates
    // so the operation content never includes it in either layout path.
    CGRect videoContent = CGRectIntersection(_video.view.bounds, [self.view convertRect:video toView:_video.view]);
    CGRect operationContent = CGRectIntersection(_operations.view.bounds, [self.view convertRect:operations toView:_operations.view]);
    _video.contentFrame = CGRectIsNull(videoContent) ? CGRectZero : videoContent;
    _operations.contentFrame = CGRectIsNull(operationContent) ? CGRectZero : operationContent;
    [_video.view layoutIfNeeded];
    [_operations.view layoutIfNeeded];
    CGRect videoFrame = [_video.view convertRect:_video.contentFrame toView:self.view];
    CGRect operationFrame = [_operations.view convertRect:_operations.contentFrame toView:self.view];
    BOOL changed = !CGRectEqualToRect(videoFrame, _videoFrame) || !CGRectEqualToRect(operationFrame, _operationsFrame);
    _videoFrame = videoFrame;
    _operationsFrame = operationFrame;
    _refreshingGeometry = NO;
    if (changed && self.layoutChanged) self.layoutChanged();
}

- (CGRect)sidebarFrame {
    if (!CGRectIsNull(_foldRegion)) return self.operationsFrame;
    CGFloat width = MIN(420, self.view.bounds.size.width);
    return CGRectMake(CGRectGetMaxX(self.view.bounds) - width, CGRectGetMinY(self.view.bounds), width, self.view.bounds.size.height);
}
@end
