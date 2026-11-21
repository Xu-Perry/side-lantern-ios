#import "DeviceBrowserViewController.h"
#import "FileTransferManager.h"
#import <QuartzCore/QuartzCore.h>

static NSString *DBText(NSString *key) { return NSLocalizedStringFromTable(key, @"Devices", nil); }
static UIColor *DBBackground(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithRed:0.055 green:0.065 blue:0.075 alpha:1] :
            [UIColor colorWithRed:0.944 green:0.963 blue:0.969 alpha:1];
    }];
}
static CGFloat DBLandscapeTopInset(UIView *view) {
    UIInterfaceOrientation orientation = view.window.windowScene.interfaceOrientation;
    BOOL landscape = UIInterfaceOrientationIsLandscape(orientation) ||
        (orientation == UIInterfaceOrientationUnknown && view.bounds.size.width > view.bounds.size.height);
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone || !landscape) return 0;
    return MAX(0, 32 - view.safeAreaInsets.top);
}
static NSString *DBQuickKey(TemporaryHost *host) { return [@"SideLantern.QuickLaunch." stringByAppendingString:host.uuid]; }
static NSArray<TemporaryApp *> *DBApps(TemporaryHost *host) { return [[host.appList allObjects] sortedArrayUsingSelector:@selector(compareName:)]; }
static NSArray<NSString *> *DBSelectedApps(TemporaryHost *host) {
    id saved = [NSUserDefaults.standardUserDefaults objectForKey:DBQuickKey(host)];
    if ([saved isKindOfClass:NSArray.class]) {
        NSMutableArray *ids = [NSMutableArray array]; for (id identifier in saved) if ([identifier isKindOfClass:NSString.class]) [ids addObject:identifier]; return ids;
    }
    TemporaryApp *desktop = [DeviceBrowserViewController desktopApplicationForHost:host]; NSMutableArray *ids = [NSMutableArray array];
    for (TemporaryApp *app in DBApps(host)) if (!app.hidden && app != desktop && app.id.length) [ids addObject:app.id]; return ids;
}
static UIImage *DBArtwork(TemporaryHost *host, NSCache *cache) {
    TemporaryApp *desktop = [DeviceBrowserViewController desktopApplicationForHost:host]; UIImage *image = desktop ? [cache objectForKey:desktop] : nil;
    if ((image.size.width == 130 && image.size.height == 180) || (image.size.width == 628 && image.size.height == 888)) return nil;
    return image;
}
static UIButton *DBIconButton(NSString *icon, NSString *label, UIActionHandler handler) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setImage:[UIImage systemImageNamed:icon] forState:UIControlStateNormal];
    button.tintColor = UIColor.labelColor; button.accessibilityLabel = label;
    [button addAction:[UIAction actionWithHandler:handler] forControlEvents:UIControlEventTouchUpInside];
    return button;
}

@interface DBStatusView : UIView
- (void)update:(TemporaryHost *)host;
@end
@implementation DBStatusView {
    UILabel *_label; UIView *_dot;
}
- (instancetype)init {
    if ((self = [super init])) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72]; self.layer.cornerRadius = 12; self.userInteractionEnabled = NO;
        _label = [[UILabel alloc] init]; _label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; _label.textColor = UIColor.whiteColor;
        _dot = [[UIView alloc] init]; _dot.layer.cornerRadius = 4; [self addSubview:_dot]; [self addSubview:_label];
    } return self;
}
- (void)update:(TemporaryHost *)host {
    _label.text = DBText(host.state == StateOnline ? @"online" : host.state == StateOffline ? @"offline" : @"connecting");
    _dot.backgroundColor = host.state == StateOnline ? UIColor.systemGreenColor : host.state == StateOffline ? UIColor.systemGrayColor : UIColor.systemOrangeColor;
    [self invalidateIntrinsicContentSize]; [self setNeedsLayout];
}
- (CGSize)intrinsicContentSize { return CGSizeMake([_label sizeThatFits:CGSizeMake(CGFLOAT_MAX, 24)].width + 28, 25); }
- (void)layoutSubviews { [super layoutSubviews]; _dot.frame = CGRectMake(8, (self.bounds.size.height - 8) / 2, 8, 8); _label.frame = CGRectMake(21, 0, MAX(0, self.bounds.size.width - 26), self.bounds.size.height); }
@end

@interface DBCoverView : UIView
- (void)showImage:(UIImage *)image;
@end
@implementation DBCoverView {
    UIImageView *_image, *_computer; CAGradientLayer *_gradient;
}
- (instancetype)init {
    if ((self = [super init])) {
        self.clipsToBounds = YES; self.userInteractionEnabled = NO;
        _gradient = [CAGradientLayer layer]; _gradient.colors = @[(id)[UIColor colorWithRed:0.04 green:0.30 blue:0.35 alpha:1].CGColor,
            (id)[UIColor colorWithRed:0.15 green:0.40 blue:0.62 alpha:1].CGColor]; _gradient.startPoint = CGPointZero; _gradient.endPoint = CGPointMake(1, 1); [self.layer addSublayer:_gradient];
        _computer = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"desktopcomputer"]]; _computer.tintColor = [UIColor colorWithWhite:1 alpha:0.75]; _computer.contentMode = UIViewContentModeScaleAspectFit; [self addSubview:_computer];
        _image = [[UIImageView alloc] init]; _image.contentMode = UIViewContentModeScaleAspectFill; _image.clipsToBounds = YES; [self addSubview:_image];
    } return self;
}
- (void)showImage:(UIImage *)image { _image.image = image; _image.hidden = image == nil; _computer.hidden = image != nil; }
- (void)layoutSubviews { [super layoutSubviews]; _gradient.frame = self.bounds; _image.frame = self.bounds;
    CGFloat width = MIN(150, self.bounds.size.width * 0.58), height = MIN(100, self.bounds.size.height * 0.6);
    _computer.frame = CGRectMake((self.bounds.size.width - width) / 2, (self.bounds.size.height - height) / 2, width, height);
}
@end

@interface DBDeviceCard : UIButton <UIContextMenuInteractionDelegate>
- (instancetype)initWithHost:(TemporaryHost *)host cache:(NSCache *)cache delegate:(id<HostCallback>)delegate;
@end
@implementation DBDeviceCard {
    TemporaryHost *_host; DBCoverView *_cover; DBStatusView *_status; UILabel *_name, *_pair;
    UIImageView *_system, *_arrow; __weak id<HostCallback> _delegate;
}
- (instancetype)initWithHost:(TemporaryHost *)host cache:(NSCache *)cache delegate:(id<HostCallback>)delegate {
    if ((self = [super init])) {
        _host = host; _delegate = delegate; self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor; self.layer.cornerRadius = 14; self.clipsToBounds = YES;
        _cover = [[DBCoverView alloc] init]; [_cover showImage:DBArtwork(host, cache)]; [self addSubview:_cover];
        _status = [[DBStatusView alloc] init]; [_status update:host]; [self addSubview:_status];
        _name = [[UILabel alloc] init]; _name.text = host.name; _name.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3]; _name.textColor = UIColor.labelColor;
        _name.lineBreakMode = NSLineBreakByTruncatingTail; _name.userInteractionEnabled = NO; [self addSubview:_name];
        _pair = [[UILabel alloc] init]; _pair.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; _pair.textColor = UIColor.secondaryLabelColor;
        _pair.text = DBText(host.pairState == PairStatePaired ? @"paired" : @"pair_device"); _pair.userInteractionEnabled = NO; [self addSubview:_pair];
        _system = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:host.isNvidiaServerSoftware ? @"square.grid.2x2.fill" : @"desktopcomputer"]]; _system.tintColor = UIColor.systemBlueColor;
        _arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]]; _arrow.tintColor = UIColor.tertiaryLabelColor;
        [self addSubview:_system]; [self addSubview:_arrow];
        [self addTarget:self action:@selector(activate) forControlEvents:UIControlEventPrimaryActionTriggered];
        [self addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:self]];
        self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", host.name, DBText(host.state == StateOnline ? @"online" : host.state == StateOffline ? @"offline" : @"connecting")];
        self.accessibilityIdentifier = [@"device-card-" stringByAppendingString:host.uuid]; self.pointerInteractionEnabled = YES;
    } return self;
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat width = self.bounds.size.width, height = self.bounds.size.height, coverWidth = MIN(180, width * 0.35);
    _cover.frame = CGRectMake(0, 0, coverWidth, height); _status.frame = CGRectMake(7, 7, MAX(0, MIN(coverWidth - 14, _status.intrinsicContentSize.width)), 25);
    CGFloat x = coverWidth + 16, available = MAX(0, width - x - 36);
    _name.frame = CGRectMake(x, MAX(14, height / 2 - 28), available, 27); _system.frame = CGRectMake(x, height / 2 + 7, 20, 20);
    _pair.frame = CGRectMake(x + 28, height / 2 + 7, MAX(0, available - 28), 20); _arrow.frame = CGRectMake(width - 27, (height - 16) / 2, 10, 16);
}
- (void)activate { [_delegate hostClicked:_host view:self]; }
- (void)setHighlighted:(BOOL)highlighted { [super setHighlighted:highlighted]; self.alpha = highlighted ? 0.7 : 1; }
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location {
    [self cancelTrackingWithEvent:nil]; [_delegate hostLongClicked:_host view:self]; return nil;
}
@end

@interface DBSectionButton : UIButton
@end
@implementation DBSectionButton
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat width = self.bounds.size.width;
    self.titleLabel.frame = CGRectMake(0, 0, MAX(0, width - 30), self.bounds.size.height);
    self.imageView.frame = CGRectMake(MAX(0, width - 18), (self.bounds.size.height - 14) / 2, 14, 14);
}
@end

@interface DBDeviceListController : UIViewController
@property (nonatomic, weak) DeviceBrowserViewController *owner;
@property (nonatomic, copy) NSArray<TemporaryHost *> *hosts;
@property (nonatomic, strong) NSCache *cache;
- (void)refresh;
@end
@implementation DBDeviceListController {
    UIScrollView *_scroll; UIStackView *_stack; NSLayoutConstraint *_stackTop;
    BOOL _onlineOnly; NSMutableIndexSet *_collapsed; NSString *_signature; CGFloat _width;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = DBBackground(); self.view.accessibilityIdentifier = @"device-management-list"; _collapsed = [NSMutableIndexSet indexSet];
    _scroll = [[UIScrollView alloc] init]; _scroll.translatesAutoresizingMaskIntoConstraints = NO; _scroll.alwaysBounceVertical = YES; _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _stack = [[UIStackView alloc] init]; _stack.axis = UILayoutConstraintAxisVertical; _stack.spacing = 16; _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scroll]; [_scroll addSubview:_stack];
    _stackTop = [_stack.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor constant:18];
    [NSLayoutConstraint activateConstraints:@[[_scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor], [_scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor], [_scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        _stackTop, [_stack.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor constant:-32],
        [_stack.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor constant:18], [_stack.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor constant:-18],
        [_stack.widthAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.widthAnchor constant:-36]]];
    [self refresh];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat top = MAX(18, DBLandscapeTopInset(self.view));
    if (fabs(_stackTop.constant - top) > 0.5) _stackTop.constant = top;
    if (fabs(_width - self.view.bounds.size.width) > 1) { _width = self.view.bounds.size.width; _signature = nil; [self refresh]; }
}
- (void)refresh {
    if (!self.isViewLoaded) return;
    NSMutableString *signature = [NSMutableString stringWithFormat:@"%d-%@-%g", _onlineOnly, _collapsed, _width];
    for (TemporaryHost *host in self.hosts) [signature appendFormat:@"|%@:%@:%d:%d:%p", host.uuid, host.name, host.state, host.pairState, DBArtwork(host, self.cache)];
    if ([_signature isEqualToString:signature]) return; _signature = signature.copy;
    CGPoint offset = _scroll.contentOffset; for (UIView *view in _stack.arrangedSubviews.copy) [view removeFromSuperview];
    UILabel *title = [[UILabel alloc] init]; title.text = DBText(@"devices.title"); title.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold]; title.textColor = UIColor.labelColor;
    [title setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIButton *filter = [UIButton buttonWithType:UIButtonTypeSystem]; UIButtonConfiguration *configuration = UIButtonConfiguration.tintedButtonConfiguration;
    configuration.title = DBText(_onlineOnly ? @"devices.online_only" : @"devices.all"); configuration.image = [UIImage systemImageNamed:@"rectangle.2.swap"];
    configuration.imagePadding = 5; configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule; configuration.baseForegroundColor = UIColor.secondaryLabelColor;
    configuration.baseBackgroundColor = UIColor.secondaryLabelColor; configuration.contentInsets = NSDirectionalEdgeInsetsMake(5, 9, 5, 9); filter.configuration = configuration;
    [filter setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal]; [filter addTarget:self action:@selector(filter:) forControlEvents:UIControlEventTouchUpInside];
    __weak typeof(self) weakSelf = self;
    UIStackView *heading = [[UIStackView alloc] initWithArrangedSubviews:@[title, filter]]; heading.alignment = UIStackViewAlignmentCenter; heading.spacing = 8; [_stack addArrangedSubview:heading];
    NSInteger columns = _width >= 760 ? 2 : 1;
    for (NSInteger group = 0; group < 3; group++) {
        if (_onlineOnly && group != 0) continue;
        State state = group == 0 ? StateOnline : group == 1 ? StateUnknown : StateOffline;
        NSMutableArray *hosts = [NSMutableArray array]; for (TemporaryHost *host in self.hosts) if (host.state == state) [hosts addObject:host];
        if (hosts.count == 0 && group != 0) continue;
        UIButton *section = [[DBSectionButton alloc] init]; section.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        [section.heightAnchor constraintEqualToConstant:32].active = YES;
        NSString *name = DBText(group == 0 ? @"devices.online_count" : group == 1 ? @"devices.connecting_count" : @"devices.offline_count");
        [section setTitle:[NSString stringWithFormat:name, (unsigned long)hosts.count] forState:UIControlStateNormal];
        [section setImage:[UIImage systemImageNamed:[_collapsed containsIndex:group] ? @"chevron.down" : @"chevron.up"] forState:UIControlStateNormal];
        section.tintColor = UIColor.secondaryLabelColor; [section setTitleColor:UIColor.secondaryLabelColor forState:UIControlStateNormal]; section.tag = group;
        section.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; [section addTarget:self action:@selector(collapse:) forControlEvents:UIControlEventTouchUpInside]; [_stack addArrangedSubview:section];
        section.titleLabel.textAlignment = NSTextAlignmentLeft;
        if ([_collapsed containsIndex:group]) continue;
        for (NSUInteger i = 0; i < hosts.count; i += columns) {
            UIStackView *row = [[UIStackView alloc] init]; row.axis = UILayoutConstraintAxisHorizontal; row.distribution = UIStackViewDistributionFillEqually; row.spacing = 16;
            for (NSInteger column = 0; column < columns; column++) {
                if (i + column < hosts.count) {
                    DBDeviceCard *card = [[DBDeviceCard alloc] initWithHost:hosts[i + column] cache:self.cache delegate:self.owner.hostDelegate];
                    [card.heightAnchor constraintEqualToConstant:columns == 2 ? 128 : (_width >= 600 ? 136 : 106)].active = YES; [row addArrangedSubview:card];
                } else [row addArrangedSubview:[[UIView alloc] init]];
            }
            [_stack addArrangedSubview:row];
        }
    }
    if (self.hosts.count == 0 || (_onlineOnly && ![self.hosts indexesOfObjectsPassingTest:^BOOL(TemporaryHost *host, NSUInteger index, BOOL *stop) { return host.state == StateOnline; }].count)) {
        UILabel *empty = [[UILabel alloc] init]; empty.text = DBText(_onlineOnly ? @"devices.none_online" : @"devices.none"); empty.numberOfLines = 0;
        empty.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; empty.textColor = UIColor.secondaryLabelColor; empty.textAlignment = NSTextAlignmentCenter; [_stack addArrangedSubview:empty];
        UIButton *add = [UIButton buttonWithType:UIButtonTypeSystem]; add.configuration = UIButtonConfiguration.tintedButtonConfiguration;
        [add setTitle:DBText(@"devices.add") forState:UIControlStateNormal]; [add addAction:[UIAction actionWithHandler:^(UIAction *action) { [weakSelf.owner.hostDelegate addHostClicked]; }] forControlEvents:UIControlEventTouchUpInside]; [_stack addArrangedSubview:add];
    }
    _scroll.contentOffset = offset;
}
- (void)filter:(UIButton *)source {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:DBText(@"devices.filter") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:DBText(@"devices.all") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { self->_onlineOnly = NO; self->_signature = nil; [self refresh]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:DBText(@"devices.online_only") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { self->_onlineOnly = YES; self->_signature = nil; [self refresh]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:DBText(@"devices.add") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self.owner.hostDelegate addHostClicked]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:DBText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = source; menu.popoverPresentationController.sourceRect = source.bounds; [self presentViewController:menu animated:YES completion:nil];
}
- (void)collapse:(UIButton *)button { if ([_collapsed containsIndex:button.tag]) [_collapsed removeIndex:button.tag]; else [_collapsed addIndex:button.tag]; _signature = nil; [self refresh]; }
@end

@interface DBQuickAppsController : UITableViewController
- (instancetype)initWithHost:(TemporaryHost *)host completion:(void (^)(void))completion;
@end
@implementation DBQuickAppsController {
    TemporaryHost *_host; NSArray<TemporaryApp *> *_apps; NSMutableSet *_selected; void (^_completion)(void);
}
- (instancetype)initWithHost:(TemporaryHost *)host completion:(void (^)(void))completion {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _host = host; _completion = [completion copy]; NSMutableArray *apps = [NSMutableArray array];
        for (TemporaryApp *app in DBApps(host)) if (!app.hidden && app.id.length) [apps addObject:app]; _apps = apps;
        _selected = [NSMutableSet setWithArray:DBSelectedApps(host)];
    } return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = DBText(@"apps.manage"); self.view.accessibilityIdentifier = @"device-quick-launch-manager";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:DBText(@"cancel") style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:DBText(@"done") style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    if (_apps.count == 0) { UILabel *empty = [[UILabel alloc] init]; empty.text = DBText(@"apps.none_published"); empty.numberOfLines = 0; empty.textAlignment = NSTextAlignmentCenter; empty.textColor = UIColor.secondaryLabelColor; self.tableView.backgroundView = empty; }
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return DBText(@"apps.choose_quick_launch"); }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _apps.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; TemporaryApp *app = _apps[indexPath.row];
    cell.textLabel.text = app.name; cell.imageView.image = [UIImage systemImageNamed:@"app"]; cell.imageView.tintColor = UIColor.systemBlueColor;
    cell.accessoryType = [_selected containsObject:app.id] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *identifier = _apps[indexPath.row].id; if ([_selected containsObject:identifier]) [_selected removeObject:identifier]; else [_selected addObject:identifier];
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)done { [NSUserDefaults.standardUserDefaults setObject:_selected.allObjects forKey:DBQuickKey(_host)]; if (_completion) _completion(); [self cancel]; }
@end

@interface DBAppButton : UIButton <UIContextMenuInteractionDelegate>
- (instancetype)initWithApp:(TemporaryApp *)app cache:(NSCache *)cache delegate:(id<AppCallback>)delegate;
@end
@implementation DBAppButton {
    TemporaryApp *_app; __weak id<AppCallback> _delegate; UIImageView *_image, *_running; UILabel *_name;
}
- (instancetype)initWithApp:(TemporaryApp *)app cache:(NSCache *)cache delegate:(id<AppCallback>)delegate {
    if ((self = [super init])) {
        _app = app; _delegate = delegate; self.layer.cornerRadius = 12; self.clipsToBounds = YES; self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        _image = [[UIImageView alloc] init]; _image.contentMode = UIViewContentModeScaleAspectFit; _image.tintColor = UIColor.systemBlueColor;
        _image.image = [cache objectForKey:app] ?: [UIImage systemImageNamed:@"app"];
        _name = [[UILabel alloc] init]; _name.text = app.name; _name.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        _name.textColor = UIColor.labelColor; _name.numberOfLines = 2; _name.textAlignment = NSTextAlignmentCenter; _name.lineBreakMode = NSLineBreakByTruncatingTail; _name.userInteractionEnabled = NO;
        _running = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"play.circle.fill"]]; _running.tintColor = UIColor.systemGreenColor;
        _running.hidden = ![app.id isEqualToString:app.host.currentGame];
        [self addSubview:_image]; [self addSubview:_name]; [self addSubview:_running];
        self.alpha = app.hidden ? 0.45 : 1; self.accessibilityLabel = app.name; self.accessibilityIdentifier = [@"device-launch-app-" stringByAppendingString:app.id ?: @""];
        [self addTarget:self action:@selector(activate) forControlEvents:UIControlEventPrimaryActionTriggered]; [self addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:self]];
        self.pointerInteractionEnabled = YES; self.enabled = app.id.length > 0 && app.host.state == StateOnline && app.host.pairState == PairStatePaired;
    } return self;
}
- (void)layoutSubviews { [super layoutSubviews]; CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    _image.frame = CGRectMake(18, 14, MAX(0, width - 36), MAX(0, height - 72)); _name.frame = CGRectMake(8, height - 52, MAX(0, width - 16), 44); _running.frame = CGRectMake(width - 30, 8, 22, 22);
}
- (void)activate { [_delegate appClicked:_app view:self]; }
- (void)setHighlighted:(BOOL)highlighted { [super setHighlighted:highlighted]; self.alpha = highlighted ? 0.6 : _app.hidden ? 0.45 : 1; }
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location {
    [self cancelTrackingWithEvent:nil]; [_delegate appLongClicked:_app view:self]; return nil;
}
@end

@interface DBAddAppButton : UIButton
@end
@implementation DBAddAppButton {
    CAShapeLayer *_border; UIImageView *_icon; UILabel *_name;
}
- (instancetype)init {
    if ((self = [super init])) {
        _border = [CAShapeLayer layer]; _border.fillColor = UIColor.clearColor.CGColor; _border.lineWidth = 1.5; _border.lineDashPattern = @[@6, @5]; [self.layer addSublayer:_border];
        _icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"plus.circle.fill"]]; _icon.tintColor = UIColor.tertiaryLabelColor; _icon.contentMode = UIViewContentModeScaleAspectFit;
        _name = [[UILabel alloc] init]; _name.text = DBText(@"apps.add"); _name.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; _name.textColor = UIColor.labelColor; _name.textAlignment = NSTextAlignmentCenter; _name.userInteractionEnabled = NO;
        [self addSubview:_icon]; [self addSubview:_name]; self.accessibilityLabel = _name.text; self.accessibilityIdentifier = @"device-add-quick-app";
    } return self;
}
- (void)layoutSubviews { [super layoutSubviews]; _border.frame = self.bounds; _border.strokeColor = UIColor.separatorColor.CGColor; _border.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds, 1, 1) cornerRadius:14].CGPath;
    CGFloat size = self.bounds.size.height > 220 ? 52 : 38; _icon.frame = CGRectMake((self.bounds.size.width - size) / 2, self.bounds.size.height / 2 - size + 4, size, size);
    _name.frame = CGRectMake(5, CGRectGetMaxY(_icon.frame) + 10, MAX(0, self.bounds.size.width - 10), 26);
}
@end

@interface DBDetailHeader : UICollectionReusableView
@property (nonatomic, weak) DeviceBrowserViewController *owner;
@property (nonatomic, copy) void (^manageApps)(void);
- (void)configure:(TemporaryHost *)host cache:(NSCache *)cache allApps:(BOOL)allApps;
@end
@implementation DBDetailHeader {
    TemporaryHost *_host; UILabel *_name, *_quickTitle; DBStatusView *_status; UIView *_card;
    DBCoverView *_cover; UIButton *_back, *_more, *_settings, *_desktop, *_manage;
    NSArray<UIButton *> *_features; NSArray<UIView *> *_separators;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        __weak typeof(self) weakSelf = self;
        _back = DBIconButton(@"chevron.left", DBText(@"devices.title"), ^(UIAction *action) { if (weakSelf.owner.backToHosts) weakSelf.owner.backToHosts(); else [weakSelf.owner showHosts]; });
        _more = DBIconButton(@"ellipsis", DBText(@"more"), ^(UIAction *action) { DBDetailHeader *header = weakSelf; if (header) [header.owner.hostDelegate hostLongClicked:header->_host view:header->_more]; });
        _settings = DBIconButton(@"gearshape", DBText(@"settings"), ^(UIAction *action) { DBDetailHeader *header = weakSelf; if (header && header.owner.openSettings) header.owner.openSettings(header->_host); });
        _settings.accessibilityIdentifier = @"device-stream-settings";
        _back.accessibilityIdentifier = @"device-back-to-list";
        _name = [[UILabel alloc] init]; _name.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold]; _name.textColor = UIColor.labelColor; _name.lineBreakMode = NSLineBreakByTruncatingTail;
        _status = [[DBStatusView alloc] init]; _card = [[UIView alloc] init]; _card.layer.cornerRadius = 14; _card.clipsToBounds = YES; _card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        _cover = [[DBCoverView alloc] init]; [_card addSubview:_cover];
        _desktop = [UIButton buttonWithType:UIButtonTypeSystem]; _desktop.contentVerticalAlignment = UIControlContentVerticalAlignmentBottom;
        UIButtonConfiguration *desktopConfiguration = UIButtonConfiguration.plainButtonConfiguration;
        desktopConfiguration.baseForegroundColor = UIColor.whiteColor; desktopConfiguration.image = [UIImage systemImageNamed:@"chevron.right"];
        desktopConfiguration.imagePlacement = NSDirectionalRectEdgeTrailing; desktopConfiguration.imagePadding = 8;
        desktopConfiguration.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *incoming) {
            NSMutableDictionary *attributes = incoming.mutableCopy; attributes[NSForegroundColorAttributeName] = UIColor.whiteColor;
            attributes[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3]; return attributes;
        };
        desktopConfiguration.imageColorTransformer = ^UIColor *(UIColor *incoming) { return UIColor.whiteColor; };
        desktopConfiguration.contentInsets = NSDirectionalEdgeInsetsMake(0, 0, 18, 0); _desktop.configuration = desktopConfiguration;
        [_desktop setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; _desktop.tintColor = UIColor.whiteColor; _desktop.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
        _desktop.titleLabel.layer.shadowColor = UIColor.blackColor.CGColor; _desktop.titleLabel.layer.shadowRadius = 4; _desktop.titleLabel.layer.shadowOpacity = 0.8;
        [_desktop addAction:[UIAction actionWithHandler:^(UIAction *action) { DBDetailHeader *header = weakSelf; if (header && header.owner.openDesktop) header.owner.openDesktop(header->_host, header->_desktop); }] forControlEvents:UIControlEventTouchUpInside];
        _desktop.accessibilityIdentifier = @"device-enter-desktop"; [_card addSubview:_desktop];
        NSMutableArray *buttons = [NSMutableArray array], *lines = [NSMutableArray array];
        NSArray *icons = @[@"folder.badge.plus", @"play.rectangle", @"terminal", @"square.grid.2x2"], *titles = @[@"files", @"view_mode", @"terminal", @"more"];
        for (NSUInteger i = 0; i < icons.count; i++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; UIButtonConfiguration *configuration = UIButtonConfiguration.plainButtonConfiguration;
            configuration.image = [UIImage systemImageNamed:icons[i]]; configuration.imagePlacement = NSDirectionalRectEdgeTop; configuration.imagePadding = 5;
            configuration.attributedTitle = [[NSAttributedString alloc] initWithString:DBText(titles[i]) attributes:@{NSFontAttributeName:[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]}];
            configuration.baseForegroundColor = UIColor.labelColor; button.configuration = configuration;
            button.accessibilityIdentifier = [@"device-feature-" stringByAppendingString:titles[i]];
            if (i == 0) [button addAction:[UIAction actionWithHandler:^(UIAction *action) { DBDetailHeader *header = weakSelf; if (header && header.owner.openFiles) header.owner.openFiles(header->_host); }] forControlEvents:UIControlEventTouchUpInside];
            else if (i == 3) [button addAction:[UIAction actionWithHandler:^(UIAction *action) { DBDetailHeader *header = weakSelf; if (header) [header.owner.hostDelegate hostLongClicked:header->_host view:action.sender]; }] forControlEvents:UIControlEventTouchUpInside];
            else { button.enabled = NO; button.accessibilityHint = DBText(@"pending"); }
            [buttons addObject:button]; [_card addSubview:button];
            if (i > 0) { UIView *line = [[UIView alloc] init]; line.backgroundColor = UIColor.separatorColor; [lines addObject:line]; [_card addSubview:line]; }
        }
        _features = buttons; _separators = lines;
        _quickTitle = [[UILabel alloc] init]; _quickTitle.font = [UIFont systemFontOfSize:21 weight:UIFontWeightSemibold]; _quickTitle.textColor = UIColor.labelColor;
        _manage = [UIButton buttonWithType:UIButtonTypeSystem]; UIButtonConfiguration *configuration = UIButtonConfiguration.tintedButtonConfiguration;
        configuration.title = DBText(@"apps.manage"); configuration.image = [UIImage systemImageNamed:@"square.grid.2x2"]; configuration.imagePadding = 5;
        configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule; configuration.baseForegroundColor = UIColor.secondaryLabelColor; configuration.baseBackgroundColor = UIColor.secondaryLabelColor;
        _manage.configuration = configuration; [_manage addAction:[UIAction actionWithHandler:^(UIAction *action) { if (weakSelf.manageApps) weakSelf.manageApps(); }] forControlEvents:UIControlEventTouchUpInside]; _manage.accessibilityIdentifier = @"device-manage-apps";
        for (UIView *view in @[_back, _status, _name, _more, _settings, _card, _quickTitle, _manage]) [self addSubview:view];
    } return self;
}
- (void)configure:(TemporaryHost *)host cache:(NSCache *)cache allApps:(BOOL)allApps {
    _host = host; _name.text = host.name; [_status update:host]; [_cover showImage:DBArtwork(host, cache)];
    TemporaryApp *desktop = [DeviceBrowserViewController desktopApplicationForHost:host];
    [_desktop setTitle:DBText(desktop ? @"desktop.enter" : host.appList.count ? @"desktop.choose" : @"desktop.unavailable") forState:UIControlStateNormal];
    _desktop.enabled = host.state == StateOnline && host.pairState == PairStatePaired && host.appList.count > 0;
    _desktop.alpha = _desktop.enabled ? 1 : 0.65;
    _features[0].enabled = self.owner.supportsFiles && self.owner.supportsFiles(host); _features[1].enabled = NO; _features[2].enabled = NO;
    _quickTitle.text = DBText(allApps ? @"apps.all" : @"apps.quick_launch"); [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat width = self.bounds.size.width, padding = 18, cardWidth = MAX(0, width - padding * 2), photo = MIN(320, cardWidth * 9 / 16);
    _back.frame = CGRectMake(padding - 8, 1, 40, 44); _status.frame = CGRectMake(padding + 36, 10, _status.intrinsicContentSize.width, 25);
    CGFloat nameX = CGRectGetMaxX(_status.frame) + 10, settingsX = width - padding - 44;
    CGFloat nameWidth = MIN([_name sizeThatFits:CGSizeMake(CGFLOAT_MAX, 40)].width + 2, MAX(0, settingsX - nameX - 48));
    _name.frame = CGRectMake(nameX, 0, nameWidth, 44); _more.frame = CGRectMake(CGRectGetMaxX(_name.frame) + 4, 0, 40, 44); _settings.frame = CGRectMake(settingsX, 0, 44, 44);
    _card.frame = CGRectMake(padding, 60, cardWidth, photo + 68); _cover.frame = CGRectMake(0, 0, cardWidth, photo); _desktop.frame = _cover.frame;
    CGFloat buttonWidth = cardWidth / 4; for (NSUInteger i = 0; i < _features.count; i++) _features[i].frame = CGRectMake(i * buttonWidth, photo, buttonWidth, 68);
    for (NSUInteger i = 0; i < _separators.count; i++) _separators[i].frame = CGRectMake((i + 1) * buttonWidth, photo + 12, 0.5, 44);
    CGFloat y = CGRectGetMaxY(_card.frame) + 24; _quickTitle.frame = CGRectMake(padding, y, MAX(0, cardWidth - 140), 42); _manage.frame = CGRectMake(width - padding - 132, y + 3, 132, 36);
}
@end

@interface DBDeviceDetailController : UICollectionViewController <UICollectionViewDelegateFlowLayout>
@property (nonatomic, weak) DeviceBrowserViewController *owner;
@property (nonatomic, strong) TemporaryHost *host;
@property (nonatomic, strong) NSCache *cache;
@property (nonatomic) BOOL allApps;
- (void)refresh;
@end
@implementation DBDeviceDetailController {
    NSArray<TemporaryApp *> *_apps; NSString *_signature; CGSize _layoutSize;
}
- (instancetype)init { UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init]; layout.minimumLineSpacing = 16; layout.minimumInteritemSpacing = 14; layout.sectionInset = UIEdgeInsetsMake(0, 18, 24, 18); if ((self = [super initWithCollectionViewLayout:layout])) _apps = @[]; return self; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = DBBackground(); self.collectionView.backgroundColor = DBBackground(); self.view.accessibilityIdentifier = @"device-management-detail";
    self.collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.collectionView registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"app"];
    [self.collectionView registerClass:DBDetailHeader.class forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"header"];
    [self refresh];
}
- (void)refresh {
    if (!self.isViewLoaded) return;
    NSArray *selected = DBSelectedApps(self.host); NSMutableArray *apps = [NSMutableArray array];
    NSMutableString *signature = [NSMutableString stringWithFormat:@"%d:%d:%d", self.allApps, self.host.state, self.host.pairState];
    for (TemporaryApp *app in DBApps(self.host)) if (self.allApps || (!app.hidden && [selected containsObject:app.id])) {
        [apps addObject:app]; [signature appendFormat:@"|%@:%@:%d:%p:%@", app.id, app.name, app.hidden, [self.cache objectForKey:app], self.host.currentGame];
    }
    _apps = apps;
    if (![_signature isEqualToString:signature]) { _signature = signature.copy; [self.collectionView reloadData]; }
    for (DBDetailHeader *header in [self.collectionView visibleSupplementaryViewsOfKind:UICollectionElementKindSectionHeader]) [header configure:self.host cache:self.cache allApps:self.allApps];
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; if (!CGSizeEqualToSize(_layoutSize, self.collectionView.bounds.size)) { _layoutSize = self.collectionView.bounds.size; [self.collectionView.collectionViewLayout invalidateLayout]; } }
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { return _apps.count + 1; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"app" forIndexPath:indexPath]; for (UIView *view in cell.contentView.subviews) [view removeFromSuperview];
    UIButton *button;
    if ((NSUInteger)indexPath.row == _apps.count) { button = [[DBAddAppButton alloc] init]; [button addTarget:self action:@selector(manageApps) forControlEvents:UIControlEventPrimaryActionTriggered]; }
    else button = [[DBAppButton alloc] initWithApp:_apps[indexPath.row] cache:self.cache delegate:self.owner.appDelegate];
    button.frame = cell.contentView.bounds; button.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [cell.contentView addSubview:button]; return cell;
}
- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    DBDetailHeader *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"header" forIndexPath:indexPath]; header.owner = self.owner;
    __weak typeof(self) weakSelf = self; header.manageApps = ^{ [weakSelf manageApps]; }; [header configure:self.host cache:self.cache allApps:self.allApps]; return header;
}
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout referenceSizeForHeaderInSection:(NSInteger)section {
    CGFloat width = collectionView.bounds.size.width; return CGSizeMake(width, 208 + MIN(320, MAX(0, width - 36) * 9 / 16));
}
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = MAX(1, collectionView.bounds.size.width - 36);
    if (_apps.count == 0) return CGSizeMake(width, MIN(340, MAX(240, self.view.bounds.size.height * 0.36)));
    NSInteger columns = MAX(2, (NSInteger)floor((width + 14) / 154)); CGFloat item = floor((width - (columns - 1) * 14) / columns); return CGSizeMake(item, 178);
}
- (void)manageApps {
    __weak typeof(self) weakSelf = self; DBQuickAppsController *picker = [[DBQuickAppsController alloc] initWithHost:self.host completion:^{
        weakSelf.allApps = NO; if (weakSelf.owner.didManageApps) weakSelf.owner.didManageApps(); [weakSelf refresh];
    }];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:picker]; [self presentViewController:navigation animated:YES completion:nil];
}
@end

@implementation DeviceBrowserViewController {
    DBDeviceListController *_list; DBDeviceDetailController *_detail; NSLayoutConstraint *_detailTop;
    NSCache *_cache; NSArray<TemporaryHost *> *_hosts; NSTimer *_timer;
}
- (instancetype)initWithArtworkCache:(NSCache *)cache { if ((self = [super initWithNibName:nil bundle:nil])) { _cache = cache; _hosts = @[]; } return self; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = DBBackground();
    _list = [[DBDeviceListController alloc] init]; _list.owner = self; _list.cache = _cache; _list.hosts = _hosts;
    [self addChildViewController:_list]; _list.view.frame = self.view.bounds; _list.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [self.view addSubview:_list.view]; [_list didMoveToParentViewController:self];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshArtwork) name:FileTransferManagerDidChange object:nil];
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [self refreshArtwork]; [_timer invalidate]; __weak typeof(self) weakSelf = self; _timer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) { [weakSelf refreshArtwork]; }]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [_timer invalidate]; _timer = nil; }
- (void)dealloc { [_timer invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat top = DBLandscapeTopInset(self.view);
    if (_detailTop && fabs(_detailTop.constant - top) > 0.5) _detailTop.constant = top;
}
- (void)updateHosts:(NSArray<TemporaryHost *> *)hosts {
    _hosts = hosts.copy; _list.hosts = _hosts; [_list refresh];
    if (_detail) { BOOL found = NO; for (TemporaryHost *host in hosts) if ([host.uuid isEqualToString:_detail.host.uuid]) { _detail.host = host; found = YES; break; }
        if (!found && self.backToHosts) self.backToHosts(); else [_detail refresh];
    }
}
- (void)showHosts {
    if (_detail) { [_detail willMoveToParentViewController:nil]; [_detail.view removeFromSuperview]; [_detail removeFromParentViewController]; _detail = nil; _detailTop = nil; }
    _list.view.hidden = NO; [_list refresh];
}
- (void)showHost:(TemporaryHost *)host allApps:(BOOL)allApps {
    [self loadViewIfNeeded]; if (_detail && ![_detail.host.uuid isEqualToString:host.uuid]) [self showHosts];
    if (!_detail) {
        _detail = [[DBDeviceDetailController alloc] init]; _detail.owner = self; _detail.cache = _cache; _detail.host = host; _detail.allApps = allApps;
        [self addChildViewController:_detail]; _detail.view.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:_detail.view];
        _detailTop = [_detail.view.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:DBLandscapeTopInset(self.view)];
        [NSLayoutConstraint activateConstraints:@[_detailTop,
            [_detail.view.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
            [_detail.view.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
            [_detail.view.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor]]];
        [_detail didMoveToParentViewController:self];
    } else { _detail.host = host; _detail.allApps = allApps; [_detail refresh]; }
    _list.view.hidden = YES;
}
- (void)refreshArtwork { if (_detail) [_detail refresh]; else [_list refresh]; }
- (void)setInteractionEnabled:(BOOL)enabled { self.view.userInteractionEnabled = enabled; }
+ (TemporaryApp *)desktopApplicationForHost:(TemporaryHost *)host {
    NSString *selected = [NSUserDefaults.standardUserDefaults stringForKey:[@"SideLantern.DesktopApp." stringByAppendingString:host.uuid]];
    for (TemporaryApp *app in host.appList) if ([app.id isEqualToString:selected]) return app;
    for (TemporaryApp *app in DBApps(host)) if ([@[@"desktop", @"桌面", @"远程桌面", @"entire desktop"] containsObject:app.name.lowercaseString]) return app;
    return nil;
}
+ (void)setDesktopApplication:(TemporaryApp *)app forHost:(TemporaryHost *)host { if (app.id.length) [NSUserDefaults.standardUserDefaults setObject:app.id forKey:[@"SideLantern.DesktopApp." stringByAppendingString:host.uuid]]; }
@end

#if DEBUG && TARGET_OS_SIMULATOR
#import "FileTransferPreview.h"
#import "SettingsViewController.h"
#import "SideLanternNavigationController.h"

@interface DBPreviewController : DeviceBrowserViewController <HostCallback, AppCallback>
@property (nonatomic, strong) TemporaryHost *previewHost;
@property (nonatomic) BOOL showInitialDetail;
@end
@implementation DBPreviewController
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; if (self.showInitialDetail) { self.showInitialDetail = NO; [self showHost:self.previewHost allApps:NO]; } }
- (void)hostClicked:(TemporaryHost *)host view:(UIView *)view { [self showHost:host allApps:NO]; }
- (void)hostLongClicked:(TemporaryHost *)host view:(UIView *)view {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:host.name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:DBText(@"apps.all") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self showHost:host allApps:YES]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:DBText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = view ?: self.view; menu.popoverPresentationController.sourceRect = (view ?: self.view).bounds;
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)addHostClicked { }
- (void)appClicked:(TemporaryApp *)app view:(UIView *)view { }
- (void)appLongClicked:(TemporaryApp *)app view:(UIView *)view { }
@end

UIViewController *DeviceBrowserPreview(BOOL detail, BOOL empty) {
    NSCache *cache = [[NSCache alloc] init]; NSMutableArray *hosts = [NSMutableArray array];
    NSArray *names = @[@"DESKTOP-PAN", @"游戏电脑", @"工作电脑 — 长名称设备", @"客厅主机"];
    for (NSUInteger i = 0; i < names.count; i++) {
        TemporaryHost *host = [[TemporaryHost alloc] init]; host.name = names[i]; host.uuid = [NSString stringWithFormat:@"device-preview-%lu%@", (unsigned long)i, empty ? @"-empty" : @""];
        host.state = i < 2 ? StateOnline : i == 2 ? StateUnknown : StateOffline; host.pairState = PairStatePaired; host.appList = [NSSet set];
        if (!empty || i != 0) {
            NSMutableSet *apps = [NSMutableSet set]; NSArray *appNames = @[@"Desktop", @"Steam", @"Playnite", @"Visual Studio Code", @"资源管理器"];
            NSArray *symbols = @[@"desktopcomputer", @"gamecontroller.fill", @"play.rectangle.fill", @"curlybraces", @"folder.fill"];
            for (NSUInteger j = 0; j < appNames.count; j++) {
                TemporaryApp *app = [[TemporaryApp alloc] init]; app.id = @(j + 1).stringValue; app.name = appNames[j]; app.host = host; [apps addObject:app];
                if (j > 0) [cache setObject:[UIImage systemImageNamed:symbols[j]] forKey:app];
            }
            host.appList = apps; host.currentGame = @"2";
        }
        [hosts addObject:host];
    }
    DBPreviewController *browser = [[DBPreviewController alloc] initWithArtworkCache:cache]; browser.hostDelegate = browser; browser.appDelegate = browser;
    browser.previewHost = hosts.firstObject; browser.showInitialDetail = detail;
    __weak typeof(browser) weakBrowser = browser;
    browser.backToHosts = ^{ [weakBrowser showHosts]; };
    browser.supportsFiles = ^BOOL(TemporaryHost *host) { return host.state == StateOnline; };
    browser.openFiles = ^(TemporaryHost *host) { [weakBrowser presentViewController:FileTransferPreview(NO) animated:YES completion:nil]; };
    browser.openSettings = ^(TemporaryHost *host) {
        NSString *name = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"iPad" : @"iPhone";
        SettingsViewController *settings = [[UIStoryboard storyboardWithName:name bundle:nil] instantiateViewControllerWithIdentifier:@"settingsFrame"];
        [settings configureStreamTargetsForHost:nil];
        [weakBrowser.navigationController pushViewController:settings animated:YES];
    };
    [browser updateHosts:hosts];
    return [[SideLanternNavigationController alloc] initWithRootViewController:browser];
}
#endif
