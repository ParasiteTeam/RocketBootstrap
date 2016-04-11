//
//  RocketBootstrap.h
//  RocketBootstrap
//
//  Created by Alexander Zielenski on 4/11/16.
//  Copyright © 2016 Parasite. All rights reserved.
//
#include <sys/cdefs.h>
#include <mach/mach.h>

__BEGIN_DECLS

#include <RocketBootstrap/bootstrap.h>

#ifndef ROCKETBOOTSTRAP_LOAD_DYNAMIC
kern_return_t rocketbootstrap_unlock(const name_t service_name);
kern_return_t rocketbootstrap_look_up(mach_port_t bp, const name_t service_name, mach_port_t *sp);

#ifdef __COREFOUNDATION_CFMESSAGEPORT__

CFMessagePortRef rocketbootstrap_cfmessageportcreateremote(CFAllocatorRef allocator, CFStringRef name);
kern_return_t rocketbootstrap_cfmessageportexposelocal(CFMessagePortRef messagePort);

#endif

#else

#include <RocketBootstrap/RocketBootstrap_dynamic.h>

#endif
__END_DECLS