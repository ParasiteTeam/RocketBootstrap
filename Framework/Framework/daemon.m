//
//  daemon.c
//  Tweak
//
//  Created by Alexander Zielenski on 4/11/16.
//  Copyright © 2016 Parasite. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <sys/sysctl.h>

#define LIGHTMESSAGING_USE_ROCKETBOOTSTRAP 0
#import <rocketbootstrap_internal.h>
static NSMutableSet *allowedNames;
static volatile OSSpinLock namesLock;

void daemon_restarted_callback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    @autoreleasepool {
        OSSpinLockLock(&namesLock);
        NSSet *allNames = [allowedNames copy];
        OSSpinLockUnlock(&namesLock);
        for (NSString *name in allNames) {
            const char *service_name = [name UTF8String];
            LMConnectionSendOneWay(&connection, 0, service_name, (uint32_t)strlen(service_name));
        }
    }
}

static pid_t pid_of_process(const char *process_name)
{
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t miblen = 4;
    
    size_t size;
    int st = sysctl(mib, (u_int)miblen, NULL, &size, NULL, 0);
    
    struct kinfo_proc * process = NULL;
    struct kinfo_proc * newprocess = NULL;
    
    do {
        size += size / 10;
        newprocess = (struct kinfo_proc *)realloc(process, size);
        
        if (!newprocess) {
            if (process) {
                free(process);
            }
            return 0;
        }
        
        process = newprocess;
        st = sysctl(mib, (u_int)miblen, process, &size, NULL, 0);
        
    } while (st == -1 && errno == ENOMEM);
    
    if (st == 0) {
        if (size % sizeof(struct kinfo_proc) == 0) {
            int nprocess = (int)(size / sizeof(struct kinfo_proc));
            if (nprocess) {
                for (int i = nprocess - 1; i >= 0; i--) {
                    if (strcmp(process[i].kp_proc.p_comm, process_name) == 0) {
                        pid_t result = process[i].kp_proc.p_pid;
                        free(process);
                        return result;
                    }
                }
            }
        }
    }
    
    free(process);
    return 0;
}

static int daemon_die_queue;
static CFFileDescriptorRef daemon_die_fd;
static CFRunLoopSourceRef daemon_die_source;

static void process_terminate_callback(CFFileDescriptorRef fd, CFOptionFlags callBackTypes, void *info);

void observe_rocketd(void)
{
    // Force the daemon to load
    mach_port_t bootstrap = MACH_PORT_NULL;
    mach_port_t self = mach_task_self();
    task_get_bootstrap_port(self, &bootstrap);
    mach_port_t servicesPort = MACH_PORT_NULL;
    kern_return_t err = bootstrap_look_up(bootstrap, kRocketBootstrapUnlockService, &servicesPort);
    if (err) {
        //NSLog(@"RocketBootstrap: failed to launch rocketd!");
    } else {
        mach_port_name_t replyPort = MACH_PORT_NULL;
        err = mach_port_allocate(self, MACH_PORT_RIGHT_RECEIVE, &replyPort);
        if (err == 0) {
            LMResponseBuffer buffer;
            uint32_t size = LMBufferSizeForLength(0);
            memset(&buffer.message, 0, sizeof(LMMessage));
            buffer.message.head.msgh_id = 2;
            buffer.message.head.msgh_size = size;
            buffer.message.head.msgh_local_port = replyPort;
            buffer.message.head.msgh_reserved = 0;
            buffer.message.head.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND_ONCE);
            buffer.message.head.msgh_remote_port = servicesPort;
            buffer.message.body.msgh_descriptor_count = 0;
            buffer.message.data.in_line.length = 0;
            err = mach_msg(&buffer.message.head, MACH_SEND_MSG | MACH_RCV_MSG | _LIGHTMESSAGING_TIMEOUT_FLAGS, size, sizeof(LMResponseBuffer), replyPort, LIGHTMESSAGING_TIMEOUT, MACH_PORT_NULL);
            if (err) {
            }
            // Cleanup
            mach_port_mod_refs(self, replyPort, MACH_PORT_RIGHT_RECEIVE, -1);
        }
        mach_port_mod_refs(self, servicesPort, MACH_PORT_RIGHT_SEND, -1);
    }
    // Find it
    pid_t pid = pid_of_process("rocketd");
    if (pid) {
        //NSLog(@"RocketBootstrap: rocketd found: %d", pid);
        daemon_die_queue = kqueue();
        struct kevent changes;
        EV_SET(&changes, pid, EVFILT_PROC, EV_ADD | EV_RECEIPT, NOTE_EXIT, 0, NULL);
        (void)kevent(daemon_die_queue, &changes, 1, &changes, 1, NULL);
        daemon_die_fd = CFFileDescriptorCreate(NULL, daemon_die_queue, true, process_terminate_callback, NULL);
        daemon_die_source = CFFileDescriptorCreateRunLoopSource(NULL, daemon_die_fd, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), daemon_die_source, kCFRunLoopDefaultMode);
        CFFileDescriptorEnableCallBacks(daemon_die_fd, kCFFileDescriptorReadCallBack);
    } else {
        NSLog(@"RocketBootstrap: unable to find rocketd!");
    }
}

static void process_terminate_callback(CFFileDescriptorRef fd, CFOptionFlags callBackTypes, void *info)
{
    struct kevent event;
    (void)kevent(daemon_die_queue, NULL, 0, &event, 1, NULL);
    NSLog(@"RocketBootstrap: rocketd terminated: %d, relaunching", (int)(pid_t)event.ident);
    // Cleanup
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), daemon_die_source, kCFRunLoopDefaultMode);
    CFRelease(daemon_die_source);
    CFRelease(daemon_die_fd);
    close(daemon_die_queue);
    observe_rocketd();
}

void rocketbootstrap_track_name(const name_t service) {
    OSSpinLockLock(&namesLock);
    [allowedNames addObject:@(service)];
    OSSpinLockUnlock(&namesLock);
}

void rocketbootstrap_untrack_name(const name_t service) {
    OSSpinLockLock(&namesLock);
    [allowedNames removeObject:@(service)];
    OSSpinLockUnlock(&namesLock);
}

bool rocketbootstrap_is_tracking_name(const name_t service_name) {
    OSSpinLockLock(&namesLock);
    BOOL res = [allowedNames containsObject:@(service_name)];
    OSSpinLockUnlock(&namesLock);
    return res;
}
