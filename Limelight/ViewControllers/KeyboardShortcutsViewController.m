#import "KeyboardShortcutsViewController.h"

static NSString *ShortcutText(NSString *key) { return NSLocalizedStringFromTable(key, @"KeyboardShortcuts", nil); }
static void PinShortcutView(UIView *view, UIView *parent) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[[view.topAnchor constraintEqualToAnchor:parent.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor], [view.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor]]];
}

@interface KeyboardShortcutEditorViewController : UIViewController <UITextFieldDelegate>
@property (nonatomic, strong) KeyboardShortcut *shortcut;
@property (nonatomic, copy) void (^completion)(KeyboardShortcut *shortcut, BOOL remove);
@end

@implementation KeyboardShortcutEditorViewController {
    UITextField *_nameField;
    UIButton *_keyButton;
    NSArray<UIButton *> *_modifierButtons;
    UILabel *_combinationLabel;
    UILabel *_errorLabel;
    UIScrollView *_formScroll;
    unsigned short _keyCode;
    KeyboardShortcutModifiers _modifiers;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.view.accessibilityIdentifier = @"shortcut-editor";
    _keyCode = self.shortcut ? self.shortcut.keyCode : 0x41;
    _modifiers = self.shortcut ? self.shortcut.modifiers : KeyboardShortcutControl;
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:ShortcutText(@"editor.cancel") forState:UIControlStateNormal];
    cancel.accessibilityIdentifier = @"shortcut-editor-cancel";
    [cancel addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
    [save setTitle:ShortcutText(@"editor.save") forState:UIControlStateNormal];
    save.accessibilityIdentifier = @"shortcut-editor-save";
    [save addTarget:self action:@selector(save) forControlEvents:UIControlEventTouchUpInside];
    UILabel *title = [[UILabel alloc] init];
    title.text = ShortcutText(self.shortcut ? @"editor.edit" : @"editor.new");
    title.textColor = UIColor.labelColor; title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.textAlignment = NSTextAlignmentCenter;
    title.adjustsFontForContentSizeCategory = YES;
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[cancel, title, save]];
    header.spacing = 8; header.alignment = UIStackViewAlignmentCenter; header.translatesAutoresizingMaskIntoConstraints = NO;
    [cancel.widthAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [save.widthAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [cancel.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [save.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [cancel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [save setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [title setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
    [self.view addSubview:header];
    UIScrollView *scroll = [[UIScrollView alloc] init];
    _formScroll = scroll;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scroll];
    NSLayoutConstraint *keyboardBottom = [scroll.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor];
    keyboardBottom.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[[header.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:8],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [header.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        keyboardBottom, [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:0]]];
    UIStackView *form = [[UIStackView alloc] init]; form.axis = UILayoutConstraintAxisVertical; form.spacing = 14;
    form.translatesAutoresizingMaskIntoConstraints = NO; [scroll addSubview:form];
    [NSLayoutConstraint activateConstraints:@[[form.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12],
        [form.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [form.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [form.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [form.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]]];
    [form addArrangedSubview:[self label:ShortcutText(@"editor.name")]];
    _nameField = [[UITextField alloc] init]; _nameField.borderStyle = UITextBorderStyleRoundedRect;
    _nameField.text = self.shortcut.name; _nameField.placeholder = ShortcutText(@"editor.name_placeholder");
    _nameField.autocorrectionType = UITextAutocorrectionTypeNo; _nameField.delegate = self;
    _nameField.clearButtonMode = UITextFieldViewModeWhileEditing; _nameField.returnKeyType = UIReturnKeyDone;
    _nameField.accessibilityIdentifier = @"shortcut-editor-name";
    [_nameField.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [form addArrangedSubview:_nameField];
    [form addArrangedSubview:[self label:ShortcutText(@"editor.modifiers")]];
    NSMutableArray *buttons = [NSMutableArray array];
    NSArray *modifierItems = @[@[@"Ctrl", @(KeyboardShortcutControl)], @[@"Alt", @(KeyboardShortcutAlt)],
        @[@"Shift", @(KeyboardShortcutShift)], @[@"Win", @(KeyboardShortcutWindows)]];
    for (NSArray *item in modifierItems) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; button.tag = [item[1] integerValue];
        UIButtonConfiguration *configuration = [UIButtonConfiguration tintedButtonConfiguration]; configuration.title = item[0];
        configuration.contentInsets = NSDirectionalEdgeInsetsMake(8, 4, 8, 4); button.configuration = configuration;
        button.accessibilityIdentifier = [@"shortcut-modifier-" stringByAppendingString:item[0]];
        [button addTarget:self action:@selector(toggleModifier:) forControlEvents:UIControlEventTouchUpInside];
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES; [buttons addObject:button];
    }
    _modifierButtons = buttons;
    UIStackView *modifierRow = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    modifierRow.distribution = UIStackViewDistributionFillEqually; modifierRow.spacing = 6;
    [form addArrangedSubview:modifierRow];
    [form addArrangedSubview:[self label:ShortcutText(@"editor.key")]];
    _keyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _keyButton.configuration = [UIButtonConfiguration tintedButtonConfiguration];
    _keyButton.showsMenuAsPrimaryAction = YES; _keyButton.accessibilityIdentifier = @"shortcut-editor-key";
    [_keyButton.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES; [form addArrangedSubview:_keyButton];
    _combinationLabel = [self label:@""]; _combinationLabel.textAlignment = NSTextAlignmentCenter;
    _combinationLabel.font = [UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightMedium];
    _combinationLabel.accessibilityIdentifier = @"shortcut-editor-combination"; [form addArrangedSubview:_combinationLabel];
    _errorLabel = [self label:ShortcutText(@"editor.name_too_long")]; _errorLabel.textColor = UIColor.systemRedColor;
    _errorLabel.hidden = YES; [form addArrangedSubview:_errorLabel];
    if (self.shortcut) {
        UIButton *remove = [UIButton buttonWithType:UIButtonTypeSystem];
        [remove setTitle:ShortcutText(@"editor.delete") forState:UIControlStateNormal]; remove.tintColor = UIColor.systemRedColor;
        remove.accessibilityIdentifier = @"shortcut-editor-delete";
        [remove.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
        [remove addTarget:self action:@selector(remove) forControlEvents:UIControlEventTouchUpInside]; [form addArrangedSubview:remove];
    }
    [self updateCombination];
}
- (UILabel *)label:(NSString *)text {
    UILabel *label = [[UILabel alloc] init]; label.text = text; label.textColor = UIColor.labelColor;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    label.adjustsFontForContentSizeCategory = YES; label.numberOfLines = 0; return label;
}
- (void)toggleModifier:(UIButton *)button { _modifiers ^= button.tag; [self updateCombination]; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (_nameField.isFirstResponder && _formScroll.bounds.size.height > 0) {
        [_formScroll scrollRectToVisible:[_nameField convertRect:_nameField.bounds toView:_formScroll] animated:NO];
    }
}
- (void)updateCombination {
    for (UIButton *button in _modifierButtons) {
        BOOL selected = (_modifiers & button.tag) != 0;
        UIButtonConfiguration *configuration = button.configuration;
        configuration.baseForegroundColor = UIColor.labelColor;
        configuration.baseBackgroundColor = selected ? UIColor.systemPurpleColor : UIColor.tertiarySystemFillColor;
        button.configuration = configuration;
        button.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    }
    _combinationLabel.text = [[KeyboardShortcut alloc] initWithIdentifier:@"preview" name:@"" keyCode:_keyCode modifiers:_modifiers].combination;
    UIButtonConfiguration *configuration = _keyButton.configuration;
    configuration.title = [[KeyboardShortcut titleForKeyCode:_keyCode] stringByAppendingString:@"  ▾"]; _keyButton.configuration = configuration;
    NSMutableArray *actions = [NSMutableArray array]; __weak typeof(self) weakSelf = self;
    for (NSDictionary *key in KeyboardShortcut.keyChoices) {
        unsigned short code = [key[@"keyCode"] unsignedShortValue];
        UIAction *action = [UIAction actionWithTitle:key[@"title"] image:nil identifier:nil handler:^(UIAction *action) {
            KeyboardShortcutEditorViewController *editor = weakSelf; if (editor) { editor->_keyCode = code; [editor updateCombination]; }
        }];
        action.state = code == _keyCode ? UIMenuElementStateOn : UIMenuElementStateOff; [actions addObject:action];
    }
    _keyButton.menu = [UIMenu menuWithChildren:actions];
}
- (void)cancel { [self.view endEditing:YES]; if (self.completion) self.completion(nil, NO); }
- (void)save {
    KeyboardShortcut *shortcut = [[KeyboardShortcut alloc] initWithIdentifier:self.shortcut.identifier ?: NSUUID.UUID.UUIDString
        name:_nameField.text keyCode:_keyCode modifiers:_modifiers];
    if (!shortcut) { _errorLabel.hidden = NO; return; }
    [self.view endEditing:YES]; if (self.completion) self.completion(shortcut, NO);
}
- (void)remove { [self.view endEditing:YES]; if (self.completion) self.completion(self.shortcut, YES); }
- (BOOL)textFieldShouldReturn:(UITextField *)textField { [self save]; return NO; }
@end

@interface KeyboardShortcutsViewController () <UITableViewDataSource, UITableViewDelegate>
@end
@implementation KeyboardShortcutsViewController {
    KeyboardShortcutStore *_store;
    NSArray<KeyboardShortcut *> *_builtIn;
    NSArray<KeyboardShortcut *> *_custom;
    UITableView *_table;
    UIButton *_addButton;
    KeyboardShortcutEditorViewController *_editor;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = UIColor.blackColor;
    self.view.accessibilityIdentifier = @"sidebar-shortcuts";
    _store = [[KeyboardShortcutStore alloc] init]; _builtIn = KeyboardShortcut.builtInShortcuts;
    _addButton = [UIButton buttonWithType:UIButtonTypeSystem]; _addButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration *configuration = [UIButtonConfiguration tintedButtonConfiguration];
    configuration.title = ShortcutText(@"list.add"); configuration.image = [UIImage systemImageNamed:@"plus"];
    configuration.imagePadding = 6; configuration.baseForegroundColor = UIColor.labelColor;
    configuration.baseBackgroundColor = UIColor.systemPurpleColor; _addButton.configuration = configuration;
    _addButton.accessibilityIdentifier = @"shortcut-add";
    [_addButton addTarget:self action:@selector(addShortcut) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_addButton];
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _table.translatesAutoresizingMaskIntoConstraints = NO; _table.backgroundColor = UIColor.clearColor;
    _table.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _table.delegate = self; _table.dataSource = self; _table.rowHeight = UITableViewAutomaticDimension; _table.estimatedRowHeight = 56;
    _table.accessibilityIdentifier = @"shortcut-list"; [self.view addSubview:_table];
    [NSLayoutConstraint activateConstraints:@[[_addButton.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12],
        [_addButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_addButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_addButton.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [_table.topAnchor constraintEqualToAnchor:_addButton.bottomAnchor constant:8],
        [_table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [_table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_table.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor]]];
    [self reloadShortcuts];
}
- (void)reloadShortcuts { _custom = _store.customShortcuts; [_table reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? _builtIn.count : _custom.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return ShortcutText(section == 0 ? @"list.common" : @"list.custom"); }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return section == 1 && _custom.count == 0 ? ShortcutText(@"list.empty") : nil; }
- (KeyboardShortcut *)shortcutAtIndexPath:(NSIndexPath *)indexPath { return (indexPath.section == 0 ? _builtIn : _custom)[indexPath.row]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"shortcut"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"shortcut"];
    KeyboardShortcut *shortcut = [self shortcutAtIndexPath:indexPath];
    cell.textLabel.text = shortcut.name; cell.textLabel.numberOfLines = 2;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    cell.detailTextLabel.text = shortcut.combination; cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    cell.detailTextLabel.adjustsFontSizeToFitWidth = YES; cell.detailTextLabel.minimumScaleFactor = 0.7;
    cell.accessibilityIdentifier = [@"shortcut-row-" stringByAppendingString:shortcut.identifier];
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", shortcut.name, shortcut.combination];
    cell.accessibilityTraits = UIAccessibilityTraitButton;
    cell.accessoryView = nil;
    if (indexPath.section == 1) {
        UIButton *more = [UIButton buttonWithType:UIButtonTypeSystem]; more.frame = CGRectMake(0, 0, 44, 44);
        [more setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
        more.accessibilityIdentifier = [@"shortcut-more-" stringByAppendingString:shortcut.identifier];
        more.accessibilityLabel = ShortcutText(@"list.manage"); more.showsMenuAsPrimaryAction = YES;
        __weak typeof(self) weakSelf = self;
        UIAction *edit = [UIAction actionWithTitle:ShortcutText(@"editor.edit") image:[UIImage systemImageNamed:@"pencil"] identifier:nil handler:^(UIAction *action) { [weakSelf showEditor:shortcut]; }];
        UIAction *remove = [UIAction actionWithTitle:ShortcutText(@"editor.delete") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *action) {
            KeyboardShortcutsViewController *controller = weakSelf; if (!controller) return;
            [controller->_store removeShortcutWithIdentifier:shortcut.identifier]; [controller reloadShortcuts];
        }];
        remove.attributes = UIMenuElementAttributesDestructive; more.menu = [UIMenu menuWithChildren:@[edit, remove]]; cell.accessoryView = more;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.shortcutHandler) self.shortcutHandler([self shortcutAtIndexPath:indexPath]);
}
- (void)addShortcut { [self showEditor:nil]; }
- (void)showEditor:(KeyboardShortcut *)shortcut {
    if (_editor) return;
    if (self.editingHandler) self.editingHandler();
    _editor = [[KeyboardShortcutEditorViewController alloc] init]; _editor.shortcut = shortcut;
    __weak typeof(self) weakSelf = self;
    _editor.completion = ^(KeyboardShortcut *updated, BOOL remove) {
        KeyboardShortcutsViewController *controller = weakSelf; if (!controller) return;
        if (updated) {
            if (remove) [controller->_store removeShortcutWithIdentifier:updated.identifier]; else [controller->_store saveShortcut:updated];
        }
        [controller->_editor willMoveToParentViewController:nil]; [controller->_editor.view removeFromSuperview];
        [controller->_editor removeFromParentViewController]; controller->_editor = nil;
        controller->_table.hidden = NO; controller->_addButton.hidden = NO; [controller reloadShortcuts];
    };
    _table.hidden = YES; _addButton.hidden = YES;
    [self addChildViewController:_editor]; [self.view addSubview:_editor.view]; PinShortcutView(_editor.view, self.view);
    [_editor didMoveToParentViewController:self];
}
@end
