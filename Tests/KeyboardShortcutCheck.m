#import <Foundation/Foundation.h>
#import "KeyboardShortcut.h"

static void Require(BOOL value, NSString *message) { if (!value) { fprintf(stderr, "%s\n", message.UTF8String); exit(1); } }

int main(void) {
    @autoreleasepool {
        KeyboardShortcut *taskManager = [[KeyboardShortcut alloc] initWithIdentifier:@"task-manager" name:@"任务管理器"
            keyCode:0x1B modifiers:KeyboardShortcutControl | KeyboardShortcutShift];
        Require([taskManager.combination isEqualToString:@"Ctrl+Shift+Esc"], @"Combination label is incorrect");
        NSArray *expectedCodes = @[@0x80A2, @0x80A0, @0x801B, @0x801B, @0x80A0, @0x80A2];
        NSArray *expectedModifiers = @[@2, @3, @3, @3, @2, @0];
        NSArray *events = taskManager.keyEvents;
        Require(events.count == 6, @"Multi-modifier shortcut lost a key event");
        for (NSUInteger index = 0; index < events.count; index++) {
            Require([events[index][@"keyCode"] isEqual:expectedCodes[index]], @"Shortcut press/release order is incorrect");
            Require([events[index][@"modifiers"] isEqual:expectedModifiers[index]], @"Modifier state was not restored");
            Require([events[index][@"down"] boolValue] == (index < 3), @"Shortcut key action is incorrect");
        }
        for (NSUInteger flags = 0; flags < 16; flags++) {
            KeyboardShortcut *shortcut = [[KeyboardShortcut alloc] initWithIdentifier:@"balanced" name:@"" keyCode:'X' modifiers:flags];
            NSMutableSet *held = [NSMutableSet set];
            for (NSDictionary *event in shortcut.keyEvents) {
                if ([event[@"down"] boolValue]) {
                    Require(![held containsObject:event[@"keyCode"]], @"A shortcut pressed a key twice");
                    [held addObject:event[@"keyCode"]];
                } else {
                    Require([held containsObject:event[@"keyCode"]], @"A shortcut released an unpressed key");
                    [held removeObject:event[@"keyCode"]];
                }
            }
            Require(held.count == 0 && [shortcut.keyEvents.lastObject[@"modifiers"] integerValue] == 0, @"A shortcut left a key or modifier held");
        }
        Require([KeyboardShortcut titleForKeyCode:0x87] != nil, @"F24 is not supported");
        Require([[KeyboardShortcut alloc] initWithIdentifier:@"invalid" name:@"Bad" keyCode:0xFF modifiers:0] == nil, @"Unsupported key was accepted");
        NSString *suite = [@"com.sidelantern.keyboard-shortcut-check." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        @try {
            KeyboardShortcutStore *store = [[KeyboardShortcutStore alloc] initWithDefaults:defaults];
            Require(store.customShortcuts.count == 0 && store.allShortcuts.count == 8, @"Initial shortcuts are incorrect");
            [store saveShortcut:taskManager];
            KeyboardShortcutStore *reopened = [[KeyboardShortcutStore alloc] initWithDefaults:[[NSUserDefaults alloc] initWithSuiteName:suite]];
            Require(reopened.customShortcuts.count == 1 && [reopened.customShortcuts.firstObject.name isEqualToString:@"任务管理器"], @"Saved shortcut did not reload");
            KeyboardShortcut *edited = [[KeyboardShortcut alloc] initWithIdentifier:taskManager.identifier name:@"桌面" keyCode:'D' modifiers:KeyboardShortcutWindows];
            [store saveShortcut:edited];
            Require(store.customShortcuts.count == 1 && [store.customShortcuts.firstObject.combination isEqualToString:@"Win+D"], @"Editing duplicated or lost a shortcut");
            NSDictionary *badKey = @{@"identifier":@"bad", @"name":@"bad", @"keyCode":@65537, @"modifiers":@0};
            NSDictionary *badModifiers = @{@"identifier":@"bad-modifiers", @"name":@"bad", @"keyCode":@65, @"modifiers":@16};
            [defaults setObject:@[edited.dictionaryRepresentation, edited.dictionaryRepresentation, badKey, badModifiers, @"invalid"] forKey:@"SideLantern.KeyboardShortcuts.v1"];
            Require(store.customShortcuts.count == 1, @"Corrupt or duplicate saved data was accepted");
            [store removeShortcutWithIdentifier:edited.identifier];
            Require(store.customShortcuts.count == 0, @"Shortcut deletion did not persist");
        } @finally { [defaults removePersistentDomainForName:suite]; }
        puts("Keyboard shortcut checks passed: balanced events, modifier order, F24, save/reload/edit/delete, corrupt records, duplicate records.");
    }
    return 0;
}
