#import <ParasiteRuntime/ParasiteRuntime.h>

#define LIGHTMESSAGING_USE_ROCKETBOOTSTRAP 0
#import <rocketbootstrap_internal.h>

#import <mach/mach.h>
#import <libkern/OSAtomic.h>
#import <libkern/OSCacheControl.h>
#import "daemon.h"

kern_return_t rocketbootstrap_unlock(const name_t service_name)
{
#if ALWAYS_UNLOCKED == 1
    return KERN_SUCCESS;
#else
	if (rocketbootstrap_is_passthrough())
		return 0;
    
    @autoreleasepool {
        NSString *serviceNameString = [NSString stringWithUTF8String:service_name];
        OSSpinLockLock(&namesLock);
        BOOL containedName;
        if (!allowedNames) {
            allowedNames = [[NSMutableSet alloc] init];
            [allowedNames addObject:serviceNameString];
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), &daemon_restarted_callback, daemon_restarted_callback, CFSTR("com.rpetrich.rocketd.started"), NULL, CFNotificationSuspensionBehaviorCoalesce);
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
#endif
}

static volatile OSSpinLock server_once_lock;
static boolean_t (*server_once_demux_orig)(mach_msg_header_t *, mach_msg_header_t *);
static bool continue_server_once;

static boolean_t new_demux(mach_msg_header_t *request, mach_msg_header_t *reply)
{
	// Highjack ROCKETBOOTSTRAP_LOOKUP_ID from the com.apple.ReportCrash.SimulateCrash demuxer
	if (request->msgh_id == ROCKETBOOTSTRAP_LOOKUP_ID) {
		continue_server_once = true;
		_rocketbootstrap_lookup_query_t *lookup_message = (_rocketbootstrap_lookup_query_t *)request;
		// Extract service name
		size_t length = request->msgh_size - offsetof(_rocketbootstrap_lookup_query_t, name);
		if (lookup_message->name_length <= length) {
			length = lookup_message->name_length;
		}
		// Ask rocketd if it's unlocked
#if ALWAYS_UNLOCKED == 1
        BOOL nameIsAllowed = YES;
#else
        LMResponseBuffer buffer;
        if (LMConnectionSendTwoWay(&connection, 1, &lookup_message->name[0], (uint32_t)length, &buffer))
			return false;
		BOOL nameIsAllowed = LMResponseConsumeInteger(&buffer) != 0;
#endif

		// Lookup service port
		mach_port_t servicePort = MACH_PORT_NULL;
		mach_port_t selfTask = mach_task_self();
		kern_return_t err;
		if (nameIsAllowed) {
			mach_port_t bootstrap = MACH_PORT_NULL;
			err = task_get_bootstrap_port(selfTask, &bootstrap);
			if (!err) {
				char *buffer = malloc(length + 1);
				if (buffer) {
					memcpy(buffer, lookup_message->name, length);
					buffer[length] = '\0';
					err = bootstrap_look_up(bootstrap, buffer, &servicePort);
					free(buffer);
				}
			}
		}
		// Generate response
		_rocketbootstrap_lookup_response_t response;
		response.head.msgh_id = 0;
		response.head.msgh_size = (sizeof(_rocketbootstrap_lookup_response_t) + 3) & ~3;
		response.head.msgh_remote_port = request->msgh_remote_port;
		response.head.msgh_local_port = MACH_PORT_NULL;
		response.head.msgh_reserved = 0;
		response.head.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_MOVE_SEND_ONCE, 0);
		if (servicePort != MACH_PORT_NULL) {
			response.head.msgh_bits |= MACH_MSGH_BITS_COMPLEX;
			response.body.msgh_descriptor_count = 1;
			response.response_port.name = servicePort;
			response.response_port.disposition = MACH_MSG_TYPE_COPY_SEND;
			response.response_port.type = MACH_MSG_PORT_DESCRIPTOR;
		} else {
			response.body.msgh_descriptor_count = 0;
		}
		// Send response
		err = mach_msg(&response.head, MACH_SEND_MSG, response.head.msgh_size, 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
		if (err) {
			if (servicePort != MACH_PORT_NULL)
				mach_port_mod_refs(selfTask, servicePort, MACH_PORT_RIGHT_SEND, -1);
			mach_port_mod_refs(selfTask, reply->msgh_remote_port, MACH_PORT_RIGHT_SEND_ONCE, -1);
		}
		return true;
	}
	return server_once_demux_orig(request, reply);
}

typedef boolean_t (*RBDemuxCallback)(mach_msg_header_t *, mach_msg_header_t *);

PSHook4(mach_msg_return_t, mach_msg_server_once, RBDemuxCallback, demux, mach_msg_size_t, max_size, mach_port_t, rcv_name, mach_msg_options_t, options)
{
	// Highjack com.apple.ReportCrash.SimulateCrash's use of mach_msg_server_once
	OSSpinLockLock(&server_once_lock);
	if (!server_once_demux_orig) {
		server_once_demux_orig = demux;
		demux = new_demux;
	} else if (server_once_demux_orig == demux) {
		demux = new_demux;
	} else {
		OSSpinLockUnlock(&server_once_lock);
		mach_msg_return_t result = PSOldCall(demux, max_size, rcv_name, options);
		return result;
	}
	OSSpinLockUnlock(&server_once_lock);
	mach_msg_return_t result;
	do {
		continue_server_once = false;
		result = PSOldCall(demux, max_size, rcv_name, options);
	} while (continue_server_once);
	return result;
}


// This tweak is used to allow other applications to piggy off of the dock's
// privileged mach services
ctor {
    PSHookFunction(mach_msg_server_once);
}
