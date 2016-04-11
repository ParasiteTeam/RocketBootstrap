//
//  Shims.m
//  RocketBootstrap
//
//  Created by Alexander Zielenski on 4/11/16.
//  Copyright © 2016 Parasite. All rights reserved.
//

#import <ParasiteRuntime/ParasiteRuntime.h>
#import <RocketBootstrap/RocketBootstrap.h>
#import "bootstrap_priv.h"
#import "rocketbootstrap_internal.h"

#ifndef _SANDBOX_H_
extern int sandbox_check(pid_t pid, const char *operation, enum sandbox_filter_type type, ...);
#endif

int (*sandbox_check_old)(pid_t pid, const char *operation, enum sandbox_filter_type type, ...);
int sandbox_check_new(pid_t pid, const char *operation, enum sandbox_filter_type type, ...) {
    if (operation != NULL && strcmp("distributed-notification-post", operation) == 0)
        return 0;
    
    va_list args;
    va_start(args, type);
    return sandbox_check_old(pid, operation, type, args);
}

PSHook5(kern_return_t, bootstrap_look_up2, mach_port_t, bp, const name_t, service_name, mach_port_t *, sp, pid_t, target_pid, uint64_t, flags) {
    @autoreleasepool {
        if (NSThread.currentThread.threadDictionary[@"rocketbootstrap_intercept_next_lookup"]) {
            NSThread.currentThread.threadDictionary[@"rocketbootstrap_intercept_next_lookup"] = nil;
            return rocketbootstrap_look_up(bp, service_name, sp);
        }
    }
    return PSOldCall(bp, service_name, sp, target_pid, flags);
}

PSHook2(CFMessagePortRef, CFMessagePortCreateRemote, CFAllocatorRef, allocator, CFStringRef, name) {
    if (rocketbootstrap_is_passthrough())
        return PSOldCall(allocator, name);
    
    @autoreleasepool {
        NSThread.currentThread.threadDictionary[@"rocketbootstrap_intercept_next_lookup"] = @YES;
        CFMessagePortRef res =  PSOldCall(allocator, name);
        NSThread.currentThread.threadDictionary[@"rocketbootstrap_intercept_next_lookup"] = nil;
        return res;
    }
}


kern_return_t rocketbootstrap_cfmessageportexposelocal(CFMessagePortRef messagePort)
{
	if (rocketbootstrap_is_passthrough())
		return 0;
	CFStringRef name = CFMessagePortGetName(messagePort);
	if (!name)
		return -1;
    @autoreleasepool {
//        kern_return_t result = rocketbootstrap_unlock([(__bridge NSString *)name UTF8String]);
        return KERN_SUCCESS;
    }
}

ctor {
    PSHookFunction(CFMessagePortCreateRemote);
    PSHookFunction(bootstrap_look_up2);
    PSHookFunctionPtr((void *)sandbox_check, (void *)sandbox_check_new, (void **)&sandbox_check_old);
}

