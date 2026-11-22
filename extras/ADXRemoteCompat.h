//
//  ADXRemoteCompat.h
//  App 扩展层 — Cyanide 风格的全局远程调用接口
//
//  移植自 AppDump 的 kcdowngrade_compat（本次合并新增，只做接口适配）：
//  把「全局函数 + 线程内会话」这层接到第三方源码里已有的 TaskRop/RemoteCall
//  实例 API 上，供屏蔽更新等模块使用。
//
#ifndef ADXRemoteCompat_h
#define ADXRemoteCompat_h

#import <Foundation/Foundation.h>
#include <stdint.h>
#include <stdbool.h>

/// 附着目标进程，成功返回 0。会话是线程内的。
int adx_init_remote_call(const char *process, bool useMigFilterBypass);

/// 最近一次附着失败的原因（人类可读）。
NSString *adx_last_attach_error(void);

/// 在目标进程里调用一个已导出符号。
uint64_t adx_remote_call(int timeout, const char *name,
                         uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3,
                         uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7);

/// 结束会话并释放内核锁，可重复调用。
int adx_destroy_remote_call(void);

/// 往目标进程写内存。
BOOL adx_remote_write(uint64_t dst, const void *src, uint64_t size);

#endif /* ADXRemoteCompat_h */