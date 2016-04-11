//
//  RocketBootstrap.h
//  RocketBootstrap
//
//  Created by Alexander Zielenski on 4/11/16.
//  Copyright © 2016 Parasite. All rights reserved.
//

#import <Cocoa/Cocoa.h>

//! Project version number for RocketBootstrap.
FOUNDATION_EXPORT double RocketBootstrapVersionNumber;

//! Project version string for RocketBootstrap.
FOUNDATION_EXPORT const unsigned char RocketBootstrapVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <RocketBootstrap/PublicHeader.h>
#import <RocketBootstrap/bootstrap.h>

extern kern_return_t rocketbootstrap_unlock(const name_t service_name);
extern kern_return_t rocketbootstrap_look_up(mach_port_t bp, const name_t service_name, mach_port_t *sp);

#ifdef __COREFOUNDATION_CFMESSAGEPORT__
CFMessagePortRef rocketbootstrap_cfmessageportcreateremote(CFAllocatorRef allocator, CFStringRef name);
kern_return_t rocketbootstrap_cfmessageportexposelocal(CFMessagePortRef messagePort);
#endif