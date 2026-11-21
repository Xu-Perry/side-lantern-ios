//
//  AbsoluteTouchHandler.h
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

#import "StreamView.h"

NS_ASSUME_NONNULL_BEGIN

@interface AbsoluteTouchHandler : UIResponder

-(id)initWithView:(StreamView*)view;
- (void)cancelTouches;

@end

NS_ASSUME_NONNULL_END
