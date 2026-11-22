//
//  ADXRemoteCompat.m
//  App 扩展层 — 远程调用适配层
//
//  与第三方源码里的 TaskRop/RemoteCall、SKKernelLock 对接。会话按线程保存，
//  期间持有内核锁（RemoteCall 会改 vm entry，不能与其它内核操作并发）。
//
#import "ADXRemoteCompat.h"
#import "ADXInternal.h"
#import "RemoteCall.h"
#import "SKKernelLock.h"
#import "darksword.h"
#import <dlfcn.h>

static _Thread_local void *g_rc_ptr = NULL;      // +1 retained RemoteCall
static _Thread_local BOOL g_lock_held = NO;

static NSString *g_adx_attach_error = nil;
static NSLock *g_adx_attach_lock = nil;

static void adx_set_attach_error(NSString *msg) {
    if (!g_adx_attach_lock) g_adx_attach_lock = [NSLock new];
    [g_adx_attach_lock lock];
    g_adx_attach_error = [msg copy];
    [g_adx_attach_lock unlock];
}

NSString *adx_last_attach_error(void) {
    if (!g_adx_attach_lock) return nil;
    [g_adx_attach_lock lock];
    NSString *s = g_adx_attach_error;
    [g_adx_attach_lock unlock];
    return s;
}

static inline RemoteCall *adx_session(void) {
    return (__bridge RemoteCall *)g_rc_ptr;
}

int adx_init_remote_call(const char *process, bool useMigFilterBypass) {
    if (g_rc_ptr) return 0;
    if (!process) return -1;

    if (!g_lock_held) {
        [SKKernelLock() lock];
        g_lock_held = YES;
    }

    NSString *name = [NSString stringWithUTF8String:process];
    RemoteCall *rc = [[RemoteCall alloc] initWithProcess:name useMigFilterBypass:useMigFilterBypass];
    if (!rc) {
        NSString *why = [RemoteCall lastInitError] ?: @"RemoteCall 初始化失败（未给出原因）";
        adx_set_attach_error(why);
        ADXLogf(@"(adx-rc) 附着 %s 失败：%@", process, why);
        [SKKernelLock() unlock];
        g_lock_held = NO;
        return -1;
    }
    adx_set_attach_error(nil);
    g_rc_ptr = (__bridge_retained void *)rc;
    return 0;
}

uint64_t adx_remote_call(int timeout, const char *name,
                         uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3,
                         uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7) {
    RemoteCall *rc = adx_session();
    if (!rc || !name) return 0;
    void *pc = dlsym(RTLD_DEFAULT, name);
    if (!pc) {
        ADXLogf(@"(adx-rc) dlsym(%s) 失败", name);
        return 0;
    }
    uint64_t args[8] = { a0, a1, a2, a3, a4, a5, a6, a7 };
    return (uint64_t)[rc doRemoteCallStableWithTimeout:timeout
                                          functionName:(char *)name
                                       functionPointer:pc
                                                  args:args
                                              argCount:8];
}

int adx_destroy_remote_call(void) {
    if (g_rc_ptr) {
        RemoteCall *rc = (__bridge_transfer RemoteCall *)g_rc_ptr;
        g_rc_ptr = NULL;
        if (rc) [rc destroyRemoteCall];
    }
    if (g_lock_held) {
        [SKKernelLock() unlock];
        g_lock_held = NO;
    }
    return 0;
}

BOOL adx_remote_write(uint64_t dst, const void *src, uint64_t size) {
    RemoteCall *rc = adx_session();
    if (!rc || !src || !size) return NO;
    return [rc remote_write:dst from:src size:size];
}