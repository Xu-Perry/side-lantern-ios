#import <UIKit/UIKit.h>
#import <unistd.h>
#import <objc/runtime.h>

// Loaded into the simulator's Debug app to exercise the production objects.
@protocol TouchCheckStream <NSObject>
@property (nonatomic, readonly) BOOL absoluteTouchMode;
- (void)applyOnScreenControlsLevel:(NSInteger)level;
- (NSInteger)getCurrentOscState;
- (void)cancelTouchInput;
- (void)updateVideoWidth:(int)width height:(int)height;
@end
@protocol TouchCheckController <NSObject>
- (void)applyLiveSettings;
- (void)toggleStreamSettings;
@end
@protocol TouchCheckData <NSObject>
- (id)getSettings;
- (void)saveAbsoluteTouchMode:(BOOL)mode;
- (void)saveLiveControls:(NSNumber *)controls statistics:(NSNumber *)statistics;
@end
@protocol DisplayCheckLaunch <NSObject>
- (void)prepareToStreamApp:(id)app;
- (void)openDesktopForHost:(id)host source:(UIView *)source target:(NSInteger)target;
@end
@protocol DisplayCheckHTTP <NSObject>
- (id)initWithAddress:(NSString *)address httpsPort:(unsigned short)port serverCert:(NSData *)cert;
- (NSURLRequest *)newLaunchOrResumeRequest:(NSString *)verb config:(id)config;
@end
@protocol DisplayCheckHeader <NSObject>
- (id)initWithFrame:(CGRect)frame;
- (void)configure:(id)host cache:(NSCache *)cache allApps:(BOOL)allApps;
@end
@protocol AppMenuCheckButton <NSObject>
- (id)initWithApp:(id)app cache:(NSCache *)cache delegate:(id)delegate;
- (void)showAppMenu:(UIGestureRecognizer *)gesture;
@end
@protocol AppMenuCheckMain <NSObject>
- (void)appLongClicked:(id)app view:(UIView *)view;
@end

@interface AppMenuCallbackRecorder : NSObject
@property (nonatomic) NSUInteger menuCount;
@end
@implementation AppMenuCallbackRecorder
- (void)appLongClicked:(id)app view:(UIView *)view { self.menuCount++; }
@end
@interface AppMenuLongPress : UILongPressGestureRecognizer
@property (nonatomic) UIGestureRecognizerState reportedState;
@end
@implementation AppMenuLongPress
- (UIGestureRecognizerState)state { return self.reportedState; }
@end
@interface AppMenuSecondaryClick : UITapGestureRecognizer
@property (nonatomic) UIGestureRecognizerState reportedState;
@end
@implementation AppMenuSecondaryClick
- (UIGestureRecognizerState)state { return self.reportedState; }
@end

@interface TouchCheckContact : NSObject
@property (nonatomic) CGPoint point;
@property (nonatomic) NSTimeInterval timestamp;
@end
@implementation TouchCheckContact
- (UITouchType)type { return UITouchTypeDirect; }
- (CGPoint)locationInView:(UIView *)view { return self.point; }
@end
@interface TouchCheckEvent : NSObject
@property (nonatomic) NSSet *allTouches;
@end
@implementation TouchCheckEvent
@end

static void Require(BOOL condition, NSString *message) {
    if (!condition) @throw [NSException exceptionWithName:@"TouchModeCheckFailed" reason:message userInfo:nil];
}
static void Wait(NSTimeInterval delay) { [NSThread sleepForTimeInterval:delay]; }
static void OnMain(void (^action)(void)) {
    __block NSException *failure;
    dispatch_sync(dispatch_get_main_queue(), ^{
        @try { action(); } @catch (NSException *exception) { failure = exception; }
    });
    if (failure) @throw failure;
}
static id Handler(id stream) { return [stream valueForKey:@"touchHandler"]; }
static BOOL Flag(id object, NSString *key) { return [[object valueForKey:key] boolValue]; }
static void Begin(id stream, TouchCheckContact *touch, TouchCheckEvent *event) {
    event.allTouches = [NSSet setWithObject:touch];
    [(UIResponder *)stream touchesBegan:(id)event.allTouches withEvent:(id)event];
}
static void End(id stream, TouchCheckContact *touch, TouchCheckEvent *event) {
    [(UIResponder *)stream touchesEnded:(id)[NSSet setWithObject:touch] withEvent:(id)event];
}
static void ChangeMode(id<TouchCheckData> data, id<TouchCheckController> controller, BOOL absolute) {
    [data saveAbsoluteTouchMode:absolute];
    [controller applyLiveSettings];
}

static NSUInteger displaySegueCount;
static void RecordSegue(id object, SEL selector, NSString *identifier, id sender) {
    Require([identifier isEqualToString:@"createStreamFrame"], @"Display entry used the wrong destination");
    displaySegueCount++;
}
static BOOL ContainsTargetSelector(UIView *view) {
    if ([view isKindOfClass:NSClassFromString(@"StreamTargetSettingsView")]) return YES;
    for (UIView *child in view.subviews) if (ContainsTargetSelector(child)) return YES;
    return NO;
}
static void CheckDisplayEntry(void) {
    id host = [NSClassFromString(@"TemporaryHost") new];
    [host setValue:@"display-entry-check" forKey:@"uuid"];
    [host setValue:@"Display entry check" forKey:@"name"];
    [host setValue:@"127.0.0.1" forKey:@"activeAddress"];
    [host setValue:@47984 forKey:@"httpsPort"];
    [host setValue:@2 forKey:@"state"]; [host setValue:@2 forKey:@"pairState"];
    id app = [NSClassFromString(@"TemporaryApp") new];
    [app setValue:@"Desktop" forKey:@"name"]; [app setValue:@"1" forKey:@"id"]; [app setValue:host forKey:@"host"];
    [host setValue:[NSSet setWithObject:app] forKey:@"appList"];
    Class mainClass = NSClassFromString(@"MainFrameViewController");
    Class testClass = objc_allocateClassPair(mainClass, "DisplayEntryCheckController", 0);
    SEL segue = @selector(performSegueWithIdentifier:sender:);
    class_addMethod(testClass, segue, (IMP)RecordSegue, method_getTypeEncoding(class_getInstanceMethod(mainClass, segue)));
    objc_registerClassPair(testClass);
    id<DisplayCheckLaunch> main = [(UICollectionViewController *)[testClass alloc] initWithCollectionViewLayout:[UICollectionViewFlowLayout new]];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id oldTarget = [defaults objectForKey:@"SideLantern.StreamTarget"];
    @try {
        [defaults setObject:@"wireless_display" forKey:@"SideLantern.StreamTarget"];
        [main prepareToStreamApp:app];
        Require([[[(id)main valueForKey:@"streamConfig"] valueForKey:@"sideLanternMode"] isEqualToString:@"primary"], @"An old saved target changed the normal desktop mode");
        id owner = [NSClassFromString(@"DeviceBrowserViewController") new];
        [owner setValue:^BOOL(id selectedHost) { return YES; } forKey:@"supportsFiles"];
        [owner setValue:^(id selectedHost, UIView *source) { [main openDesktopForHost:selectedHost source:source target:1]; } forKey:@"openSecondaryDisplay"];
        [owner setValue:^(id selectedHost, UIView *source) { [main openDesktopForHost:selectedHost source:source target:2]; } forKey:@"openWirelessDisplay"];
        id<DisplayCheckHeader> header = [(id<DisplayCheckHeader>)[NSClassFromString(@"DBDetailHeader") alloc] initWithFrame:CGRectMake(0, 0, 600, 500)];
        [(id)header setValue:owner forKey:@"owner"];
        [header configure:host cache:[NSCache new] allApps:NO];
        NSArray<UIButton *> *features = [(id)header valueForKey:@"features"];
        Require(features.count == 4 && [features[0].accessibilityIdentifier isEqualToString:@"device-feature-files"] &&
            [features[1].accessibilityIdentifier isEqualToString:@"device-feature-secondary_display"] &&
            [features[2].accessibilityIdentifier isEqualToString:@"device-feature-wireless_display"] &&
            [features[3].accessibilityIdentifier isEqualToString:@"device-feature-more"], @"The independent display entries are missing or in the wrong order");
        Require(features[1].accessibilityHint.length > 0, @"The secondary-only entry is missing its main-display behavior hint");
        id<DisplayCheckHTTP> http = [(id<DisplayCheckHTTP>)[NSClassFromString(@"HttpManager") alloc] initWithAddress:@"127.0.0.1" httpsPort:47984 serverCert:nil];
        NSArray *expectedModes = @[@"secondary", @"extend"];
        for (NSUInteger index = 0; index < expectedModes.count; index++) {
            [features[index + 1] sendActionsForControlEvents:UIControlEventTouchUpInside];
            id config = [(id)main valueForKey:@"streamConfig"];
            Require(displaySegueCount == index * 2 + 1 && [[config valueForKey:@"sideLanternMode"] isEqualToString:expectedModes[index]], @"A display entry launched the wrong mode");
            [config setValue:[NSMutableData dataWithLength:16] forKey:@"riKey"];
            for (NSString *verb in @[@"launch", @"resume"]) {
                NSURLRequest *request = [http newLaunchOrResumeRequest:verb config:config];
                NSURLComponents *components = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
                NSPredicate *mode = [NSPredicate predicateWithFormat:@"name == %@ AND value == %@", @"sidelantern_mode", expectedModes[index]];
                Require([components.queryItems filteredArrayUsingPredicate:mode].count == 1, @"A display launch/resume lost its independent mode parameter");
            }
            [main openDesktopForHost:host source:nil target:0];
            Require(displaySegueCount == index * 2 + 2 && [[[(id)main valueForKey:@"streamConfig"] valueForKey:@"sideLanternMode"] isEqualToString:@"primary"], @"A secondary display mode leaked into a later normal desktop launch");
        }
        Require([[defaults objectForKey:@"SideLantern.StreamTarget"] isEqualToString:@"wireless_display"], @"An independent display entry changed the global preference");
        [host setValue:@1 forKey:@"state"];
        [header configure:host cache:[NSCache new] allApps:NO];
        Require(!features[1].enabled && !features[2].enabled, @"Offline host retained enabled display entries");
        NSString *storyboard = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"iPad" : @"iPhone";
        UIViewController *settings = [[UIStoryboard storyboardWithName:storyboard bundle:nil] instantiateViewControllerWithIdentifier:@"settingsFrame"];
        [settings loadViewIfNeeded];
        Require(!ContainsTargetSelector(settings.view), @"Stream targets remain visible in stream settings");
        puts("Display entry runtime checks passed: primary default, Files/Secondary only/Wireless display/More order, independent secondary and extend launch/resume parameters, offline behavior, and no preference or mode leakage.");
    } @finally {
        if (oldTarget) [defaults setObject:oldTarget forKey:@"SideLantern.StreamTarget"];
        else [defaults removeObjectForKey:@"SideLantern.StreamTarget"];
    }
}

static void CheckAppMenus(void) {
    __block UIViewController *presenter;
    __block UIButton<AppMenuCheckButton> *button;
    __block id<AppMenuCheckMain> main;
    __block id app;
    __block UIAlertController *firstMenu;
    dispatch_semaphore_t dismissalFinished = dispatch_semaphore_create(0);
    OnMain(^{
        id host = [NSClassFromString(@"TemporaryHost") new];
        [host setValue:@"app-menu-check" forKey:@"uuid"]; [host setValue:@"App menu check" forKey:@"name"];
        [host setValue:@2 forKey:@"state"]; [host setValue:@2 forKey:@"pairState"];
        app = [NSClassFromString(@"TemporaryApp") new];
        [app setValue:@"Menu test app" forKey:@"name"]; [app setValue:@"101" forKey:@"id"]; [app setValue:host forKey:@"host"];
        [host setValue:[NSSet setWithObject:app] forKey:@"appList"];
        AppMenuCallbackRecorder *recorder = [AppMenuCallbackRecorder new];
        button = [(id<AppMenuCheckButton>)[NSClassFromString(@"DBAppButton") alloc] initWithApp:app cache:[NSCache new] delegate:recorder];
        AppMenuLongPress *longPress = [AppMenuLongPress new];
        for (NSNumber *state in @[@(UIGestureRecognizerStatePossible), @(UIGestureRecognizerStateBegan), @(UIGestureRecognizerStateChanged), @(UIGestureRecognizerStateChanged), @(UIGestureRecognizerStateEnded)]) {
            longPress.reportedState = state.integerValue;
            [button showAppMenu:longPress];
        }
        Require(recorder.menuCount == 1, @"One held long press requested multiple app menus");
        AppMenuSecondaryClick *secondaryClick = [AppMenuSecondaryClick new];
        secondaryClick.reportedState = UIGestureRecognizerStateRecognized;
        [button showAppMenu:secondaryClick];
        Require(recorder.menuCount == 2, @"Mouse right click no longer requests the app menu");
        button.enabled = NO; longPress.reportedState = UIGestureRecognizerStateBegan;
        [button showAppMenu:longPress];
        Require(recorder.menuCount == 2, @"A disabled app requested its menu");
        main = [(UICollectionViewController *)[NSClassFromString(@"MainFrameViewController") alloc] initWithCollectionViewLayout:[UICollectionViewFlowLayout new]];
        UIWindow *window = ((UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject).windows.firstObject;
        presenter = window.rootViewController;
        button.enabled = YES;
        button.frame = CGRectMake(20, 20, 130, 170);
        [presenter.view addSubview:button];
        for (NSUInteger index = 0; index < 5; index++) [main appLongClicked:app view:button];
        firstMenu = (id)presenter.presentedViewController;
        Require([firstMenu isKindOfClass:UIAlertController.class] && [[(id)main valueForKey:@"appActionMenu"] isEqual:firstMenu], @"The app menu was not registered before presentation");
        Require(firstMenu.presentedViewController == nil, @"Rapid long presses stacked app menus during presentation");
    });
    @try {
        Wait(1);
        OnMain(^{
            for (NSUInteger index = 0; index < 5; index++) [main appLongClicked:app view:button];
            Require(presenter.presentedViewController == firstMenu && firstMenu.presentedViewController == nil, @"Repeated long presses stacked menus over the visible menu");
            [presenter dismissViewControllerAnimated:YES completion:^{ dispatch_semaphore_signal(dismissalFinished); }];
            [main appLongClicked:app view:button];
            Require([[(id)main valueForKey:@"appActionMenu"] isEqual:firstMenu], @"A second menu opened during dismissal");
        });
        Require(dispatch_semaphore_wait(dismissalFinished, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0, @"The app menu dismissal did not finish");
        OnMain(^{
            Require(presenter.presentedViewController == nil, @"The app menu did not dismiss");
            [main appLongClicked:app view:button];
            Require(presenter.presentedViewController != nil && presenter.presentedViewController != firstMenu && presenter.presentedViewController.presentedViewController == nil, @"The app menu could not reopen after dismissal");
        });
        Wait(0.5);
        puts("App menu runtime checks passed: one request per held long press, right click, disabled apps, rapid repeats during presentation and display, dismissal guard, and reopening.");
    } @finally {
        OnMain(^{ [presenter dismissViewControllerAnimated:NO completion:nil]; [button removeFromSuperview]; });
    }
}

static void Check(void) {
    __block id<TouchCheckController> controller;
    __block id<TouchCheckStream> stream;
    __block UIScrollView *viewport;
    __block id streamManager;
    __block id<TouchCheckData> data;
    __block BOOL savedMode;
    __block NSNumber *savedControls;
    __block id sidebar, settings, absolute, relative;
    __block UISegmentedControl *selector, *controls;
    __block TouchCheckContact *touch;
    __block TouchCheckEvent *event;
    __block NSUInteger generation;
    OnMain(^{
        UIWindow *window = ((UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject).windows.firstObject;
        UINavigationController *navigation = (id)window.rootViewController;
        controller = (id)navigation.topViewController;
        stream = [(id)controller valueForKey:@"streamView"];
        viewport = [(id)controller valueForKey:@"scrollView"];
        streamManager = [(id)controller valueForKey:@"streamMan"];
        data = [NSClassFromString(@"DataManager") new];
        id saved = [data getSettings];
        savedMode = Flag(saved, @"absoluteTouchMode");
        savedControls = [saved valueForKey:@"onscreenControls"];
        Require(stream != nil && viewport != nil, @"Preview must contain the production stream and viewport");
    });
    @try {
        OnMain(^{
            [data saveLiveControls:@0 statistics:nil];
            ChangeMode(data, controller, YES);
            Require(stream.absoluteTouchMode && Flag([data getSettings], @"absoluteTouchMode"), @"Touchscreen mode did not save/apply");
            Require(viewport.scrollEnabled && viewport.panGestureRecognizer.enabled && viewport.pinchGestureRecognizer.enabled, @"Touchscreen zoom gestures were not enabled");
            Require(!viewport.delaysContentTouches && ((UIView *)stream).multipleTouchEnabled, @"Touch delivery is delayed or limited to one finger");
            [controller toggleStreamSettings];
            sidebar = [(id)controller valueForKey:@"settingsSidebar"];
            settings = [sidebar valueForKey:@"settings"];
            selector = [settings valueForKey:@"touchModeSelector"];
            controls = [settings valueForKey:@"onscreenControlSelector"];
            Require(selector.window != nil && selector.numberOfSegments == 2 && selector.selectedSegmentIndex == 1, @"The two existing touch modes are missing from live settings");
            Require(controls.window == nil, @"On-screen controls should be hidden in touchscreen mode");
            selector.selectedSegmentIndex = 0;
            [selector sendActionsForControlEvents:UIControlEventValueChanged];
        });
        Wait(0.1);
        OnMain(^{
            Require(!stream.absoluteTouchMode && !Flag([data getSettings], @"absoluteTouchMode"), @"The live setting did not switch/save touchpad mode");
            Require(controls.window != nil && controls.enabled && Flag(sidebar, @"onScreenControlsAvailable"), @"Controls did not return after switching to touchpad mode");
            selector.selectedSegmentIndex = 1;
            [selector sendActionsForControlEvents:UIControlEventValueChanged];
        });
        Wait(0.1);
        OnMain(^{
            Require(stream.absoluteTouchMode && controls.window == nil, @"Switching back did not hide controls immediately");
            [controller toggleStreamSettings];
            touch = [TouchCheckContact new];
            touch.point = CGPointMake(CGRectGetMidX(((UIView *)stream).bounds), CGRectGetMidY(((UIView *)stream).bounds));
            touch.timestamp = NSProcessInfo.processInfo.systemUptime;
            event = [TouchCheckEvent new];
            Begin(stream, touch, event);
            absolute = Handler(stream);
            Require(Flag(absolute, @"leftButtonDown") && [absolute valueForKey:@"longPressTimer"] != nil, @"Touchscreen press/long-press did not start");
            ChangeMode(data, controller, NO);
            Require(!Flag(absolute, @"leftButtonDown") && !Flag(absolute, @"rightButtonDown") && [absolute valueForKey:@"longPressTimer"] == nil, @"Switching left an absolute mouse button or timer active");
        });
        Wait(0.7);
        OnMain(^{
            Require(!Flag(absolute, @"rightButtonDown"), @"A cancelled long press fired after mode switch");
            [(UIResponder *)stream touchesMoved:(id)event.allTouches withEvent:(id)event];
            End(stream, touch, event);
            Require([Handler(stream) valueForKey:@"dragTimer"] == nil && [[(id)stream valueForKey:@"cancelledTouchInput"] count] == 0, @"The old finger was accepted by the new mode or never cleared");
            [stream applyOnScreenControlsLevel:0];
            Begin(stream, touch, event);
            relative = Handler(stream);
            [(NSTimer *)[relative valueForKey:@"dragTimer"] fire];
            Require(Flag(relative, @"isDragging"), @"Touchpad drag did not start");
            ChangeMode(data, controller, YES);
            Require(!Flag(relative, @"isDragging") && [relative valueForKey:@"dragTimer"] == nil, @"Switching did not release the touchpad drag");
            End(stream, touch, event);
            ChangeMode(data, controller, NO);
            [stream applyOnScreenControlsLevel:0];
            Begin(stream, touch, event); End(stream, touch, event);
            relative = Handler(stream);
            Require([[relative valueForKey:@"pendingClickButton"] integerValue] != 0, @"Touchpad tap did not schedule its release");
            ChangeMode(data, controller, YES);
            generation = [[relative valueForKey:@"clickGeneration"] unsignedIntegerValue];
            Require([[relative valueForKey:@"pendingClickButton"] integerValue] == 0, @"Switching did not release the pending tap");
            Begin(stream, touch, event);
            absolute = Handler(stream);
        });
        Wait(0.15);
        OnMain(^{
            Require([[relative valueForKey:@"clickGeneration"] unsignedIntegerValue] == generation && Flag(absolute, @"leftButtonDown"), @"The old click callback affected the new gesture");
            [(NSTimer *)[absolute valueForKey:@"longPressTimer"] fire];
            Require(Flag(absolute, @"rightButtonDown") && !Flag(absolute, @"leftButtonDown"), @"Touchscreen long press did not start a right click");
            [stream cancelTouchInput];
            Require(!Flag(absolute, @"rightButtonDown"), @"Cancelling did not release the long-press right click");
            End(stream, touch, event);
            Begin(stream, touch, event);
            [stream updateVideoWidth:1080 height:1920];
            Require(!Flag(Handler(stream), @"leftButtonDown") && [Handler(stream) valueForKey:@"longPressTimer"] == nil, @"Resolution change left a touch active");
            End(stream, touch, event);
            [stream updateVideoWidth:1920 height:1080];
            Begin(stream, touch, event);
            CGRect originalBounds = ((UIView *)stream).bounds;
            ((UIView *)stream).bounds = CGRectInset(originalBounds, 0, 12);
            [(UIView *)stream layoutIfNeeded];
            Require(!Flag(Handler(stream), @"leftButtonDown"), @"Viewport change left a touch active");
            End(stream, touch, event);
            ((UIView *)stream).bounds = originalBounds;
            [data saveLiveControls:@3 statistics:nil];
            for (NSUInteger index = 0; index < 6; index++) {
                ChangeMode(data, controller, YES);
                Require([stream getCurrentOscState] == 0, @"Touchscreen mode enabled virtual controls");
                [viewport setZoomScale:2 animated:NO];
                ChangeMode(data, controller, NO);
                Require(viewport.zoomScale == 1 && CGPointEqualToPoint(viewport.contentOffset, CGPointZero), @"Switching did not reset zoom and pan");
                Require(!viewport.scrollEnabled && !viewport.panGestureRecognizer.enabled && !viewport.pinchGestureRecognizer.enabled, @"Touchpad mode retained local zoom/pan gestures");
                Require([stream getCurrentOscState] == 3, @"Touchpad mode did not restore the saved controls level");
                Require([(id)controller valueForKey:@"streamView"] == (id)stream && [(id)controller valueForKey:@"scrollView"] == viewport && [(id)controller valueForKey:@"streamMan"] == streamManager, @"Switching recreated the stream or renderer owner");
            }
            CheckDisplayEntry();
        });
        CheckAppMenus();
        puts("Touch mode runtime checks passed: live settings, save/reload, controls visibility, long-press/drag/tap cancellation, stale fingers, resolution/layout changes, zoom reset, and six switches without recreating the stream.");
    } @finally {
        OnMain(^{
            [stream cancelTouchInput];
            [data saveLiveControls:savedControls statistics:nil];
            [data saveAbsoluteTouchMode:savedMode];
            [controller applyLiveSettings];
        });
    }
}

__attribute__((constructor)) static void StartTouchCheck(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try { Check(); fflush(stdout); _exit(0); }
        @catch (NSException *exception) { fprintf(stderr, "Touch mode check failed: %s\n", exception.description.UTF8String); fflush(stderr); _exit(1); }
    });
}
