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

BOOL isDaemon;

static kern_return_t rocketbootstrap_look_up_with_timeout(mach_port_t bp, const name_t service_name, mach_port_t *sp, mach_msg_timeout_t timeout)
{
    if (rocketbootstrap_is_passthrough() || isDaemon) {
        if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_5_0) {
            int sandbox_result = sandbox_check(getpid(), "mach-lookup", SANDBOX_FILTER_LOCAL_NAME | SANDBOX_CHECK_NO_REPORT, service_name);
            if (sandbox_result) {
                return sandbox_result;
            }
        }
        return bootstrap_look_up(bp, service_name, sp);
    }

    // Ask our service running inside of the kRocketBootstrapService job
    mach_port_t servicesPort = MACH_PORT_NULL;
    kern_return_t err = bootstrap_look_up(bp, kRocketBootstrapService, &servicesPort);
    
    if (err) {
        return err;
    }
    
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
    message->name_length = (unsigned int)service_name_size;
    memcpy(&message->name[0], service_name, service_name_size);
    mach_msg_option_t options = MACH_SEND_MSG | MACH_RCV_MSG;
    
    if (timeout == 0) {
        timeout = MACH_MSG_TIMEOUT_NONE;
    } else {
        options |= MACH_SEND_TIMEOUT | MACH_RCV_TIMEOUT;
    }
    err = mach_msg(&message->head, options, (mach_msg_size_t)size, (mach_msg_size_t)size, replyPort, timeout, MACH_PORT_NULL);
    
    // Parse response
    if (!err) {
        _rocketbootstrap_lookup_response_t *response = (_rocketbootstrap_lookup_response_t *)message;
        if (response->body.msgh_descriptor_count)
            *sp = response->response_port.name;
        else
            err = 1;
    }
    
    NSLog(@"RocketBootstrap FUK4 0x%x", err);
    
    // Cleanup
    mach_port_deallocate(selfTask, servicesPort);
    mach_port_deallocate(selfTask, replyPort);
    return err;
}

kern_return_t rocketbootstrap_look_up(mach_port_t bp, const name_t service_name, mach_port_t *sp) {
    return rocketbootstrap_look_up_with_timeout(bp, service_name, sp, LIGHTMESSAGING_TIMEOUT);
}


