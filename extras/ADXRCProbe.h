//
//  ADXRCProbe.h
//  App 扩展层 — RemoteCall（跨进程注入）单点自检
//
//  背景：注入这条路（RemoteCall）在 arm64e 真机上一直崩，而它拖垮了整个 App。
//  这一版把注入**默认关掉**：降级 / 屏蔽更新会直接报「本版停用」，砸壳则自动回落到
//  前台启动（CY 原本的回退分支），功能仍然可用。
//  只有显式打开「注入自检」时才会真的跑 RemoteCall，并且全程由 ADXCrashDiag 的
//  注入窗口保护兜着 —— 崩了也只是把那条线程停住，不再带走 App。
//
#import <Foundation/Foundation.h>

/// RemoteCall 是否放行。默认 NO（本版语义）。
BOOL adx_rc_allowed(void);
void adx_rc_set_allowed(BOOL on);

/// 同步跑一次自检（会阻塞数秒，别在主线程调）。返回可读报告。
NSString *adx_rc_probe_run(void);