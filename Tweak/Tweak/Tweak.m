#import <ParasiteRuntime/ParasiteRuntime.h>
#import "rocketbootstrap_internal.h"

#import <mach/mach.h>
#import <libkern/OSAtomic.h>

extern BOOL isDaemon;
extern void observe_rocketd();

static void new_demux(mach_msg_header_t *request)
{
	// Highjack ROCKETBOOTSTRAP_LOOKUP_ID from the com.apple.ReportCrash.SimulateCrash demuxer
	if (request->msgh_id == ROCKETBOOTSTRAP_LOOKUP_ID) {
		_rocketbootstrap_lookup_query_t *lookup_message = (_rocketbootstrap_lookup_query_t *)request;
		// Extract service name
		size_t length = request->msgh_size - offsetof(_rocketbootstrap_lookup_query_t, name);
		if (lookup_message->name_length <= length) {
			length = lookup_message->name_length;
		}
		// Ask rocketd if it's unlocked
        LMResponseBuffer buffer;
        if (LMConnectionSendTwoWay(&connection, 1, &lookup_message->name[0], (uint32_t)length, &buffer))
			return;
		BOOL nameIsAllowed = LMResponseConsumeInteger(&buffer) != 0;

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
			mach_port_mod_refs(selfTask, request->msgh_remote_port, MACH_PORT_RIGHT_SEND_ONCE, -1);
		}
	}
}


static mach_port_t _sp;

PSHook7(mach_msg_return_t, mach_msg, mach_msg_header_t *, msg, mach_msg_option_t, option, mach_msg_size_t, send_size, mach_msg_size_t, rcv_size, mach_port_name_t, rcv_name, mach_msg_timeout_t, timeout, mach_port_name_t, notify) {
    mach_msg_return_t res = PSOldCall(msg, option, send_size, rcv_size, rcv_name, timeout, notify);
    
    if (msg->msgh_local_port == _sp && msg->msgh_id == ROCKETBOOTSTRAP_LOOKUP_ID) {
        new_demux(msg);
        
        return PSOldCall(msg, option, send_size, rcv_size, rcv_name, timeout, notify);
    }
    
    return res;
}

PSHook3(kern_return_t, bootstrap_check_in, mach_port_t, bp, const char *, service, mach_port_t *, sp) {
    kern_return_t res = PSOldCall(bp, service, sp);
    
    if (res == KERN_SUCCESS &&
        sp != NULL && _sp == 0 &&
        service != NULL && strcmp(service, kRocketBootstrapService) == 0) {
        _sp = *sp;
    }
    
    return res;
}

// This tweak is used to allow other applications to piggy off of the dock's
// privileged mach services
ctor {
    isDaemon = YES;

    observe_rocketd();
    
    PSHookFunction(bootstrap_check_in);
    PSHookFunction(mach_msg);
}
