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
#import "daemon.h"
#import <xpc/xpc.h>

extern bool rocketbootstrap_name_is_tracked(const name_t);

kern_return_t bootstrap_look_up3(mach_port_t bp, const name_t service_name, mach_port_t *sp, pid_t target_pid, const uuid_t instance_id, uint64_t flags) __attribute__((weak_import));
PSHook6(kern_return_t, bootstrap_look_up3, mach_port_t, bp, const name_t, service_name, mach_port_t *, sp, pid_t, target_pid, const uuid_t, instance_id, uint64_t, flags) {
    @autoreleasepool {
        if (NSThread.currentThread.threadDictionary[@"rocketbootstrap_intercept_next_lookup"]) {
            NSThread.currentThread.threadDictionary[@"rocketbootstrap_intercept_next_lookup"] = nil;
            return rocketbootstrap_look_up3(bp, service_name, sp, target_pid, instance_id, flags);
        }
    }
    return PSOldCall(bp, service_name, sp, target_pid, instance_id, flags);
}

static void (*_xpc_connection_init)(xpc_connection_t connection);
PSHook1(void, _xpc_connection_init, xpc_connection_t, connection) {
    @autoreleasepool {
        if (connection != NULL && rocketbootstrap_is_tracking_connection(connection)) {
            NSThread.currentThread.threadDictionary[@"rocketbootstrap_intercept_next_lookup"] = @YES;
            PSOldCall(connection);
            NSThread.currentThread.threadDictionary[@"rocketbootstrap_intercept_next_lookup"] = nil;
        }
    }
    
    PSOldCall(connection);
}

PSHook1(void, xpc_connection_cancel, xpc_connection_t, connection) {
    rocketbootstrap_untrack_connection(connection);
    
    PSOldCall(connection);
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

void rocketbootstrap_xpc_connection_apply(xpc_connection_t connection) {
    const char *name = xpc_connection_get_name(connection);
    if (name == NULL)
        return;
    
    rocketbootstrap_track_connection(connection);
}

ctor {
    void *xpc = PSGetImageByName("/usr/lib/system/libxpc.dylib");
    _xpc_connection_init = PSFindSymbol(xpc, "__xpc_connection_init");
    if (_xpc_connection_init != NULL)
        PSHookFunction(_xpc_connection_init);
        
    PSHookFunction(xpc_connection_cancel);
    PSHookFunction(bootstrap_look_up3);
}

