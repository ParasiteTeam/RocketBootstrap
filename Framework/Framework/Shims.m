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

kern_return_t bootstrap_look_up3(mach_port_t bp, const name_t service_name, mach_port_t *sp, pid_t target_pid, const uuid_t instance_id, uint64_t flags) __attribute__((weak_import));
PSHook6(kern_return_t, bootstrap_look_up3, mach_port_t, bp, const name_t, service_name, mach_port_t *, sp, pid_t, target_pid, const uuid_t, instance_id, uint64_t, flags) {
    @autoreleasepool {
        if (NSThread.currentThread.threadDictionary[@"rocketbootstrap_intercept_next_lookup"]) {
            NSThread.currentThread.threadDictionary[@"rocketbootstrap_intercept_next_lookup"] = nil;
            return rocketbootstrap_look_up(bp, service_name, sp);
        }
    }
    return PSOldCall(bp, service_name, sp, target_pid, instance_id, flags);
}

CFMessagePortRef rocketbootstrap_cfmessageportcreateremote(CFAllocatorRef allocator, CFStringRef name) {
    if (rocketbootstrap_is_passthrough())
        return CFMessagePortCreateRemote(allocator, name);
    
    @autoreleasepool {
        NSThread.currentThread.threadDictionary[@"rocketbootstrap_intercept_next_lookup"] = @YES;
        CFMessagePortRef res =  CFMessagePortCreateRemote(allocator, name);
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
        kern_return_t result = rocketbootstrap_unlock([(__bridge NSString *)name UTF8String]);
        return result;
    }
}

ctor {
    PSHookFunction(bootstrap_look_up3);
}

