#import "SideLanternNavigationController.h"
#import "MainFrameViewController.h"
#import "DeviceBrowserViewController.h"
#import "StreamFrameViewController.h"

@interface SideLanternNavigationController () <UINavigationControllerDelegate>
@end

@implementation SideLanternNavigationController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.delegate = self;

    // Settings use a dark appearance. Keep the shared bar stable while each
    // content controller continues to choose its own interface style.
    self.navigationBar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.navigationBar.translucent = YES;
    self.navigationBar.backgroundColor = nil;
    self.navigationBar.barTintColor = nil;
    self.navigationBar.tintColor = UIColor.labelColor;
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithDefaultBackground];
    self.navigationBar.standardAppearance = appearance;
    self.navigationBar.scrollEdgeAppearance = appearance;
    self.navigationBar.compactAppearance = appearance;
    self.navigationBar.compactScrollEdgeAppearance = appearance;
    [self setNavigationBarHidden:[self hidesNavigationBarForViewController:self.topViewController] animated:NO];
}

- (BOOL)hidesNavigationBarForViewController:(UIViewController *)viewController {
    return [viewController isKindOfClass:MainFrameViewController.class] ||
        [viewController isKindOfClass:DeviceBrowserViewController.class] ||
        [viewController isKindOfClass:StreamFrameViewController.class];
}

- (void)navigationController:(UINavigationController *)navigationController
      willShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    // Use the transition's animation flag so UIKit coordinates the bar with
    // native push/pop, including an interactive pop's progress and rollback.
    [self setNavigationBarHidden:[self hidesNavigationBarForViewController:viewController] animated:animated];
}

- (void)navigationController:(UINavigationController *)navigationController
       didShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    // The shown controller may be the source after an interactive pop cancels.
    BOOL hidden = [self hidesNavigationBarForViewController:viewController];
    if (self.navigationBarHidden != hidden) {
        [self setNavigationBarHidden:hidden animated:NO];
    }
}

@end
