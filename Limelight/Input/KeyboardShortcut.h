#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSUInteger, KeyboardShortcutModifiers) {
    KeyboardShortcutShift = 0x01,
    KeyboardShortcutControl = 0x02,
    KeyboardShortcutAlt = 0x04,
    KeyboardShortcutWindows = 0x08,
};

FOUNDATION_EXPORT NSNotificationName const KeyboardShortcutsDidChangeNotification;

@interface KeyboardShortcut : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, readonly) unsigned short keyCode;
@property (nonatomic, readonly) KeyboardShortcutModifiers modifiers;
@property (nonatomic, copy, readonly) NSString *combination;
@property (nonatomic, readonly) NSDictionary *dictionaryRepresentation;
@property (nonatomic, readonly) NSArray<NSDictionary *> *keyEvents;
- (instancetype)initWithIdentifier:(NSString *)identifier name:(NSString *)name keyCode:(unsigned short)keyCode modifiers:(KeyboardShortcutModifiers)modifiers;
+ (instancetype)shortcutFromDictionary:(NSDictionary *)dictionary;
+ (NSArray<NSDictionary *> *)keyChoices;
+ (NSString *)titleForKeyCode:(unsigned short)keyCode;
+ (NSArray<KeyboardShortcut *> *)builtInShortcuts;
@end

@interface KeyboardShortcutStore : NSObject
@property (nonatomic, readonly) NSArray<KeyboardShortcut *> *customShortcuts;
@property (nonatomic, readonly) NSArray<KeyboardShortcut *> *allShortcuts;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (void)saveShortcut:(KeyboardShortcut *)shortcut;
- (void)removeShortcutWithIdentifier:(NSString *)identifier;
@end
