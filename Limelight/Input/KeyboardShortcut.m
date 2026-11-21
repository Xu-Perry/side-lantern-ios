#import "KeyboardShortcut.h"

NSNotificationName const KeyboardShortcutsDidChangeNotification = @"SideLantern.KeyboardShortcutsChanged";
static NSString *const ShortcutDefaultsKey = @"SideLantern.KeyboardShortcuts.v1";

@implementation KeyboardShortcut

- (instancetype)initWithIdentifier:(NSString *)identifier name:(NSString *)name keyCode:(unsigned short)keyCode modifiers:(KeyboardShortcutModifiers)modifiers {
    if (identifier.length == 0 || [KeyboardShortcut titleForKeyCode:keyCode] == nil || (modifiers & ~0x0F)) return nil;
    if ((self = [super init])) {
        _identifier = [identifier copy]; _keyCode = keyCode; _modifiers = modifiers;
        NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        _name = trimmed.length ? [trimmed copy] : self.combination;
        if (_name.length > 64) return nil;
    }
    return self;
}

+ (NSArray<NSDictionary *> *)keyChoices {
    static NSArray *choices;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *keys = [NSMutableArray array];
        NSArray *special = @[@[@0x1B, @"Esc"], @[@0x09, @"Tab"], @[@0x0D, @"Enter"], @[@0x20, @"Space"],
            @[@0x08, @"Backspace"], @[@0x2E, @"Delete"], @[@0x24, @"Home"], @[@0x23, @"End"],
            @[@0x21, @"Page Up"], @[@0x22, @"Page Down"], @[@0x25, @"←"], @[@0x26, @"↑"],
            @[@0x27, @"→"], @[@0x28, @"↓"], @[@0x2D, @"Insert"], @[@0x2C, @"Print Screen"],
            @[@0x14, @"Caps Lock"], @[@0xBD, @"-"], @[@0xBB, @"="], @[@0xDB, @"["], @[@0xDD, @"]"],
            @[@0xDC, @"\\"], @[@0xBA, @";"], @[@0xDE, @"'"], @[@0xC0, @"`"], @[@0xBC, @","], @[@0xBE, @"."], @[@0xBF, @"/"]];
        for (NSArray *key in special) [keys addObject:@{@"keyCode":key[0], @"title":key[1]}];
        for (int code = 'A'; code <= 'Z'; code++) [keys addObject:@{@"keyCode":@(code), @"title":[NSString stringWithFormat:@"%c", code]}];
        for (int code = '0'; code <= '9'; code++) [keys addObject:@{@"keyCode":@(code), @"title":[NSString stringWithFormat:@"%c", code]}];
        for (int number = 1; number <= 24; number++) [keys addObject:@{@"keyCode":@(0x6F + number), @"title":[NSString stringWithFormat:@"F%d", number]}];
        choices = [keys copy];
    });
    return choices;
}

+ (NSString *)titleForKeyCode:(unsigned short)keyCode {
    for (NSDictionary *key in self.keyChoices) if ([key[@"keyCode"] unsignedShortValue] == keyCode) return key[@"title"];
    return nil;
}

- (NSString *)combination {
    NSMutableArray *parts = [NSMutableArray array];
    if (_modifiers & KeyboardShortcutControl) [parts addObject:@"Ctrl"];
    if (_modifiers & KeyboardShortcutAlt) [parts addObject:@"Alt"];
    if (_modifiers & KeyboardShortcutShift) [parts addObject:@"Shift"];
    if (_modifiers & KeyboardShortcutWindows) [parts addObject:@"Win"];
    [parts addObject:[KeyboardShortcut titleForKeyCode:_keyCode]];
    return [parts componentsJoinedByString:@"+"];
}

- (NSDictionary *)dictionaryRepresentation {
    return @{@"identifier":_identifier, @"name":_name, @"keyCode":@(_keyCode), @"modifiers":@(_modifiers)};
}

+ (instancetype)shortcutFromDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class] || ![dictionary[@"identifier"] isKindOfClass:NSString.class] ||
        ![dictionary[@"name"] isKindOfClass:NSString.class] || ![dictionary[@"keyCode"] isKindOfClass:NSNumber.class] ||
        ![dictionary[@"modifiers"] isKindOfClass:NSNumber.class]) return nil;
    NSInteger key = [dictionary[@"keyCode"] integerValue];
    NSInteger modifiers = [dictionary[@"modifiers"] integerValue];
    if (key < 1 || key > 255 || modifiers < 0 || modifiers > 15) return nil;
    return [[self alloc] initWithIdentifier:dictionary[@"identifier"] name:dictionary[@"name"] keyCode:key modifiers:modifiers];
}

- (NSArray<NSDictionary *> *)keyEvents {
    NSMutableArray *events = [NSMutableArray array];
    NSArray *modifiers = @[@[@(KeyboardShortcutControl), @0xA2], @[@(KeyboardShortcutAlt), @0xA4],
        @[@(KeyboardShortcutShift), @0xA0], @[@(KeyboardShortcutWindows), @0x5B]];
    NSUInteger held = 0;
    for (NSArray *modifier in modifiers) {
        NSUInteger flag = [modifier[0] unsignedIntegerValue];
        if (_modifiers & flag) {
            held |= flag;
            [events addObject:@{@"keyCode":@([modifier[1] unsignedShortValue] | 0x8000), @"down":@YES, @"modifiers":@(held)}];
        }
    }
    [events addObject:@{@"keyCode":@(_keyCode | 0x8000), @"down":@YES, @"modifiers":@(held)}];
    [events addObject:@{@"keyCode":@(_keyCode | 0x8000), @"down":@NO, @"modifiers":@(held)}];
    for (NSArray *modifier in modifiers.reverseObjectEnumerator) {
        NSUInteger flag = [modifier[0] unsignedIntegerValue];
        if (_modifiers & flag) {
            held &= ~flag;
            [events addObject:@{@"keyCode":@([modifier[1] unsignedShortValue] | 0x8000), @"down":@NO, @"modifiers":@(held)}];
        }
    }
    return events;
}

+ (NSArray<KeyboardShortcut *> *)builtInShortcuts {
    NSArray *definitions = @[@[@"copy", @"C", @0x43, @2], @[@"paste", @"V", @0x56, @2], @[@"cut", @"X", @0x58, @2],
        @[@"undo", @"Z", @0x5A, @2], @[@"select_all", @"A", @0x41, @2], @[@"switch_app", @"Tab", @0x09, @4],
        @[@"show_desktop", @"D", @0x44, @8], @[@"task_manager", @"Esc", @0x1B, @3]];
    NSMutableArray *shortcuts = [NSMutableArray array];
    for (NSArray *item in definitions) {
        NSString *name = NSLocalizedStringFromTable([@"shortcut." stringByAppendingString:item[0]], @"KeyboardShortcuts", nil);
        [shortcuts addObject:[[self alloc] initWithIdentifier:[@"builtin." stringByAppendingString:item[0]] name:name
            keyCode:[item[2] unsignedShortValue] modifiers:[item[3] unsignedIntegerValue]]];
    }
    return shortcuts;
}
@end

@implementation KeyboardShortcutStore {
    NSUserDefaults *_defaults;
}
- (instancetype)init { return [self initWithDefaults:NSUserDefaults.standardUserDefaults]; }
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) _defaults = defaults;
    return self;
}
- (NSArray<KeyboardShortcut *> *)customShortcuts {
    id saved = [_defaults objectForKey:ShortcutDefaultsKey];
    if (![saved isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *shortcuts = [NSMutableArray array]; NSMutableSet *identifiers = [NSMutableSet set];
    for (id value in saved) {
        KeyboardShortcut *shortcut = [KeyboardShortcut shortcutFromDictionary:value];
        if (shortcut && ![shortcut.identifier hasPrefix:@"builtin."] && ![identifiers containsObject:shortcut.identifier]) {
            [shortcuts addObject:shortcut]; [identifiers addObject:shortcut.identifier];
        }
    }
    return shortcuts;
}
- (NSArray<KeyboardShortcut *> *)allShortcuts { return [KeyboardShortcut.builtInShortcuts arrayByAddingObjectsFromArray:self.customShortcuts]; }
- (void)writeShortcuts:(NSArray<KeyboardShortcut *> *)shortcuts {
    NSMutableArray *values = [NSMutableArray array];
    for (KeyboardShortcut *shortcut in shortcuts) [values addObject:shortcut.dictionaryRepresentation];
    [_defaults setObject:values forKey:ShortcutDefaultsKey];
    [NSNotificationCenter.defaultCenter postNotificationName:KeyboardShortcutsDidChangeNotification object:self];
}
- (void)saveShortcut:(KeyboardShortcut *)shortcut {
    if (!shortcut || [shortcut.identifier hasPrefix:@"builtin."]) return;
    NSMutableArray *shortcuts = [self.customShortcuts mutableCopy];
    NSUInteger index = [shortcuts indexOfObjectPassingTest:^BOOL(KeyboardShortcut *existing, NSUInteger idx, BOOL *stop) {
        return [existing.identifier isEqualToString:shortcut.identifier];
    }];
    if (index == NSNotFound) [shortcuts addObject:shortcut]; else shortcuts[index] = shortcut;
    [self writeShortcuts:shortcuts];
}
- (void)removeShortcutWithIdentifier:(NSString *)identifier {
    NSMutableArray *shortcuts = [self.customShortcuts mutableCopy];
    NSIndexSet *indexes = [shortcuts indexesOfObjectsPassingTest:^BOOL(KeyboardShortcut *shortcut, NSUInteger idx, BOOL *stop) {
        return [shortcut.identifier isEqualToString:identifier];
    }];
    if (indexes.count == 0) return;
    [shortcuts removeObjectsAtIndexes:indexes]; [self writeShortcuts:shortcuts];
}
@end
