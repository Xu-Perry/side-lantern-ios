#import "KeyboardShortcutBar.h"

@implementation KeyboardShortcutBar {
    KeyboardShortcutStore *_store;
    UIStackView *_keys;
    NSMutableDictionary<NSNumber *, UIButton *> *_modifierButtons;
}

- (instancetype)initWithShortcutStore:(KeyboardShortcutStore *)store {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 0, 52)])) {
        _store = store; self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        self.accessibilityIdentifier = @"keyboard-shortcut-toolbar";
        self.backgroundColor = UIColor.secondarySystemBackgroundColor;
        UIScrollView *scroll = [[UIScrollView alloc] init];
        scroll.translatesAutoresizingMaskIntoConstraints = NO;
        scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        scroll.alwaysBounceHorizontal = YES; scroll.showsHorizontalScrollIndicator = NO;
        scroll.delaysContentTouches = NO; scroll.directionalLockEnabled = YES;
        scroll.accessibilityIdentifier = @"keyboard-shortcut-scroll";
        _keys = [[UIStackView alloc] init]; _keys.axis = UILayoutConstraintAxisHorizontal; _keys.spacing = 6;
        _keys.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:scroll]; [scroll addSubview:_keys];
        UIButton *dismiss = [UIButton buttonWithType:UIButtonTypeSystem];
        dismiss.translatesAutoresizingMaskIntoConstraints = NO;
        [dismiss setImage:[UIImage systemImageNamed:@"keyboard.chevron.compact.down"] forState:UIControlStateNormal];
        dismiss.tintColor = UIColor.labelColor;
        dismiss.accessibilityIdentifier = @"keyboard-dismiss";
        dismiss.accessibilityLabel = NSLocalizedStringFromTable(@"keyboard.hide", @"KeyboardShortcuts", nil);
        __weak typeof(self) weakSelf = self;
        [dismiss addAction:[UIAction actionWithHandler:^(UIAction *action) { if (weakSelf.dismissHandler) weakSelf.dismissHandler(); }] forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:dismiss];
        [NSLayoutConstraint activateConstraints:@[
            [dismiss.widthAnchor constraintEqualToConstant:44], [dismiss.heightAnchor constraintEqualToConstant:44],
            [dismiss.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [dismiss.trailingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor constant:-4],
            [scroll.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
            [scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],
            [scroll.leadingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor constant:8],
            [scroll.trailingAnchor constraintEqualToAnchor:dismiss.leadingAnchor constant:-6],
            [_keys.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
            [_keys.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
            [_keys.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
            [_keys.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
            [_keys.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor]]];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadShortcuts) name:KeyboardShortcutsDidChangeNotification object:nil];
        [self reloadShortcuts];
    }
    return self;
}
- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, 52); }
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(size.width, 52); }
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (UIButton *)buttonWithTitle:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration = [UIButtonConfiguration tintedButtonConfiguration];
    configuration.title = title;
    configuration.baseForegroundColor = UIColor.labelColor;
    configuration.baseBackgroundColor = UIColor.tertiarySystemFillColor;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(6, 10, 6, 10);
    configuration.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
        NSMutableDictionary *updated = [attributes mutableCopy];
        updated[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; return updated;
    };
    button.configuration = configuration;
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return button;
}

- (void)reloadShortcuts {
    for (UIView *view in [_keys.arrangedSubviews copy]) { [_keys removeArrangedSubview:view]; [view removeFromSuperview]; }
    _modifierButtons = [NSMutableDictionary dictionary];
    NSArray *keys = @[@[@"Win", @0x5B, @(KeyboardShortcutWindows)], @[@"Esc", @0x1B, @0],
        @[@"Tab", @0x09, @0], @[@"Ctrl", @0xA2, @(KeyboardShortcutControl)],
        @[@"Alt", @0xA4, @(KeyboardShortcutAlt)], @[@"Shift", @0xA0, @(KeyboardShortcutShift)], @[@"Del", @0x2E, @0]];
    __weak typeof(self) weakSelf = self;
    for (NSArray *key in keys) {
        UIButton *button = [self buttonWithTitle:key[0]];
        unsigned short code = [key[1] unsignedShortValue]; BOOL toggle = [key[2] unsignedIntegerValue] != 0;
        button.accessibilityIdentifier = [NSString stringWithFormat:@"keyboard-key-%u", code];
        [button addAction:[UIAction actionWithHandler:^(UIAction *action) { if (weakSelf.keyHandler) weakSelf.keyHandler(code, toggle); }] forControlEvents:UIControlEventTouchUpInside];
        if (toggle) _modifierButtons[key[2]] = button;
        [_keys addArrangedSubview:button];
    }
    for (KeyboardShortcut *shortcut in _store.allShortcuts) {
        UIButton *button = [self buttonWithTitle:shortcut.name];
        button.accessibilityIdentifier = [@"keyboard-shortcut-" stringByAppendingString:shortcut.identifier];
        button.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", shortcut.name, shortcut.combination];
        [button addAction:[UIAction actionWithHandler:^(UIAction *action) { if (weakSelf.shortcutHandler) weakSelf.shortcutHandler(shortcut); }] forControlEvents:UIControlEventTouchUpInside];
        [_keys addArrangedSubview:button];
    }
    [self setActiveModifiers:_activeModifiers];
}
- (void)setActiveModifiers:(KeyboardShortcutModifiers)activeModifiers {
    _activeModifiers = activeModifiers;
    [_modifierButtons enumerateKeysAndObjectsUsingBlock:^(NSNumber *flag, UIButton *button, BOOL *stop) {
        BOOL selected = (activeModifiers & flag.unsignedIntegerValue) != 0;
        UIButtonConfiguration *configuration = button.configuration;
        configuration.baseBackgroundColor = selected ? UIColor.systemPurpleColor : UIColor.tertiarySystemFillColor;
        button.configuration = configuration; button.selected = selected;
        button.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    }];
}
@end
