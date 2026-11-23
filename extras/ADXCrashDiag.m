//
//  ADXCrashDiag.m
//  App 扩展层 — 崩溃定位辅助
//
//  第三方自己的 crash guard 只打 "BLADE CRASH: signal N"，没有 faulting PC/LR，
//  在 arm64e 上定位注入崩溃基本靠猜。这里在它之后挂一层 handler：
//  先把 signal/code/fault addr/PC/LR/SP 和 backtrace 打到 stderr（App 日志页能抓到），
//  再把控制权交回第三方原来的 handler，行为不变。
//
#import <UIKit/UIKit.h>
#import <signal.h>
#import <execinfo.h>
#import <sys/ucontext.h>
#import <unistd.h>
#import <string.h>
#import <stdio.h>
#import <stdlib.h>

static int g_sigs[4] = { SIGBUS, SIGSEGV, SIGILL, SIGABRT };
static struct sigaction g_prev[4];
static char g_altstack[SIGSTKSZ * 4];
static BOOL g_installed = NO;

static int adx_sig_index(int sig) {
    for (int i = 0; i < 4; i++) if (g_sigs[i] == sig) return i;
    return -1;
}

static void adx_crash_handler(int sig, siginfo_t *info, void *ctx) {
    (void)ctx;
    // 新版 SDK 的 mcontext 把 pc/lr/sp 做成了不透明字段，这里不直接读寄存器，
    // 靠 si_addr + backtrace（信号栈上的帧链能把被打断的调用栈带出来）。
    char buf[300];
    int n = snprintf(buf, sizeof buf,
                     "\n[adx-crash] signal %d (%s) code=%d addr=%p\n",
                     sig, strsignal(sig),
                     info ? info->si_code : 0,
                     info ? info->si_addr : NULL);
    if (n > 0) write(STDERR_FILENO, buf, (size_t)n);

    void *frames[64];
    int count = backtrace(frames, 64);
    if (count > 0) backtrace_symbols_fd(frames, count, STDERR_FILENO);

    // 交回第三方原来的 handler（它只打日志然后返回，进程会继续跑）。
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
    // 没有任何上层 handler：恢复默认动作并重发，别卡在故障指令上死循环。
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
    NSLog(@"[adx] (crash) 已挂崩溃诊断 handler");
}

__attribute__((constructor)) static void ADXCrashDiagInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) {
            // 第三方的 SKCrashGuardInstall 在 didFinishLaunching 里先执行，这里排在它后面。
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ adx_crash_install(); });
        }];
    });
}