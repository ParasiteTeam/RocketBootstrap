//
//  daemon.h
//  Tweak
//
//  Created by Alexander Zielenski on 4/11/16.
//  Copyright © 2016 Parasite. All rights reserved.
//

#ifndef daemon_h
#define daemon_h


#if ALWAYS_UNLOCKED != 1
#pragma GCC visibility push(hidden)
#import <Foundation/Foundation.h>
#import <rocketbootstrap_internal.h>

extern NSMutableSet *allowedNames;
extern volatile OSSpinLock namesLock;

#pragma GCC visibility pop

extern void daemon_restarted_callback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);

#endif

#endif /* daemon_h */
