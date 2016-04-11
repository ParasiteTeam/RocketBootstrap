//
//  RocketBootstrap.m
//  Framework
//
//  Created by Alexander Zielenski on 4/11/16.
//  Copyright © 2016 Parasite. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <ParasiteRuntime/ParasiteRuntime.h>
#import "rocketbootstrap_internal.h"
#import "daemon.h"

BOOL isDaemon;

kern_return_t rocketbootstrap_look_up3(mach_port_t bp, const name_t service_name, mach_port_t *sp, pid_t target_pid, const uuid_t instance_id, uint64_t flags)
{
    if (rocketbootstrap_is_passthrough() || isDaemon) {
        int sandbox_result = sandbox_check(getpid(), "mach-lookup", SANDBOX_FILTER_LOCAL_NAME | SANDBOX_CHECK_NO_REPORT, service_name);
        if (sandbox_result) {
            return sandbox_result;
        }
        return bootstrap_look_up(bp, service_name, sp);
    }
    mach_port_t servicesPort = MACH_PORT_NULL;
    kern_return_t err = bootstrap_look_up(bp, kRocketBootstrapService, &servicesPort);
    if (err)
        return err;
    mach_port_t selfTask = mach_task_self();
    // Create a reply port
    mach_port_name_t replyPort = MACH_PORT_NULL;
    err = mach_port_allocate(selfTask, MACH_PORT_RIGHT_RECEIVE, &replyPort);
    if (err) {
        mach_port_deallocate(selfTask, servicesPort);
        return err;
    }
    // Send message
    size_t service_name_size = strlen(service_name);
    size_t size = (sizeof(_rocketbootstrap_lookup_query_t) + service_name_size + 3) & ~3;
    if (size < sizeof(_rocketbootstrap_lookup_response_t)) {
        size = sizeof(_rocketbootstrap_lookup_response_t);
    }
    char buffer[size];
    _rocketbootstrap_lookup_query_t *message = (_rocketbootstrap_lookup_query_t *)&buffer[0];
    memset(message, 0, sizeof(_rocketbootstrap_lookup_response_t));
    message->head.msgh_id = ROCKETBOOTSTRAP_LOOKUP_ID;
    message->head.msgh_size = (mach_msg_size_t)size;
    message->head.msgh_remote_port = servicesPort;
    message->head.msgh_local_port = replyPort;
    message->head.msgh_reserved = 0;
    message->head.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND_ONCE);
    message->target_pid = target_pid;
    memcpy(message->instance_id, instance_id, sizeof(uuid_t));
    message->flags = flags;
    message->name_length = (unsigned int)service_name_size;
    memcpy(&message->name[0], service_name, service_name_size);
    err = mach_msg(&message->head, MACH_SEND_MSG | MACH_RCV_MSG | MACH_RCV_TIMEOUT, (mach_msg_size_t)size, (mach_msg_size_t)size, replyPort, 200, MACH_PORT_NULL);
    // Parse response
    if (!err) {
        _rocketbootstrap_lookup_response_t *response = (_rocketbootstrap_lookup_response_t *)message;
        if (response->body.msgh_descriptor_count)
            *sp = response->response_port.name;
        else
            err = 1;
    }
    // Cleanup
    mach_port_deallocate(selfTask, servicesPort);
    mach_port_deallocate(selfTask, replyPort);
    return err;
}

kern_return_t rocketbootstrap_look_up(mach_port_t bp, const name_t service_name, mach_port_t *sp)
{
    uuid_t instance_id = { 0 };
    return rocketbootstrap_look_up3(bp, service_name, sp, 0, instance_id, 0);
}

kern_return_t rocketbootstrap_unlock(const name_t service_name)
{
    if (rocketbootstrap_is_passthrough())
        return 0;
    
    @autoreleasepool {
        NSString *serviceNameString = [NSString stringWithUTF8String:service_name];
        OSSpinLockLock(&namesLock);
        BOOL containedName;
        if (!allowedNames) {
            allowedNames = [[NSMutableSet alloc] init];
            [allowedNames addObject:serviceNameString];
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), &daemon_restarted_callback, daemon_restarted_callback, CFSTR("com.parasite.rocketd.started"), NULL, CFNotificationSuspensionBehaviorCoalesce);
            containedName = NO;
        } else {
            containedName = [allowedNames containsObject:serviceNameString];
            if (!containedName) {
                [allowedNames addObject:serviceNameString];
            }
        }
        OSSpinLockUnlock(&namesLock);
        if (containedName) {
            return 0;
        }
        // Ask rocketd to unlock it for us
        int sandbox_result = sandbox_check(getpid(), "mach-lookup", SANDBOX_FILTER_LOCAL_NAME | SANDBOX_CHECK_NO_REPORT, kRocketBootstrapUnlockService);
        if (sandbox_result) {
            return sandbox_result;
        }
        return LMConnectionSendOneWay(&connection, 0, service_name, (uint32_t)strlen(service_name));
    }
}

kern_return_t rocketbootstrap_xpc_unlock(xpc_connection_t connection) {
    const char *name = xpc_connection_get_name(connection);
    if (name == NULL)
        return KERN_INVALID_NAME;
    
    return rocketbootstrap_unlock(name);
}

