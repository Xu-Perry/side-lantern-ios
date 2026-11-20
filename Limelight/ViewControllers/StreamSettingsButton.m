#import "StreamSettingsButton.h"
#include <math.h>

static NSString *const EdgePreference = @"SideLantern.SettingsButton.Edge";
static NSString *const PositionPreference = @"SideLantern.SettingsButton.Position";

@implementation StreamSettingsButton {
    UIPanGestureRecognizer *_pan;
    NSTimer *_fadeTimer;
    CGPoint _dragStart;
    BOOL _dragging;
    BOOL _rightEdge;
    CGFloat _verticalPosition;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(frame.origin.x, frame.origin.y, 52, 52)])) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        _rightEdge = ![[defaults stringForKey:EdgePreference] isEqualToString:@"left"];
        _verticalPosition = [defaults objectForKey:PositionPreference] ? [defaults doubleForKey:PositionPreference] : 0.1;
        if (!isfinite(_verticalPosition)) _verticalPosition = 0.1;
        _verticalPosition = MIN(1, MAX(0, _verticalPosition));
        self.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1];
        self.tintColor = UIColor.whiteColor;
        self.layer.cornerRadius = 26;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.6].CGColor;
        self.alpha = 0.45;
        [self setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
        self.accessibilityLabel = NSLocalizedStringFromTable(@"settings.title", @"StreamTarget", nil);
        self.accessibilityIdentifier = @"stream-settings-button";
        [self addTarget:self action:@selector(beginInteraction) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [self addTarget:self action:@selector(endInteraction) forControlEvents:
            UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        _pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)];
        _pan.maximumNumberOfTouches = 1;
        _pan.cancelsTouchesInView = YES;
        [self addGestureRecognizer:_pan];
    }
    return self;
}

- (CGRect)centerBounds {
    CGRect bounds = CGRectInset(self.movementBounds, 38, 38);
    if (bounds.size.width < 0) { bounds.origin.x = CGRectGetMidX(self.movementBounds); bounds.size.width = 0; }
    if (bounds.size.height < 0) { bounds.origin.y = CGRectGetMidY(self.movementBounds); bounds.size.height = 0; }
    return bounds;
}

- (CGPoint)clampedCenter:(CGPoint)center {
    CGRect bounds = [self centerBounds];
    return CGPointMake(MIN(CGRectGetMaxX(bounds), MAX(CGRectGetMinX(bounds), center.x)),
        MIN(CGRectGetMaxY(bounds), MAX(CGRectGetMinY(bounds), center.y)));
}

- (void)setMovementBounds:(CGRect)movementBounds {
    if (CGRectEqualToRect(_movementBounds, movementBounds)) return;
    _movementBounds = movementBounds;
    if (CGRectIsEmpty(movementBounds) || CGRectIsNull(movementBounds)) return;
    if (_dragging) {
        self.center = [self clampedCenter:self.center];
        _dragStart = self.center;
        [_pan setTranslation:CGPointZero inView:self.superview];
    }
    else {
        [self snapToEdgeAnimated:NO];
    }
}

- (void)snapToEdgeAnimated:(BOOL)animated {
    CGRect bounds = [self centerBounds];
    CGPoint center = CGPointMake(_rightEdge ? CGRectGetMaxX(bounds) : CGRectGetMinX(bounds),
        CGRectGetMinY(bounds) + bounds.size.height * _verticalPosition);
    if (animated) {
        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState |
            UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut animations:^{ self.center = center; }
            completion:nil];
    }
    else self.center = center;
}

- (void)beginInteraction {
    [_fadeTimer invalidate];
    _fadeTimer = nil;
    [self.layer removeAllAnimations];
    self.alpha = 1;
}

- (void)endInteraction {
    if (_dragging || self.interactionActive) return;
    [_fadeTimer invalidate];
    __weak typeof(self) weakSelf = self;
    _fadeTimer = [NSTimer scheduledTimerWithTimeInterval:1.6 repeats:NO block:^(NSTimer *timer) {
        StreamSettingsButton *button = weakSelf;
        if (button && !button->_dragging && !button.interactionActive) {
            [UIView animateWithDuration:0.2 animations:^{ button.alpha = 0.45; }];
        }
    }];
}

- (void)setInteractionActive:(BOOL)interactionActive {
    if (_interactionActive == interactionActive) return;
    _interactionActive = interactionActive;
    if (interactionActive) [self beginInteraction];
    else [self endInteraction];
}

- (void)dragged:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        _dragging = YES;
        _dragStart = self.layer.presentationLayer ? self.layer.presentationLayer.position : self.center;
        [self beginInteraction];
    }
    CGPoint translation = [gesture translationInView:self.superview];
    self.center = [self clampedCenter:CGPointMake(_dragStart.x + translation.x, _dragStart.y + translation.y)];
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        _dragging = NO;
        CGRect bounds = [self centerBounds];
        _rightEdge = self.center.x >= CGRectGetMidX(self.movementBounds);
        _verticalPosition = bounds.size.height > 0 ? (self.center.y - CGRectGetMinY(bounds)) / bounds.size.height : 0.5;
        [NSUserDefaults.standardUserDefaults setObject:_rightEdge ? @"right" : @"left" forKey:EdgePreference];
        [NSUserDefaults.standardUserDefaults setDouble:_verticalPosition forKey:PositionPreference];
        [self snapToEdgeAnimated:YES];
        [self endInteraction];
    }
}

- (void)dealloc { [_fadeTimer invalidate]; }
@end
