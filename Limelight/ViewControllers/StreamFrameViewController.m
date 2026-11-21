//
//  StreamFrameViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "StreamFrameViewController.h"
#import "MainFrameViewController.h"
#import "VideoDecoderRenderer.h"
#import "StreamManager.h"
#import "ControllerSupport.h"
#import "DataManager.h"
#if !TARGET_OS_TV
#import "SettingsSidebar.h"
#import "StreamSettingsButton.h"
#import "StreamWorkspaceViewController.h"
#import "ManualVideoController.h"
#import "HttpManager.h"

static BOOL StreamHasTextResponder(UIView *view) {
    if (view.isFirstResponder && [view conformsToProtocol:@protocol(UITextInput)]) return YES;
    for (UIView *child in view.subviews) if (StreamHasTextResponder(child)) return YES;
    return NO;
}
#endif

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <Limelight.h>

#if TARGET_OS_TV
#import <AVFoundation/AVDisplayCriteria.h>
#import <AVKit/AVDisplayManager.h>
#import <AVKit/UIWindow.h>
#endif

@interface AVDisplayCriteria()
@property(readonly) int videoDynamicRange;
@property(readonly, nonatomic) float refreshRate;
- (id)initWithRefreshRate:(float)arg1 videoDynamicRange:(int)arg2;
@end

@implementation StreamFrameViewController {
    ControllerSupport *_controllerSupport;
    StreamManager *_streamMan;
    TemporarySettings *_settings;
    NSTimer *_inactivityTimer;
    NSTimer *_statsUpdateTimer;
    UITapGestureRecognizer *_menuTapGestureRecognizer;
    UITapGestureRecognizer *_menuDoubleTapGestureRecognizer;
    UITapGestureRecognizer *_playPauseTapGestureRecognizer;
    UITextView *_overlayView;
    UILabel *_stageLabel;
    UILabel *_tipLabel;
    UIActivityIndicatorView *_spinner;
    StreamView *_streamView;
    UIScrollView *_scrollView;
    BOOL _userIsInteracting;
    CGSize _keyboardSize;
    
#if !TARGET_OS_TV
    UIScreenEdgePanGestureRecognizer *_exitSwipeRecognizer;
    StreamSettingsButton *_settingsFloatButton;
    UIView *_controlsSurface;
    SettingsSidebar *_settingsSidebar;
    StreamWorkspaceViewController *_workspace;
    UILayoutGuide *_keyboardViewportGuide;
    ManualVideoController *_manualVideoController;
    BOOL _separateControls;
    BOOL _connectionStarted;
#if DEBUG && TARGET_OS_SIMULATOR
    UIView *_previewCanvas;
    NSString *_lastPreviewGeometry;
#endif
#endif
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
#if !TARGET_OS_TV
    [[self revealViewController] setPrimaryViewController:self];
    if (@available(iOS 16.0, *)) [self setNeedsUpdateOfSupportedInterfaceOrientations];
#endif
}

#if !TARGET_OS_TV
- (BOOL)prefersStatusBarHidden { return YES; }
#endif

#if TARGET_OS_TV
- (void)controllerPauseButtonPressed:(id)sender { }
- (void)controllerPauseButtonDoublePressed:(id)sender {
    Log(LOG_I, @"Menu double-pressed -- backing out of stream");
    [self returnToMainFrame];
}
- (void)controllerPlayPauseButtonPressed:(id)sender {
    Log(LOG_I, @"Play/Pause button pressed -- backing out of stream");
    [self returnToMainFrame];
}
#endif


- (void)viewDidLoad
{
    [super viewDidLoad];
    
#if TARGET_OS_TV
    [self.navigationController setNavigationBarHidden:YES animated:YES];
#endif
    
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    _settings = [[[DataManager alloc] init] getSettings];
    
    _stageLabel = [[UILabel alloc] init];
    [_stageLabel setUserInteractionEnabled:NO];
    [_stageLabel setText:[NSString stringWithFormat:@"Starting %@...", self.streamConfig.appName]];
    [_stageLabel sizeToFit];
    _stageLabel.textAlignment = NSTextAlignmentCenter;
    _stageLabel.textColor = [UIColor whiteColor];
    _stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2);
    
    _spinner = [[UIActivityIndicatorView alloc] init];
    [_spinner setUserInteractionEnabled:NO];
#if TARGET_OS_TV
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhiteLarge];
#else
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhite];
#endif
    [_spinner sizeToFit];
    [_spinner startAnimating];
    _spinner.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2 - _stageLabel.frame.size.height - _spinner.frame.size.height);
    
    _controllerSupport = [[ControllerSupport alloc] initWithConfig:self.streamConfig delegate:self];
    _inactivityTimer = nil;
    
    _streamView = [[StreamView alloc] initWithFrame:self.view.frame];
    _streamView.accessibilityIdentifier = @"stream-video-area";
    [_streamView setupStreamView:_controllerSupport interactionDelegate:self config:self.streamConfig];
    
#if TARGET_OS_TV
    if (!_menuTapGestureRecognizer || !_menuDoubleTapGestureRecognizer || !_playPauseTapGestureRecognizer) {
        _menuTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonPressed:)];
        _menuTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];

        _playPauseTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPlayPauseButtonPressed:)];
        _playPauseTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypePlayPause)];
        
        _menuDoubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonDoublePressed:)];
        _menuDoubleTapGestureRecognizer.numberOfTapsRequired = 2;
        [_menuTapGestureRecognizer requireGestureRecognizerToFail:_menuDoubleTapGestureRecognizer];
        _menuDoubleTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];
    }
    
    [self.view addGestureRecognizer:_menuTapGestureRecognizer];
    [self.view addGestureRecognizer:_menuDoubleTapGestureRecognizer];
    [self.view addGestureRecognizer:_playPauseTapGestureRecognizer];

#else
    _exitSwipeRecognizer = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(edgeSwiped)];
    _exitSwipeRecognizer.edges = UIRectEdgeLeft;
    _exitSwipeRecognizer.delaysTouchesBegan = NO;
    _exitSwipeRecognizer.delaysTouchesEnded = NO;
    _exitSwipeRecognizer.delegate = self;
    
    [self.view addGestureRecognizer:_exitSwipeRecognizer];
#endif
    
    _tipLabel = [[UILabel alloc] init];
    [_tipLabel setUserInteractionEnabled:NO];
    
#if TARGET_OS_TV
    [_tipLabel setText:@"Tip: Tap the Play/Pause button on the Apple TV Remote to disconnect from your PC"];
#else
    [_tipLabel setText:NSLocalizedStringFromTable(@"stream.exit_tip", @"StreamTarget", nil)];
#endif
    
    [_tipLabel sizeToFit];
    _tipLabel.textColor = [UIColor whiteColor];
    _tipLabel.textAlignment = NSTextAlignmentCenter;
    _tipLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height * 0.9);
    
    _streamMan = [[StreamManager alloc] initWithConfig:self.streamConfig
                                            renderView:_streamView
                                   connectionCallbacks:self];
#if DEBUG && TARGET_OS_SIMULATOR
    BOOL layoutPreview = [NSProcessInfo.processInfo.arguments containsObject:@"--sidelantern-stream-preview"];
    if (!layoutPreview) {
#endif
        NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
        [opQueue addOperation:_streamMan];
#if DEBUG && TARGET_OS_SIMULATOR
    }
#endif
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidBecomeActive:)
                                                 name: UIApplicationDidBecomeActiveNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidEnterBackground:)
                                                 name: UIApplicationDidEnterBackgroundNotification
                                               object: nil];

#if 0
    // FIXME: This doesn't work reliably on iPad for some reason. Showing and hiding the keyboard
    // several times in a row will not correctly restore the state of the UIScrollView.
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillShow:)
                                                 name: UIKeyboardWillShowNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillHide:)
                                                 name: UIKeyboardWillHideNotification
                                               object: nil];
#endif
    
    // Only enable scroll and zoom in absolute touch mode
    if (_settings.absoluteTouchMode) {
        _scrollView = [[UIScrollView alloc] initWithFrame:self.view.frame];
#if !TARGET_OS_TV
        [_scrollView.panGestureRecognizer setMinimumNumberOfTouches:2];
#endif
        [_scrollView setShowsHorizontalScrollIndicator:NO];
        [_scrollView setShowsVerticalScrollIndicator:NO];
        [_scrollView setDelegate:self];
        [_scrollView setMaximumZoomScale:10.0f];
        
        // Add StreamView inside a UIScrollView for absolute mode
        [_scrollView addSubview:_streamView];
#if TARGET_OS_TV
        [self.view addSubview:_scrollView];
#endif
    }
    else {
        // Add StreamView directly in relative mode
#if TARGET_OS_TV
        [self.view addSubview:_streamView];
#endif
    }

#if !TARGET_OS_TV
    _controlsSurface = [_streamView makeControlsSurface];
    _controlsSurface.hidden = YES;
    _workspace = [[StreamWorkspaceViewController alloc] initWithVideoSurface:_scrollView ?: _streamView
        renderView:_streamView controlsSurface:_controlsSurface];
    [self addChildViewController:_workspace];
    _workspace.view.frame = self.view.bounds;
    _workspace.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_workspace.view];
    [_workspace didMoveToParentViewController:self];
#endif
    
    [self.view addSubview:_stageLabel];
    [self.view addSubview:_spinner];
    [self.view addSubview:_tipLabel];
#if !TARGET_OS_TV
    _settingsSidebar = [[SettingsSidebar alloc] initWithParent:_workspace.operationsController overlayParent:self];
    _settingsSidebar.onScreenControlsAvailable = !_settings.absoluteTouchMode;
    __weak typeof(self) weakSelf = self;
    _workspace.layoutChanged = ^{ [weakSelf.view setNeedsLayout]; };
    _settingsSidebar.settingsChanged = ^{ [weakSelf applyLiveSettings]; };
    _settingsSidebar.exitStreamHandler = ^{ [weakSelf returnToMainFrame]; };
    _settingsSidebar.keyboardToggleHandler = ^{ [weakSelf toggleStreamKeyboard]; };
    _settingsSidebar.keyboardShortcutHandler = ^(KeyboardShortcut *shortcut) {
        StreamFrameViewController *controller = weakSelf;
        if (controller) [controller->_streamView sendKeyboardShortcut:shortcut];
    };
    _settingsSidebar.shortcutEditingHandler = ^{
        StreamFrameViewController *controller = weakSelf;
        if (controller) { [controller.view endEditing:YES]; [controller->_streamView hideKeyboard]; }
    };
    _keyboardViewportGuide = [[UILayoutGuide alloc] init];
    [self.view addLayoutGuide:_keyboardViewportGuide];
    [NSLayoutConstraint activateConstraints:@[
        [_keyboardViewportGuide.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_keyboardViewportGuide.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_keyboardViewportGuide.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_keyboardViewportGuide.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor]]];
    _streamView.keyboardVisibilityChanged = ^(BOOL visible) {
        StreamFrameViewController *controller = weakSelf;
        if (!controller) return;
        if (visible) [controller->_settingsSidebar close];
        [controller refreshKeyboardState];
        [controller.view setNeedsLayout];
    };
    for (NSNotificationName name in @[UIKeyboardDidShowNotification, UIKeyboardDidHideNotification, UIKeyboardDidChangeFrameNotification]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardStateDidChange:) name:name object:nil];
    }
    _settingsSidebar.videoSettingsChanged = ^(ManualVideoSettings *settings, ManualVideoFields fields) {
        StreamFrameViewController *controller = weakSelf;
        if (!controller) return;
        if (fields & ManualVideoBitrate) controller.streamConfig.bitRate = (int)settings.bitrate;
        [controller->_manualVideoController requestSettings:settings fields:fields bitrateBudget:settings.bitrate];
    };
    _settingsSidebar.visibilityChanged = ^(BOOL visible) {
        StreamFrameViewController *controller = weakSelf;
        if (controller) {
            [controller->_streamView cancelControlTouches];
            controller->_settingsFloatButton.interactionActive = visible || controller->_userIsInteracting;
            [controller.view setNeedsLayout];
        }
    };
    _settingsFloatButton = [[StreamSettingsButton alloc] initWithFrame:CGRectZero];
    [_settingsFloatButton addTarget:self action:@selector(toggleStreamSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_settingsFloatButton];
    if (@available(iOS 27.1, *)) {
        // Hinge updates invalidate the custom layout; the geometry itself still
        // comes from the system's division reserved region.
        [self.view addInteraction:[[UIHingeInteraction alloc] initWithUpdateHandler:^(UIHingeInteraction *interaction,
            UIHingeInteractionUpdate *update) {
            [weakSelf.view setNeedsLayout];
#if DEBUG && TARGET_OS_SIMULATOR
            NSLog(@"SideLantern hinge: %@", update.hinge);
#endif
        }]];
    }
#if DEBUG && TARGET_OS_SIMULATOR
    if (layoutPreview) {
        self.view.backgroundColor = UIColor.blackColor;
        _previewCanvas = [[UIView alloc] init];
        _previewCanvas.backgroundColor = [UIColor colorWithRed:0.07 green:0.25 blue:0.29 alpha:1];
        _previewCanvas.accessibilityIdentifier = @"stream-layout-preview";
        [_streamView insertSubview:_previewCanvas atIndex:0];
        UILabel *caption = [[UILabel alloc] init];
        caption.text = NSLocalizedStringFromTable(@"stream.preview", @"StreamTarget", nil);
        caption.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
        caption.textColor = UIColor.whiteColor;
        caption.textAlignment = NSTextAlignmentCenter;
        caption.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_previewCanvas addSubview:caption];
        _stageLabel.hidden = _tipLabel.hidden = YES;
        [_spinner stopAnimating];
        [_streamView applyOnScreenControlsLevel:OnScreenControlsLevelFull];
        [_streamView showOnScreenControls];
    }
#endif
#endif
}

#if !TARGET_OS_TV
- (CGRect)portraitFoldRegion {
    if (@available(iOS 27.1, *)) {
        UIInterfaceOrientation orientation = self.view.window.windowScene.interfaceOrientation;
        if (!UIInterfaceOrientationIsPortrait(orientation)) return CGRectNull;
        for (UIViewReservedRegion *region in [self.view reservedRegionsOfKind:UIViewReservedRegionKind.divisionRegionKind
            options:UIViewReservedRegionQueryOptionsIncludeInactive]) {
            CGRect frame = region.frame;
            // A horizontal fold divides the portrait inner display. Include the
            // inactive region so opening the hinge retains the two-area layout.
            if (CGRectGetWidth(frame) > self.view.bounds.size.width * 0.6 &&
                CGRectGetMidY(frame) > self.view.bounds.size.height * 0.2 &&
                CGRectGetMidY(frame) < self.view.bounds.size.height * 0.8) return frame;
        }
    }
    return CGRectNull;
}

- (CGRect)streamSidebarFrame {
    if (_workspace) return _workspace.sidebarFrame;
    CGRect fold = [self portraitFoldRegion];
    if (!CGRectIsNull(fold)) {
        CGFloat top = CGRectGetMaxY(fold);
        return CGRectMake(0, top, self.view.bounds.size.width, MAX(0, self.view.bounds.size.height - top));
    }
    CGFloat width = MIN(420, self.view.bounds.size.width);
    return CGRectMake(self.view.bounds.size.width - width, 0, width, self.view.bounds.size.height);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect fold = [self portraitFoldRegion];
#if DEBUG && TARGET_OS_SIMULATOR
    if (_previewCanvas) {
        NSString *geometry = [NSString stringWithFormat:@"%ld %@ fold=%@", (long)self.view.window.windowScene.interfaceOrientation,
            NSStringFromCGRect(self.view.bounds), NSStringFromCGRect(fold)];
        if (![_lastPreviewGeometry isEqualToString:geometry]) {
            _lastPreviewGeometry = geometry;
            NSLog(@"SideLantern preview geometry: %@", geometry);
            if (@available(iOS 27.1, *)) {
                for (UIViewReservedRegion *region in [self.view reservedRegionsOfKind:UIViewReservedRegionKind.divisionRegionKind
                    options:UIViewReservedRegionQueryOptionsIncludeInactive]) NSLog(@"SideLantern division: %@ active=%d", NSStringFromCGRect(region.frame), region.active);
            }
        }
    }
#endif
    BOOL separate = !CGRectIsNull(fold);
    CGRect workspaceFrame = self.view.bounds;
    UIInterfaceOrientation orientation = self.view.window.windowScene.interfaceOrientation;
    BOOL portraitPhone = self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPhone &&
        (UIInterfaceOrientationIsPortrait(orientation) ||
         (orientation == UIInterfaceOrientationUnknown && workspaceFrame.size.height > workspaceFrame.size.width));
    if (_streamView.keyboardVisible && !portraitPhone && !separate) {
        CGFloat keyboardTop = CGRectGetMaxY(_keyboardViewportGuide.layoutFrame);
        if (keyboardTop > CGRectGetMinY(workspaceFrame) &&
            keyboardTop < CGRectGetMaxY(workspaceFrame) - self.view.safeAreaInsets.bottom - 1) {
            workspaceFrame.size.height = keyboardTop - CGRectGetMinY(workspaceFrame);
        }
    }
    _workspace.view.frame = workspaceFrame;
    [_workspace updateLayoutForFoldRegion:fold settingsVisible:_settingsSidebar.visible];
    CGRect videoFrame = _workspace.videoFrame;
    if (separate != _separateControls) {
        _separateControls = separate;
        [_streamView setSeparateControlsView:separate ? _controlsSurface : nil];
    }
    [_settingsSidebar layoutInFrame:[self streamSidebarFrame]];
    CGRect buttonArea = separate ? _workspace.operationsFrame : workspaceFrame;
    if (_settingsSidebar.visible && !separate) {
        buttonArea.size.width = MAX(0, CGRectGetMinX([self streamSidebarFrame]));
    }
    buttonArea = CGRectIntersection(buttonArea, self.view.safeAreaLayoutGuide.layoutFrame);
    CGRect keyboard = self.view.keyboardLayoutGuide.layoutFrame;
    if (_streamView.keyboardVisible && keyboard.size.height > self.view.safeAreaInsets.bottom + 1 &&
        CGRectIntersectsRect(buttonArea, keyboard)) {
        buttonArea.size.height = MAX(0, CGRectGetMinY(keyboard) - CGRectGetMinY(buttonArea));
        if (buttonArea.size.height < 76) {
            buttonArea = self.view.safeAreaLayoutGuide.layoutFrame;
            buttonArea.size.height = MAX(0, CGRectGetMinY(keyboard) - CGRectGetMinY(buttonArea));
        }
    }
    _settingsFloatButton.hidden = _settingsSidebar.visible && (separate || buttonArea.size.width < 76);
    if (!CGRectIsEmpty(buttonArea)) _settingsFloatButton.movementBounds = buttonArea;
    if (_settingsSidebar.view) [self.view bringSubviewToFront:_settingsSidebar.view];
    [self.view bringSubviewToFront:_settingsFloatButton];
    _stageLabel.center = CGPointMake(CGRectGetMidX(videoFrame), CGRectGetMidY(videoFrame));
    _spinner.center = CGPointMake(CGRectGetMidX(videoFrame), CGRectGetMidY(videoFrame) - 50);
    _tipLabel.center = CGPointMake(CGRectGetMidX(videoFrame), CGRectGetMaxY(videoFrame) - 40);
#if DEBUG && TARGET_OS_SIMULATOR
    if (_previewCanvas) {
        CGFloat aspect = (CGFloat)self.streamConfig.width / MAX(1, self.streamConfig.height);
        CGSize size = _streamView.bounds.size;
        if (size.width > size.height * aspect) size.width = size.height * aspect;
        else size.height = size.width / aspect;
        _previewCanvas.frame = CGRectMake((_streamView.bounds.size.width - size.width) / 2,
            (_streamView.bounds.size.height - size.height) / 2, size.width, size.height);
        _previewCanvas.subviews.firstObject.frame = _previewCanvas.bounds;
    }
#endif
}

- (void)toggleStreamSettings {
    if (!_settingsSidebar.visible && _streamView.keyboardVisible) [_streamView hideKeyboard];
    [_streamView cancelControlTouches];
    [_settingsSidebar showForHost:self.streamConfig.settingsHost frame:[self streamSidebarFrame] streaming:YES];
    [self updateManualVideoUI];
    if (_settingsSidebar.visible) [_manualVideoController refresh];
    [self.view setNeedsLayout];
}

- (void)refreshKeyboardState { _settingsSidebar.keyboardVisible = StreamHasTextResponder(self.view); }
- (void)keyboardStateDidChange:(NSNotification *)notification { [self refreshKeyboardState]; [self.view setNeedsLayout]; }
- (void)toggleStreamKeyboard {
    if (StreamHasTextResponder(self.view)) { [self.view endEditing:YES]; [_streamView hideKeyboard]; }
    else [_streamView showKeyboard];
    [self refreshKeyboardState];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // A drag starting on the docked button must not trigger the stream's exit gesture.
    if (gestureRecognizer == _exitSwipeRecognizer && [touch.view isDescendantOfView:_settingsFloatButton]) return NO;
    if (gestureRecognizer == _exitSwipeRecognizer && _settingsSidebar.visible) return NO;
    return YES;
}

- (void)applyLiveSettings {
    TemporarySettings *settings = [[[DataManager alloc] init] getSettings];
    // Touch mode belongs to the active stream; a saved change applies only after reconnecting.
    [_streamView applyOnScreenControlsLevel:_settings.absoluteTouchMode ? OnScreenControlsLevelOff :
        (OnScreenControlsLevel)settings.onscreenControls.integerValue];
    if (_connectionStarted && settings.statsOverlay && _statsUpdateTimer == nil) {
        _statsUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
            selector:@selector(updateStatsOverlay) userInfo:nil repeats:YES];
    }
    else if (!settings.statsOverlay && _statsUpdateTimer != nil) {
        [_statsUpdateTimer invalidate];
        _statsUpdateTimer = nil;
        [self updateOverlayText:nil];
    }
}

- (void)startManualVideo {
    if (!self.streamConfig.manualVideoEnabled) return;
    HttpManager *manager = [[HttpManager alloc] initWithAddress:self.streamConfig.host httpsPort:self.streamConfig.httpsPort serverCert:self.streamConfig.serverCert];
    _manualVideoController = [[ManualVideoController alloc] initWithTransport:^(NSString *identifier, ManualVideoSettings *settings, void (^completion)(ManualVideoResponse *)) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            ManualVideoResponse *response = [[ManualVideoResponse alloc] init];
            [manager executeRequestSynchronously:[HttpRequest requestForResponse:response
                withUrlRequest:[manager newManualVideoRequestForSession:identifier settings:settings]]];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(response); });
        });
    } schedule:nil];
    __weak typeof(self) weakSelf = self;
    _manualVideoController.stateChanged = ^(ManualVideoController *controller) {
        StreamFrameViewController *stream = weakSelf;
        if (stream == nil) return;
        ManualVideoSettings *settings = controller.response.settings;
        if (controller.response.validSession) {
            [stream->_streamMan updateVideoFrameRate:(int)settings.frameRate bitrate:stream.streamConfig.bitRate];
            ManualVideoFields fields = controller.appliedFields & ~ManualVideoBitrate;
            if (fields) [[[DataManager alloc] init] saveVideoWidth:fields & ManualVideoResolution ? @(settings.width) : nil
                height:fields & ManualVideoResolution ? @(settings.height) : nil
                framerate:fields & ManualVideoFrameRate ? @(settings.frameRate) : nil
                bitrate:nil];
        }
        [stream updateManualVideoUI];
    };
    [_manualVideoController refreshWithBitrateBudget:self.streamConfig.bitRate
        audioChannels:CHANNEL_COUNT_FROM_AUDIO_CONFIGURATION(self.streamConfig.audioConfiguration)];
}

- (void)updateManualVideoUI {
    NSString *message = nil;
    if (_manualVideoController.state == ManualVideoApplying) message = NSLocalizedStringFromTable(@"manual.compact.applying", @"StreamTarget", nil);
    else if (_manualVideoController.state == ManualVideoFailed) message = NSLocalizedStringFromTable(@"manual.compact.failed", @"StreamTarget", nil);
    else if (_manualVideoController.state == ManualVideoUnavailable && _manualVideoController.response.validSession)
        message = NSLocalizedStringFromTable(@"manual.compact.unconfirmed", @"StreamTarget", nil);
    [_settingsSidebar updateManualVideoSettings:_manualVideoController.response.settings
        available:_manualVideoController.available updating:_manualVideoController.state == ManualVideoApplying
        message:message];
}
#endif

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _streamView;
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    // Only cleanup when we're being destroyed
    if (parent == nil) {
#if !TARGET_OS_TV
        [_manualVideoController cancel];
        [_settingsSidebar close];
        [_streamView cancelControlTouches];
#endif
        [_controllerSupport cleanup];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        [_streamMan stopStream];
        if (_inactivityTimer != nil) {
            [_inactivityTimer invalidate];
            _inactivityTimer = nil;
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
}

#if 0
- (void)keyboardWillShow:(NSNotification *)notification {
    _keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;

    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self->_scrollView.frame;
        frame.size.height -= self->_keyboardSize.height;
        self->_scrollView.frame = frame;
    }];
}

-(void)keyboardWillHide:(NSNotification *)notification {
    // NOTE: UIKeyboardFrameEndUserInfoKey returns a different keyboard size
    // than UIKeyboardFrameBeginUserInfoKey, so it's unsuitable for use here
    // to undo the changes made by keyboardWillShow.
    
    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self->_scrollView.frame;
        frame.size.height += self->_keyboardSize.height;
        self->_scrollView.frame = frame;
    }];
}
#endif

- (void)updateStatsOverlay {
    NSString* overlayText = [self->_streamMan getStatsOverlayText];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateOverlayText:overlayText];
    });
}

- (void)updateOverlayText:(NSString*)text {
    if (_overlayView == nil) {
        _overlayView = [[UITextView alloc] init];
#if !TARGET_OS_TV
        [_overlayView setEditable:NO];
#endif
        [_overlayView setUserInteractionEnabled:NO];
        [_overlayView setSelectable:NO];
        [_overlayView setScrollEnabled:NO];
        
        // HACK: If not using stats overlay, center the text
        if (_statsUpdateTimer == nil) {
            [_overlayView setTextAlignment:NSTextAlignmentCenter];
        }
        
        [_overlayView setTextColor:[UIColor lightGrayColor]];
        [_overlayView setBackgroundColor:[UIColor blackColor]];
#if TARGET_OS_TV
        [_overlayView setFont:[UIFont systemFontOfSize:24]];
#else
        [_overlayView setFont:[UIFont systemFontOfSize:12]];
#endif
        [_overlayView setAlpha:0.5];
        [self.view addSubview:_overlayView];
    }
    
    if (text != nil) {
        // We set our bounds to the maximum width in order to work around a bug where
        // sizeToFit interacts badly with the UITextView's line breaks, causing the
        // width to get smaller and smaller each time as more line breaks are inserted.
        [_overlayView setBounds:CGRectMake(self.view.frame.origin.x,
                                           _overlayView.frame.origin.y,
                                           self.view.frame.size.width,
                                           _overlayView.frame.size.height)];
        [_overlayView setText:text];
        [_overlayView sizeToFit];
        [_overlayView setCenter:CGPointMake(self.view.frame.size.width / 2, _overlayView.frame.size.height / 2)];
        [_overlayView setHidden:NO];
    }
    else {
        [_overlayView setHidden:YES];
    }
}

- (void) returnToMainFrame {
#if !TARGET_OS_TV
    [_manualVideoController cancel];
    [_settingsSidebar close];
#endif
    // Reset display mode back to default
    [self updatePreferredDisplayMode:NO];
    
    [_statsUpdateTimer invalidate];
    _statsUpdateTimer = nil;
    
    [self.navigationController popToRootViewControllerAnimated:YES];
}

// This will fire if the user opens control center or gets a low battery message
- (void)applicationWillResignActive:(NSNotification *)notification {
    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
    }
    
#if !TARGET_OS_TV
    // Terminate the stream if the app is inactive for 60 seconds
    Log(LOG_I, @"Starting inactivity termination timer");
    _inactivityTimer = [NSTimer scheduledTimerWithTimeInterval:60
                                                      target:self
                                                    selector:@selector(inactiveTimerExpired:)
                                                    userInfo:nil
                                                     repeats:NO];
#endif
}

- (void)inactiveTimerExpired:(NSTimer*)timer {
    Log(LOG_I, @"Terminating stream after inactivity");

    [self returnToMainFrame];
    
    _inactivityTimer = nil;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    // Stop the background timer, since we're foregrounded again
    if (_inactivityTimer != nil) {
        Log(LOG_I, @"Stopping inactivity timer after becoming active again");
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
}

// This fires when the home button is pressed
- (void)applicationDidEnterBackground:(UIApplication *)application {
    Log(LOG_I, @"Terminating stream immediately for backgrounding");

    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
    
    [self returnToMainFrame];
}

- (void)edgeSwiped {
    Log(LOG_I, @"User swiped to end stream");
    
    [self returnToMainFrame];
}

- (void) connectionStarted {
    Log(LOG_I, @"Connection started");
    dispatch_async(dispatch_get_main_queue(), ^{
#if !TARGET_OS_TV
        self->_connectionStarted = YES;
        [self startManualVideo];
#endif
        // Leave the spinner spinning until it's obscured by
        // the first frame of video.
        self->_stageLabel.hidden = YES;
        self->_tipLabel.hidden = YES;
        
        [self->_streamView showOnScreenControls];
        
        [self->_controllerSupport connectionEstablished];
        
#if !TARGET_OS_TV
        [self applyLiveSettings];
#else
        if (self->_settings.statsOverlay) {
            self->_statsUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                                                       target:self
                                                                     selector:@selector(updateStatsOverlay)
                                                                     userInfo:nil
                                                                      repeats:YES];
        }
#endif
    });
}

- (void)connectionTerminated:(int)errorCode {
    Log(LOG_I, @"Connection terminated: %d", errorCode);
    
    unsigned int portFlags = LiGetPortFlagsFromTerminationErrorCode(errorCode);
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portFlags);
    
    dispatch_async(dispatch_get_main_queue(), ^{
#if !TARGET_OS_TV
        [self->_manualVideoController cancel];
#endif
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        NSString* title;
        NSString* message;
        
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            title = @"Connection Error";
            message = @"Your device's network connection is blocking Moonlight. Streaming may not work while connected to this network.";
        }
        else {
            switch (errorCode) {
                case ML_ERROR_GRACEFUL_TERMINATION:
                    [self returnToMainFrame];
                    return;
                    
                case ML_ERROR_NO_VIDEO_TRAFFIC:
                    title = @"Connection Error";
                    message = @"No video received from host.";
                    if (portFlags != 0) {
                        char failingPorts[256];
                        LiStringifyPortFlags(portFlags, "\n", failingPorts, sizeof(failingPorts));
                        message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
                    }
                    break;
                    
                case ML_ERROR_NO_VIDEO_FRAME:
                    title = @"Connection Error";
                    message = @"Your network connection isn't performing well. Reduce your video bitrate setting or try a faster connection.";
                    break;
                    
                case ML_ERROR_UNEXPECTED_EARLY_TERMINATION:
                case ML_ERROR_PROTECTED_CONTENT:
                    title = @"Connection Error";
                    message = @"Something went wrong on your host PC when starting the stream.\n\nMake sure you don't have any DRM-protected content open on your host PC. You can also try restarting your host PC.\n\nIf the issue persists, try reinstalling your GPU drivers and GeForce Experience.";
                    break;
                    
                case ML_ERROR_FRAME_CONVERSION:
                    title = @"Connection Error";
                    message = @"The host PC reported a fatal video encoding error.\n\nTry disabling HDR mode, changing the streaming resolution, or changing your host PC's display resolution.";
                    break;
                    
                default:
                {
                    NSString* errorString;
                    if (abs(errorCode) > 1000) {
                        // We'll assume large errors are hex values
                        errorString = [NSString stringWithFormat:@"%08X", (uint32_t)errorCode];
                    }
                    else {
                        // Smaller values will just be printed as decimal (probably errno.h values)
                        errorString = [NSString stringWithFormat:@"%d", errorCode];
                    }
                    
                    title = @"Connection Terminated";
                    message = [NSString stringWithFormat: @"The connection was terminated\n\nError code: %@", errorString];
                    break;
                }
            }
        }
        
        UIAlertController* conTermAlert = [UIAlertController alertControllerWithTitle:title
                                                                              message:message
                                                                       preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:conTermAlert];
        [conTermAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:conTermAlert animated:YES completion:nil];
    });

    [_streamMan stopStream];
}

- (void) stageStarting:(const char*)stageName {
    Log(LOG_I, @"Starting %s", stageName);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* lowerCase = [NSString stringWithFormat:@"%s in progress...", stageName];
        NSString* titleCase = [[[lowerCase substringToIndex:1] uppercaseString] stringByAppendingString:[lowerCase substringFromIndex:1]];
        [self->_stageLabel setText:titleCase];
        [self->_stageLabel sizeToFit];
        self->_stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self->_stageLabel.center.y);
    });
}

- (void) stageComplete:(const char*)stageName {
}

- (void) stageFailed:(const char*)stageName withError:(int)errorCode portTestFlags:(int)portTestFlags {
    Log(LOG_I, @"Stage %s failed: %d", stageName, errorCode);
    
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portTestFlags);

    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        NSString* message = [NSString stringWithFormat:@"%s failed with error %d", stageName, errorCode];
        if (portTestFlags != 0) {
            char failingPorts[256];
            LiStringifyPortFlags(portTestFlags, "\n", failingPorts, sizeof(failingPorts));
            message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
        }
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            message = [message stringByAppendingString:@"\n\nYour device's network connection is blocking Moonlight. Streaming may not work while connected to this network."];
        }
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Connection Failed"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
    
    [_streamMan stopStream];
}

- (void) launchFailed:(NSString*)message {
    Log(LOG_I, @"Launch failed: %@", message);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Connection Error"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor {
    Log(LOG_I, @"Rumble on gamepad %d: %04x %04x", controllerNumber, lowFreqMotor, highFreqMotor);
    
    [_controllerSupport rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}

- (void) rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger {
    Log(LOG_I, @"Trigger rumble on gamepad %d: %04x %04x", controllerNumber, leftTrigger, rightTrigger);
    
    [_controllerSupport rumbleTriggers:controllerNumber leftTrigger:leftTrigger rightTrigger:rightTrigger];
}

- (void) setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz {
    Log(LOG_I, @"Set motion state on gamepad %d: %02x %u Hz", controllerNumber, motionType, reportRateHz);
    
    [_controllerSupport setMotionEventState:controllerNumber motionType:motionType reportRateHz:reportRateHz];
}

- (void) setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
    Log(LOG_I, @"Set controller LED on gamepad %d: l%02x%02x%02x", controllerNumber, r, g, b);
    
    [_controllerSupport setControllerLed:controllerNumber r:r g:g b:b];
}

- (void)connectionStatusUpdate:(int)status {
    Log(LOG_W, @"Connection status update: %d", status);

    // The stats overlay takes precedence over these warnings
    if (_statsUpdateTimer != nil) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (status) {
            case CONN_STATUS_OKAY:
                [self updateOverlayText:nil];
                break;
                
            case CONN_STATUS_POOR:
                if (self->_streamConfig.bitRate > 5000) {
                    [self updateOverlayText:@"Slow connection to PC\nReduce your bitrate"];
                }
                else {
                    [self updateOverlayText:@"Poor connection to PC"];
                }
                break;
        }
    });
}

- (void) updatePreferredDisplayMode:(BOOL)streamActive {
#if TARGET_OS_TV
    if (@available(tvOS 11.2, *)) {
        UIWindow* window = [[[UIApplication sharedApplication] delegate] window];
        AVDisplayManager* displayManager = [window avDisplayManager];
        
        // This logic comes from Kodi and MrMC
        if (streamActive) {
            int dynamicRange;
            
            if (LiGetCurrentHostDisplayHdrMode()) {
                dynamicRange = 2; // HDR10
            }
            else {
                dynamicRange = 0; // SDR
            }
            
            AVDisplayCriteria* displayCriteria = [[AVDisplayCriteria alloc] initWithRefreshRate:[_settings.framerate floatValue]
                                                                              videoDynamicRange:dynamicRange];
            displayManager.preferredDisplayCriteria = displayCriteria;
        }
        else {
            // Switch back to the default display mode
            displayManager.preferredDisplayCriteria = nil;
        }
    }
#endif
}

- (void) setHdrMode:(bool)enabled {
    Log(LOG_I, @"HDR is now: %s", enabled ? "active" : "inactive");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updatePreferredDisplayMode:YES];
    });
}

- (void) videoContentShown {
    [_spinner stopAnimating];
    [self.view setBackgroundColor:[UIColor blackColor]];
}

- (void)videoSizeChangedWithWidth:(int)width height:(int)height {
    self.streamConfig.width = width;
    self.streamConfig.height = height;
    [_streamView updateVideoWidth:width height:height];
#if !TARGET_OS_TV
    [_streamView cancelControlTouches];
#endif
    if (_scrollView.zoomScale != 1) [_scrollView setZoomScale:1 animated:NO];
    [self.view setNeedsLayout];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)gamepadPresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)mousePresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 14.0, *)) {
        [self setNeedsUpdateOfPrefersPointerLocked];
    }
#endif
}

- (void) streamExitRequested {
    Log(LOG_I, @"Gamepad combo requested stream exit");
    
    [self returnToMainFrame];
}

- (void)userInteractionBegan {
    // Disable hiding home bar when user is interacting.
    // iOS will force it to be shown anyway, but it will
    // also discard our edges deferring system gestures unless
    // we willingly give up home bar hiding preference.
    _userIsInteracting = YES;
#if !TARGET_OS_TV
    _settingsFloatButton.interactionActive = YES;
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)userInteractionEnded {
    // Enable home bar hiding again if conditions allow
    _userIsInteracting = NO;
#if !TARGET_OS_TV
    _settingsFloatButton.interactionActive = _settingsSidebar.visible;
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

#if !TARGET_OS_TV
// Require a confirmation when streaming to activate a system gesture
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
    return UIRectEdgeAll;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    if ([_controllerSupport getConnectedGamepadCount] > 0 &&
        [_streamView getCurrentOscState] == OnScreenControlsLevelOff &&
        _userIsInteracting == NO) {
        // Autohide the home bar when a gamepad is connected
        // and the on-screen controls are disabled. We can't
        // do this all the time because any touch on the display
        // will cause the home indicator to reappear, and our
        // preferredScreenEdgesDeferringSystemGestures will also
        // be suppressed (leading to possible errant exits of the
        // stream).
        return YES;
    }
    
    return NO;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (BOOL)prefersPointerLocked {
    // Pointer lock breaks the UIKit mouse APIs, which is a problem because
    // GCMouse is horribly broken on iOS 14.0 for certain mice. Only lock
    // the cursor if there is a GCMouse present.
    return [GCMouse mice].count > 0;
}
#endif

@end
