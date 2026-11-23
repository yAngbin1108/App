//
//  ADXRCProbe.m
//  App 扩展层 — RemoteCall 自检实现
//
#import "ADXRCProbe.h"
#import "ADXInternal.h"
#import "RemoteCall.h"
#import <unistd.h>

// 强制走 iOS16+（exc_actions）路径 —— 旧路径在 17.5.1 上已被证伪
extern void adx_rc_force_ios16(int on);

// 注入窗口保护（ADXCrashDiag.m 提供）
extern void adx_inject_guard_begin(void);
extern void adx_inject_guard_end(void);

static volatile int g_adx_rc_allowed = 0;

BOOL adx_rc_allowed(void) { return g_adx_rc_allowed != 0; }

void adx_rc_set_allowed(BOOL on) { g_adx_rc_allowed = on ? 1 : 0; }

NSString *adx_rc_probe_run(void) {
    NSMutableString *rep = [NSMutableString string];
    [rep appendString:@"== RemoteCall 注入自检 ==\n"];

    adx_rc_set_allowed(YES);
    adx_rc_force_ios16(1);          // 走 exc_actions 路径，不再扫栈换 TRO
    adx_inject_guard_begin();
    ADXLogf(@"(probe) 开始注入自检（目标 SpringBoard）");

    @try {
        RemoteCall *rc = [[RemoteCall alloc] initWithProcess:@"SpringBoard" useMigFilterBypass:NO];
        if (!rc) {
            NSString *why = [RemoteCall lastInitError] ?: @"未给出原因";
            [rep appendFormat:@"init 失败：%@\n", why];
            ADXLogf(@"(probe) init 失败：%@", why);
        } else {
            [rep appendString:@"init 成功 —— TRO 交换完成，注入通道可用\n"];
            ADXLogf(@"(probe) init 成功");

            uint64_t args[8] = { 0 };
            NSUInteger got = [rc doRemoteCallStableWithTimeout:200
                                                  functionName:(char *)"getpid"
                                               functionPointer:(void *)getpid
                                                          args:args
                                                      argCount:8];
            [rep appendFormat:@"SpringBoard getpid() -> %lu\n", (unsigned long)got];
            ADXLogf(@"(probe) getpid() -> %lu", (unsigned long)got);
            [rc destroyRemoteCall];
        }
    } @catch (NSException *e) {
        [rep appendFormat:@"异常：%@ — %@\n", e.name, e.reason];
        ADXLogf(@"(probe) 异常：%@ — %@", e.name, e.reason);
    }

    adx_inject_guard_end();
    adx_rc_force_ios16(0);
    adx_rc_set_allowed(NO);

    [rep appendString:@"== 自检结束（已重新停用注入） ==\n"];
    return rep;
}