#import "SettingsChoiceView.h"

@implementation SettingsChoiceView {
    UISegmentedControl *_control;
    UIButton *_menuButton;
    NSString *_lastSignature;
}

- (instancetype)initWithControl:(UISegmentedControl *)control label:(NSString *)label identifier:(NSString *)identifier {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _control = control;
        self.isAccessibilityElement = NO;
        self.accessibilityLabel = label;
        _control.translatesAutoresizingMaskIntoConstraints = NO;
        [_control removeFromSuperview];
        [_control addTarget:self action:@selector(valueChanged) forControlEvents:UIControlEventValueChanged];
        _control.accessibilityLabel = label;
        _control.accessibilityIdentifier = identifier;
        [self addSubview:_control];

        _menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _menuButton.translatesAutoresizingMaskIntoConstraints = NO;
        _menuButton.showsMenuAsPrimaryAction = YES;
        _menuButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        _menuButton.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
        _menuButton.titleLabel.numberOfLines = 0;
        _menuButton.titleLabel.adjustsFontForContentSizeCategory = YES;
        _menuButton.layer.cornerRadius = 8;
        _menuButton.backgroundColor = UIColor.secondarySystemBackgroundColor;
        [_menuButton setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
        _menuButton.accessibilityLabel = label;
        _menuButton.accessibilityIdentifier = [identifier stringByAppendingString:@"-menu"];
        _menuButton.accessibilityHint = NSLocalizedStringFromTable(@"settings.choice_hint", @"StreamTarget", nil);
        [self addSubview:_menuButton];
        [NSLayoutConstraint activateConstraints:@[
            [_control.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_control.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_control.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_control.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_menuButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_menuButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_menuButton.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_menuButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        ]];
        [self refresh];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self refresh];
}

- (UISegmentedControl *)control { return _control; }

- (void)valueChanged {
    [self refresh];
    dispatch_async(dispatch_get_main_queue(), ^{ [self sendActionsForControlEvents:UIControlEventValueChanged]; });
}

- (void)refresh {
    UIFont *font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline]
        scaledFontForFont:[UIFont systemFontOfSize:14 weight:UIFontWeightMedium]];
    CGFloat requiredWidth = 0;
    NSMutableString *signature = [NSMutableString stringWithFormat:@"%ld-%d-%.0f-%.0f", (long)_control.selectedSegmentIndex,
        _control.enabled, self.bounds.size.width, font.pointSize];
    for (NSUInteger index = 0; index < _control.numberOfSegments; index++) {
        NSString *title = [_control titleForSegmentAtIndex:index] ?: @"";
        requiredWidth += [title sizeWithAttributes:@{NSFontAttributeName:font}].width + 24;
        [signature appendFormat:@"|%@-%d", title, [_control isEnabledForSegmentAtIndex:index]];
    }
    if ([signature isEqualToString:_lastSignature]) {
        return;
    }
    _lastSignature = signature;
    BOOL useMenu = _control.numberOfSegments > 3 || requiredWidth > self.bounds.size.width;
    _control.hidden = useMenu;
    _menuButton.hidden = !useMenu;
    _menuButton.enabled = _control.enabled;
    _menuButton.titleLabel.font = font;
    [_control setTitleTextAttributes:@{NSFontAttributeName:font} forState:UIControlStateNormal];
    NSInteger selected = _control.selectedSegmentIndex;
    NSString *selectedTitle = selected >= 0 && selected < _control.numberOfSegments ? [_control titleForSegmentAtIndex:selected] : @"—";
    [_menuButton setTitle:[selectedTitle stringByAppendingString:@"  ▾"] forState:UIControlStateNormal];
    _menuButton.accessibilityValue = selectedTitle;

    NSMutableArray<UIAction *> *actions = [[NSMutableArray alloc] init];
    __weak SettingsChoiceView *weakSelf = self;
    for (NSUInteger index = 0; index < _control.numberOfSegments; index++) {
        UIAction *action = [UIAction actionWithTitle:[_control titleForSegmentAtIndex:index] ?: @"" image:nil identifier:nil
            handler:^(UIAction *action) {
                SettingsChoiceView *view = weakSelf;
                if (view != nil) {
                    view->_control.selectedSegmentIndex = index;
                    [view->_control sendActionsForControlEvents:UIControlEventValueChanged];
                }
            }];
        action.state = selected == index ? UIMenuElementStateOn : UIMenuElementStateOff;
        action.attributes = [_control isEnabledForSegmentAtIndex:index] ? 0 : UIMenuElementAttributesDisabled;
        [actions addObject:action];
    }
    _menuButton.menu = [UIMenu menuWithChildren:actions];
}

@end
