#import "SceneDelegate.h"
#import "AppDelegate.h"
#import "StreamFrameViewController.h"
#import "FileTransferPreview.h"
#import "DeviceBrowserViewController.h"
#import "SideLanternNavigationController.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) {
        return;
    }
    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    if (connectionOptions.shortcutItem != nil) {
        appDelegate.pcUuidToLoad = connectionOptions.shortcutItem.userInfo[@"UUID"];
    }

    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    // Existing streaming and orientation code obtains its window from AppDelegate.
    appDelegate.window = self.window;
    NSString *storyboardName = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"iPad" : @"iPhone";
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:storyboardName bundle:nil];
    self.window.rootViewController = [storyboard instantiateInitialViewController];
#if DEBUG && TARGET_OS_SIMULATOR
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--sidelantern-device-list-preview"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--sidelantern-device-detail-preview"]) {
        self.window.rootViewController = DeviceBrowserPreview([NSProcessInfo.processInfo.arguments containsObject:@"--sidelantern-device-detail-preview"],
            [NSProcessInfo.processInfo.arguments containsObject:@"--sidelantern-device-empty-preview"]);
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--sidelantern-file-transfer-preview"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--sidelantern-file-browser-preview"]) {
        self.window.rootViewController = FileTransferPreview([NSProcessInfo.processInfo.arguments containsObject:@"--sidelantern-file-browser-preview"]);
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--sidelantern-stream-preview"]) {
        StreamFrameViewController *stream = [storyboard instantiateViewControllerWithIdentifier:@"streamFrame"];
        StreamConfiguration *config = [[StreamConfiguration alloc] init];
        config.width = 1920; config.height = 1080; config.frameRate = 60;
        config.appName = @"SideLantern";
        stream.streamConfig = config;
        self.window.rootViewController = [[SideLanternNavigationController alloc] initWithRootViewController:stream];
    }
#endif
    [self.window makeKeyAndVisible];
#if DEBUG && TARGET_OS_SIMULATOR
    BOOL previewPortrait = [NSProcessInfo.processInfo.arguments containsObject:@"--sidelantern-preview-portrait"];
    BOOL previewLandscape = [NSProcessInfo.processInfo.arguments containsObject:@"--sidelantern-preview-landscape"];
    if (previewPortrait || previewLandscape) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIWindowSceneGeometryPreferencesIOS *geometry = [[UIWindowSceneGeometryPreferencesIOS alloc]
                initWithInterfaceOrientations:previewPortrait ? UIInterfaceOrientationMaskPortrait : UIInterfaceOrientationMaskLandscape];
            [self.window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
            [self.window.windowScene requestGeometryUpdateWithPreferences:geometry errorHandler:^(NSError *error) {
                NSLog(@"SideLantern preview orientation: %@", error);
            }];
        });
    }
#endif
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    [(AppDelegate *)UIApplication.sharedApplication.delegate saveContext];
}

- (void)windowScene:(UIWindowScene *)windowScene performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem
    completionHandler:(void (^)(BOOL))completionHandler {
    [(AppDelegate *)UIApplication.sharedApplication.delegate application:UIApplication.sharedApplication
        performActionForShortcutItem:shortcutItem completionHandler:completionHandler];
}

@end
