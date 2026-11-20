#import "StreamSettingsContainerViewController.h"
#import "SettingsViewController.h"

static NSString *SidebarText(NSString *key) {
    return NSLocalizedStringFromTable(key, @"StreamTarget", nil);
}

@interface StreamSettingsDismissMask : UIButton
@property (nonatomic) CGRect excludedFrame;
@end
@implementation StreamSettingsDismissMask
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return !CGRectContainsPoint(self.excludedFrame, point) && [super pointInside:point withEvent:event];
}
@end

static void PinSidebarView(UIView *view, UIView *parent) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:parent.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor],
        [view.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor]]];
}

@interface StreamSettingsActionsViewController : UIViewController
@property (nonatomic, copy) NSString *sectionTitle;
@property (nonatomic, copy) void (^exitHandler)(void);
@end

@implementation StreamSettingsActionsViewController {
    UILabel *_titleLabel;
    NSLayoutConstraint *_top;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.accessibilityIdentifier = @"sidebar-session-actions";
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = self.sectionTitle;
    _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
    _titleLabel.adjustsFontForContentSizeCategory = YES;
    _titleLabel.numberOfLines = 0;
    _titleLabel.textColor = UIColor.labelColor;
    _titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;

    UIButton *exit = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration = [UIButtonConfiguration tintedButtonConfiguration];
    configuration.title = SidebarText(@"sidebar.exit_stream");
    configuration.image = [UIImage systemImageNamed:@"rectangle.portrait.and.arrow.right"];
    configuration.imagePadding = 6;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(8, 10, 8, 10);
    configuration.baseForegroundColor = UIColor.systemRedColor;
    configuration.baseBackgroundColor = UIColor.systemRedColor;
    configuration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attributes) {
        NSMutableDictionary *updated = [attributes mutableCopy];
        updated[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        return updated;
    };
    exit.configuration = configuration;
    exit.titleLabel.numberOfLines = 2;
    exit.titleLabel.adjustsFontForContentSizeCategory = YES;
    exit.accessibilityIdentifier = @"sidebar-exit-stream";
    exit.accessibilityLabel = configuration.title;
    exit.accessibilityHint = SidebarText(@"sidebar.exit_stream_hint");
    [exit.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [exit addTarget:self action:@selector(exitStream:) forControlEvents:UIControlEventTouchUpInside];
    [exit setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, exit]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 8;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:row];
    _top = [row.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12];
    [NSLayoutConstraint activateConstraints:@[
        _top,
        [row.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [row.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-12]]];
}

- (void)setSectionTitle:(NSString *)sectionTitle {
    _sectionTitle = [sectionTitle copy];
    _titleLabel.text = sectionTitle;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    BOOL landscape = UIInterfaceOrientationIsLandscape(self.view.window.windowScene.interfaceOrientation);
    _top.constant = 12 + (landscape ? 0 : self.view.safeAreaInsets.top);
}

- (void)exitStream:(UIButton *)sender {
    if (self.exitHandler == nil) return;
    sender.enabled = NO;
    self.exitHandler();
}
@end

@interface StreamSettingsMenuViewController : UIViewController
@property (nonatomic) NSInteger selectedIndex;
@property (nonatomic, copy) void (^selectionChanged)(NSInteger index);
@end

@implementation StreamSettingsMenuViewController {
    NSArray<UIButton *> *_buttons;
    NSLayoutConstraint *_top;
    NSLayoutConstraint *_bottom;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    self.view.accessibilityIdentifier = @"sidebar-function-menu";
    NSArray *titles = @[SidebarText(@"sidebar.stream"), SidebarText(@"sidebar.keyboard"), SidebarText(@"sidebar.desktop")];
    NSArray *symbols = @[@"play.rectangle", @"keyboard", @"macwindow"];
    NSArray *identifiers = @[@"sidebar-tab-stream", @"sidebar-tab-keyboard", @"sidebar-tab-desktop"];
    NSMutableArray *buttons = [[NSMutableArray alloc] init];
    for (NSInteger index = 0; index < titles.count; index++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = index;
        button.layer.cornerRadius = 12;
        button.accessibilityIdentifier = identifiers[index];
        button.accessibilityLabel = titles[index];
        [button addTarget:self action:@selector(selectTab:) forControlEvents:UIControlEventTouchUpInside];
        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbols[index]]];
        icon.tintColor = UIColor.whiteColor;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        [icon.heightAnchor constraintEqualToConstant:22].active = YES;
        [icon.widthAnchor constraintEqualToConstant:24].active = YES;
        UILabel *label = [[UILabel alloc] init];
        label.text = titles[index];
        label.textColor = UIColor.whiteColor;
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        label.adjustsFontForContentSizeCategory = YES;
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 2;
        label.isAccessibilityElement = NO;
        UIStackView *item = [[UIStackView alloc] initWithArrangedSubviews:@[icon, label]];
        item.axis = UILayoutConstraintAxisVertical;
        item.alignment = UIStackViewAlignmentCenter;
        item.spacing = 6;
        item.userInteractionEnabled = NO;
        item.translatesAutoresizingMaskIntoConstraints = NO;
        [button addSubview:item];
        [NSLayoutConstraint activateConstraints:@[
            [item.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
            [item.topAnchor constraintGreaterThanOrEqualToAnchor:button.topAnchor constant:4],
            [item.bottomAnchor constraintLessThanOrEqualToAnchor:button.bottomAnchor constant:-4],
            [item.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:2],
            [item.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-2],
            [button.heightAnchor constraintGreaterThanOrEqualToConstant:72]]];
        [buttons addObject:button];
    }
    _buttons = buttons;
    UIStackView *menu = [[UIStackView alloc] initWithArrangedSubviews:_buttons];
    menu.axis = UILayoutConstraintAxisVertical;
    menu.spacing = 8;
    menu.translatesAutoresizingMaskIntoConstraints = NO;
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    scroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:scroll];
    [scroll addSubview:menu];
    _top = [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:8];
    _bottom = [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8];
    [NSLayoutConstraint activateConstraints:@[
        _top, _bottom,
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [menu.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [menu.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:6],
        [menu.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-6],
        [menu.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [menu.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-12]]];
    [self updateSelection];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    BOOL landscape = UIInterfaceOrientationIsLandscape(self.view.window.windowScene.interfaceOrientation);
    _top.constant = 8 + MAX(self.view.safeAreaInsets.top, landscape ? 24 : 0);
    _bottom.constant = -(8 + (landscape ? 0 : self.view.safeAreaInsets.bottom));
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self updateSelection];
}

- (void)updateSelection {
    for (UIButton *button in _buttons) {
        BOOL selected = button.tag == self.selectedIndex;
        button.backgroundColor = selected ? [UIColor colorWithRed:0.45 green:0.36 blue:0.78 alpha:1] : UIColor.clearColor;
        button.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    }
}

- (void)selectTab:(UIButton *)sender {
    if (self.selectionChanged) self.selectionChanged(sender.tag);
}
@end

@interface StreamSettingsPlaceholderViewController : UIViewController
@end

@implementation StreamSettingsPlaceholderViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = UIColor.secondaryLabelColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.text = [NSString stringWithFormat:@"%@\n%@", self.title, SidebarText(@"sidebar.pending")];
    label.accessibilityIdentifier = @"sidebar-pending";
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [label.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20]]];
}
@end

@implementation StreamSettingsContainerViewController {
    UIStoryboard *_settingsStoryboard;
    TemporaryHost *_host;
    UIView *_panel;
    UIView *_contentHost;
    CGRect _sidebarFrame;
    StreamSettingsActionsViewController *_actions;
    StreamSettingsMenuViewController *_menu;
    NSArray<UIViewController *> *_pages;
    UIViewController *_contentController;
    StreamSettingsDismissMask *_dismissMask;
}

- (instancetype)initWithStoryboard:(UIStoryboard *)storyboard host:(TemporaryHost *)host {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _settingsStoryboard = storyboard;
        _host = host;
        _onScreenControlsAvailable = YES;
    }
    return self;
}

- (void)loadView {
    self.view = [[UIView alloc] init];
    self.view.backgroundColor = UIColor.clearColor;
    self.view.opaque = NO;
    self.view.accessibilityIdentifier = @"stream-settings-container";
    self.view.accessibilityViewIsModal = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    StreamSettingsDismissMask *mask = [[StreamSettingsDismissMask alloc] initWithFrame:CGRectZero];
    _dismissMask = mask;
    mask.backgroundColor = UIColor.clearColor;
    mask.accessibilityIdentifier = @"settings-dismiss-mask";
    mask.accessibilityLabel = SidebarText(@"settings.close");
    [mask addTarget:self action:@selector(dismissSettings) forControlEvents:UIControlEventTouchUpInside];

    _panel = [[UIView alloc] init];
    _panel.frame = _sidebarFrame;
    _panel.backgroundColor = UIColor.blackColor;
    _panel.clipsToBounds = YES;
    _panel.accessibilityIdentifier = @"settings-sidebar";
    _panel.layer.borderWidth = 1;
    _panel.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1].CGColor;
    [self.view addSubview:_panel];
    _contentHost = [[UIView alloc] init];
    _contentHost.translatesAutoresizingMaskIntoConstraints = NO;
    _contentHost.clipsToBounds = YES;
    [_panel addSubview:_contentHost];

    __weak typeof(self) weakSelf = self;
    _actions = [[StreamSettingsActionsViewController alloc] init];
    _actions.sectionTitle = SidebarText(@"settings.title");
    _actions.exitHandler = ^{ if (weakSelf.exitStreamHandler) weakSelf.exitStreamHandler(); };
    _menu = [[StreamSettingsMenuViewController alloc] init];
    _menu.selectionChanged = ^(NSInteger index) { [weakSelf selectSection:index]; };
    [self addChildViewController:_actions];
    [_panel addSubview:_actions.view];
    _actions.view.translatesAutoresizingMaskIntoConstraints = NO;
    [_actions didMoveToParentViewController:self];
    [self addChildViewController:_menu];
    [_panel addSubview:_menu.view];
    _menu.view.translatesAutoresizingMaskIntoConstraints = NO;
    [_menu didMoveToParentViewController:self];
    [NSLayoutConstraint activateConstraints:@[
        [_menu.view.topAnchor constraintEqualToAnchor:_panel.topAnchor],
        [_menu.view.bottomAnchor constraintEqualToAnchor:_panel.bottomAnchor],
        [_menu.view.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor],
        [_menu.view.widthAnchor constraintEqualToConstant:76],
        [_actions.view.topAnchor constraintEqualToAnchor:_panel.topAnchor],
        [_actions.view.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor],
        [_actions.view.trailingAnchor constraintEqualToAnchor:_menu.view.leadingAnchor],
        [_contentHost.topAnchor constraintEqualToAnchor:_actions.view.bottomAnchor],
        [_contentHost.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor],
        [_contentHost.trailingAnchor constraintEqualToAnchor:_menu.view.leadingAnchor],
        [_contentHost.bottomAnchor constraintEqualToAnchor:_panel.bottomAnchor]]];

    _settings = [_settingsStoryboard instantiateViewControllerWithIdentifier:@"settingsFrame"];
    _settings.streaming = YES;
    _settings.onScreenControlsAvailable = self.onScreenControlsAvailable;
    [_settings configureStreamTargetsForHost:_host];
    _settings.changeHandler = ^{ if (weakSelf.settingsChanged) weakSelf.settingsChanged(); };
    _settings.videoSettingsChanged = ^(ManualVideoSettings *settings, ManualVideoFields fields) {
        if (weakSelf.videoSettingsChanged) weakSelf.videoSettingsChanged(settings, fields);
    };
    StreamSettingsPlaceholderViewController *keyboard = [[StreamSettingsPlaceholderViewController alloc] init];
    keyboard.title = SidebarText(@"sidebar.keyboard");
    StreamSettingsPlaceholderViewController *desktop = [[StreamSettingsPlaceholderViewController alloc] init];
    desktop.title = SidebarText(@"sidebar.desktop");
    _pages = @[_settings, keyboard, desktop];
    [self selectSection:0];
}

- (void)selectSection:(NSInteger)index {
    if (index < 0 || index >= _pages.count) return;
    UIViewController *page = _pages[index];
    if (page == _contentController) return;
    if (_contentController == _settings) {
        [self saveSettings];
        if (self.settingsChanged) self.settingsChanged();
    }
    [_contentController willMoveToParentViewController:nil];
    [_contentController.view removeFromSuperview];
    [_contentController removeFromParentViewController];
    [self addChildViewController:page];
    [_contentHost addSubview:page.view];
    page.view.clipsToBounds = YES;
    page.view.accessibilityIdentifier = index == 0 ? @"sidebar-stream-settings" : @"sidebar-placeholder";
    PinSidebarView(page.view, _contentHost);
    [page didMoveToParentViewController:self];
    _contentController = page;
    _menu.selectedIndex = index;
    _actions.sectionTitle = index == 0 ? SidebarText(@"settings.title") : page.title;
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, page.view);
}

- (void)layoutSidebarInFrame:(CGRect)frame {
    _sidebarFrame = frame;
    _panel.frame = frame;
    [self.viewIfLoaded setNeedsLayout];
}

- (UIView *)dismissMaskView { return _dismissMask; }

- (void)placeDismissMaskInView:(UIView *)view excludingFrame:(CGRect)frame {
    if (_dismissMask.superview != view) [view addSubview:_dismissMask];
    _dismissMask.frame = view.bounds;
    _dismissMask.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dismissMask.excludedFrame = frame;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _panel.frame = _sidebarFrame;
    _settings.usesFullBounds = UIInterfaceOrientationIsLandscape(self.view.window.windowScene.interfaceOrientation);
}

- (void)saveSettings {
    if (_settings.isViewLoaded) [_settings saveSettings];
}

- (void)updateManualVideoSettings:(ManualVideoSettings *)settings available:(BOOL)available updating:(BOOL)updating message:(NSString *)message {
    [_settings updateManualVideoSettings:settings available:available updating:updating message:message];
}

- (void)dismissSettings {
    if (self.dismissHandler) self.dismissHandler();
}

- (BOOL)accessibilityPerformEscape {
    [self dismissSettings];
    return YES;
}
@end
