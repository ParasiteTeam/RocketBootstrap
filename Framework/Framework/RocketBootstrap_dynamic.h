// DONT INCLUDE DIRECTLY
// Set ROCKETBOOTSTRAP_LOAD_DYNAMIC and then include rocketbootstrap.h
#include <dlfcn.h>
#define LIBRARY_PATH "/Library/Frameworks/RocketBootstrap.framework/RocketBootstrap"

__attribute__((unused))
static kern_return_t rocketbootstrap_look_up(mach_port_t bp, const name_t service_name, mach_port_t *sp)
{
	static kern_return_t (*impl)(mach_port_t bp, const name_t service_name, mach_port_t *sp);
	if (!impl) {
		void *handle = dlopen(LIBRARY_PATH, RTLD_LAZY);
		if (handle)
			impl = dlsym(handle, "rocketbootstrap_look_up");
		if (!impl)
			impl = bootstrap_look_up;
	}
	return impl(bp, service_name, sp);
}

__attribute__((unused))
static kern_return_t rocketbootstrap_unlock(const name_t service_name)
{
	static kern_return_t (*impl)(const name_t service_name);
	if (!impl) {
		void *handle = dlopen(LIBRARY_PATH, RTLD_LAZY);
		if (handle)
			impl = dlsym(handle, "rocketbootstrap_unlock");
		if (!impl)
			return -1;
	}
	return impl(service_name);
}

#ifdef __COREFOUNDATION_CFMESSAGEPORT__
__attribute__((unused))
static CFMessagePortRef rocketbootstrap_cfmessageportcreateremote(CFAllocatorRef allocator, CFStringRef name)
{
	static CFMessagePortRef (*impl)(CFAllocatorRef allocator, CFStringRef name);
	if (!impl) {
		void *handle = dlopen(LIBRARY_PATH, RTLD_LAZY);
		if (handle)
			impl = dlsym(handle, "rocketbootstrap_cfmessageportcreateremote");
		if (!impl)
			impl = CFMessagePortCreateRemote;
	}
	return impl(allocator, name);
}
__attribute__((unused))
static kern_return_t rocketbootstrap_cfmessageportexposelocal(CFMessagePortRef messagePort)
{
	static kern_return_t (*impl)(CFMessagePortRef messagePort);
	if (!impl) {
		void *handle = dlopen(LIBRARY_PATH, RTLD_LAZY);
		if (handle)
			impl = dlsym(handle, "rocketbootstrap_cfmessageportexposelocal");
		if (!impl)
			return -1;
	}
	return impl(messagePort);
}
#endif

