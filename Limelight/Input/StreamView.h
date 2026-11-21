//
//  StreamView.h
//  Moonlight
//
//  Created by Cameron Gutman on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "ControllerSupport.h"
#import "OnScreenControls.h"
#import "Moonlight-Swift.h"
#import "StreamConfiguration.h"
#if !TARGET_OS_TV
@class KeyboardShortcut;
#endif

@protocol UserInteractionDelegate <NSObject>

- (void) userInteractionBegan;
- (void) userInteractionEnded;

@end

#if TARGET_OS_TV
@interface StreamView : UIView <X1KitMouseDelegate, UITextFieldDelegate>
#else
@interface StreamView : UIView <X1KitMouseDelegate, UITextFieldDelegate, UIPointerInteractionDelegate>
#endif

- (void) setupStreamView:(ControllerSupport*)controllerSupport
     interactionDelegate:(id<UserInteractionDelegate>)interactionDelegate
                  config:(StreamConfiguration*)streamConfig;
- (void) showOnScreenControls;
- (OnScreenControlsLevel) getCurrentOscState;
- (void)updateVideoWidth:(int)width height:(int)height;
#if !TARGET_OS_TV
- (UIView *)makeControlsSurface;
- (void)setSeparateControlsView:(UIView *)view;
- (void)cancelControlTouches;
- (void)applyOnScreenControlsLevel:(OnScreenControlsLevel)level;
@property (nonatomic, copy) void (^videoLayoutChanged)(void);
#endif

#if !TARGET_OS_TV
- (void)showKeyboard;
- (void)hideKeyboard;
@property (nonatomic, readonly, getter=isKeyboardVisible) BOOL keyboardVisible;
@property (nonatomic, copy) void (^keyboardVisibilityChanged)(BOOL visible);
- (void)sendKeyboardShortcut:(KeyboardShortcut *)shortcut;
- (void) updateCursorLocation:(CGPoint)location isMouse:(BOOL)isMouse;
#endif

@end
