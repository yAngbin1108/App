//
//  ADXCrashDiag.m
//  App 扩展层 — 崩溃定位辅助 + 注入窗口保护
//
//  第三方自己的 crash guard 只打 "BLADE CRASH: signal N"，然后重新抛信号把进程带走。
//  这里在它之后挂一层 handler（后装的先执行，所以我们先跑）：
//
//   1. 打到 stderr：signal/code/fault addr + backtrace；
//   2. 如果是「注入窗口」里（RemoteCall 正在搞挂起线程）出的 SIGBUS/SIGSEGV，
//      不再往下交给那个「打完就 raise」的第三方 handler，而是直接把出事线程的
//      返回现场改成一段死循环 —— 那条线程停住，App 继续活着。
//      这是本版能「一个一个加功能」的前提：任何一条注入路径坏掉都只报错，不闪退。
//
#import <UIKit/UIKit.h>
#import <signal.h>
#import <execinfo.h>
#import <sys/ucontext.h>
#import <unistd.h>
#import <string.h>
#import <stdio.h>
#import <stdlib.h>
#import <stdint.h>
#import <pthread.h>

static int g_sigs[4] = { SIGBUS, SIGSEGV, SIGILL, SIGABRT };
static struct sigaction g_prev[4];
static char g_altstack[SIGSTKSZ * 4];
static BOOL g_installed = NO;

/// 注入窗口计数：RemoteCall 建挂起线程期间 > 0（可嵌套）。
static volatile int g_adx_inject_depth = 0;
/// 已经停住过几条线程（避免无限刷日志）。
static volatile int g_adx_parked = 0;

static int adx_sig_index(int sig) {
    for (int i = 0; i < 4; i++) if (g_sigs[i] == sig) return i;
    return -1;
}

/// 出事线程停在这里，永不返回。
static void adx_park_forever(void) {
    for (;;) pause();
}

static void adx_crash_install(void);

void adx_inject_guard_begin(void) {
    adx_crash_install();
    g_adx_inject_depth++;
}

void adx_inject_guard_end(void) {
    if (g_adx_inject_depth > 0) g_adx_inject_depth--;
}

static inline int adx_injecting(void) { return g_adx_inject_depth > 0; }

// ucontext_t 布局（arm64 Darwin）：
//   0: uc_onstack(4) | 4: uc_sigmask(4) | 8: uc_stack(24) | 32: uc_link(8)
//   40: uc_mcsize(8) | 48: uc_mcontext(8)
// mcontext64: __es(16) 然后 __ss（arm_thread_state64）从 +16 开始：
//   __lr = ss+240, __sp = ss+248, __pc = ss+256
// 这里只在校验通过（mcsize 合理、指针 8 对齐）时才动手，宁可不救也不乱写。
#define ADX_UC_MCSIZE_OFF   40
#define ADX_UC_MCONTEXT_OFF 48
#define ADX_MC_SS_OFF       16
#define ADX_SS_LR           240
#define ADX_SS_SP           248
#define ADX_SS_PC           256

static int adx_park_from_context(void *ctx) {
    if (!ctx) return 0;
    uint8_t *uc = (uint8_t *)ctx;
    uint64_t mcsize = 0, mc = 0;
    memcpy(&mcsize, uc + ADX_UC_MCSIZE_OFF, sizeof mcsize);
    memcpy(&mc, uc + ADX_UC_MCONTEXT_OFF, sizeof mc);
    if (!mc || (mc & 7) || mcsize < 0x40 || mcsize > 0x2000) return 0;

    uint64_t *ss = (uint64_t *)(uintptr_t)(mc + ADX_MC_SS_OFF);
    uint64_t sp = 0, pc = 0;
    memcpy(&sp, (uint8_t *)ss + ADX_SS_SP, sizeof sp);
    memcpy(&pc, (uint8_t *)ss + ADX_SS_PC, sizeof pc);
    if (!sp) return 0;

    uint64_t lr = 0;
    uint64_t park = (uint64_t)(uintptr_t)&adx_park_forever;
    if (pc == park) return 1;   // 已经在停驻点，别再写

    memcpy((uint8_t *)ss + ADX_SS_LR, &lr, sizeof lr);
    memcpy((uint8_t *)ss + ADX_SS_PC, &park, sizeof park);
    return 1;
}

static void adx_crash_handler(int sig, siginfo_t *info, void *ctx) {
    char buf[320];
    int n = snprintf(buf, sizeof buf,
                     "\n[adx-crash] signal %d (%s) code=%d addr=%p injecting=%d\n",
                     sig, strsignal(sig),
                     info ? info->si_code : 0,
                     info ? info->si_addr : NULL,
                     adx_injecting());
    if (n > 0) write(STDERR_FILENO, buf, (size_t)n);

    void *frames[64];
    int count = backtrace(frames, 64);
    if (count > 0) backtrace_symbols_fd(frames, count, STDERR_FILENO);

    // 注入窗口里的崩溃：把这条线程停在死循环里，进程继续。
    if (adx_injecting() && (sig == SIGBUS || sig == SIGSEGV) && adx_park_from_context(ctx)) {
        g_adx_parked++;
        char b2[160];
        int m = snprintf(b2, sizeof b2,
                         "[adx-guard] 已停住出事线程（第 %d 条），进程继续运行\n", g_adx_parked);
        if (m > 0) write(STDERR_FILENO, b2, (size_t)m);
        return;
    }

    // 其它情况交回第三方原来的 handler（它打完日志会重新抛，保留系统崩溃行为）。
    int idx = adx_sig_index(sig);
    if (idx >= 0) {
        struct sigaction *prev = &g_prev[idx];
        if ((prev->sa_flags & SA_SIGINFO) && prev->sa_sigaction) {
            prev->sa_sigaction(sig, info, ctx);
            return;
        }
        if (prev->sa_handler && prev->sa_handler != SIG_DFL && prev->sa_handler != SIG_IGN) {
            prev->sa_handler(sig);
            return;
        }
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

static void adx_crash_install(void) {
    if (g_installed) return;
    g_installed = YES;

    stack_t ss;
    memset(&ss, 0, sizeof ss);
    ss.ss_sp = g_altstack;
    ss.ss_size = sizeof g_altstack;
    sigaltstack(&ss, NULL);

    for (int i = 0; i < 4; i++) {
        struct sigaction prev;
        memset(&prev, 0, sizeof prev);
        if (sigaction(g_sigs[i], NULL, &prev) != 0) continue;
        g_prev[i] = prev;

        struct sigaction sa;
        memset(&sa, 0, sizeof sa);
        sa.sa_sigaction = adx_crash_handler;
        sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
        sigemptyset(&sa.sa_mask);
        sigaction(g_sigs[i], &sa, NULL);
    }
    printf("[adx] (crash) 已挂崩溃诊断 + 注入保护 handler\n");
    fflush(stdout);
}

__attribute__((constructor)) static void ADXCrashDiagInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ adx_crash_install(); });
        }];
    });
}