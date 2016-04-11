#import <CoreFoundation/CoreFoundation.h>

#import "rocketbootstrap.h"

#define kRocketBootstrapUnlockService "com.rpetrich.rocketbootstrapd"
#define ALWAYS_UNLOCKED 0
#define ROCKETBOOTSTRAP_LOOKUP_ID -1

#ifndef kCFCoreFoundationVersionNumber_iOS_5_0
    #define kCFCoreFoundationVersionNumber_iOS_5_0 UINT_MAX
#endif
#import <LightMessaging/LightMessaging.h>

typedef struct {
	mach_msg_header_t head;
	mach_msg_body_t body;
	uint32_t name_length;
	char name[];
} _rocketbootstrap_lookup_query_t;

typedef struct {
	mach_msg_header_t head;
	mach_msg_body_t body;
	mach_msg_port_descriptor_t response_port;
} _rocketbootstrap_lookup_response_t;

#import "LightMessaging/LightMessaging.h"

__attribute__((unused))
static LMConnection connection = {
	MACH_PORT_NULL,
	kRocketBootstrapUnlockService
};

__attribute__((unused))
static inline bool rocketbootstrap_is_passthrough(void)
{
    return false;
}
