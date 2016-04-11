//
//  daemon.h
//  Framework
//
//  Created by Alexander Zielenski on 4/11/16.
//  Copyright © 2016 Parasite. All rights reserved.
//

#ifndef daemon_h
#define daemon_h

#pragma GCC visibility push(hidden)
static NSMutableSet *allowedNames;
static volatile OSSpinLock namesLock;

void observe_rocketd(void);
void rocketbootstrap_track_name(const name_t service);
void rocketbootstrap_untrack_name(const name_t service);
bool rocketbootstrap_is_tracking_name(const name_t service_name);
void daemon_restarted_callback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
kern_return_t rocketbootstrap_look_up3(mach_port_t bp, const name_t service_name, mach_port_t *sp, pid_t target_pid, const uuid_t instance_id, uint64_t flags);

#pragma GCC visibility pop

#endif /* daemon_h */
