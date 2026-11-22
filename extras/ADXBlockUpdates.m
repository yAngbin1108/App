//
//  ADXBlockUpdates.m
//  App 扩展层 — 阻止 App Store 更新
//
//  移植自 AppDump 的 kexploit/kcblock.m（Cyanide20 的实现），调用换成
//  本仓库已有的 RemoteCall 适配层。
//
#import "ADXBlockUpdates.h"
#import "ADXInternal.h"
#import "ADXRemoteCompat.h"
#import "darksword.h"
#import <unistd.h>

NSString *const ADXPlaceholderName = @"com.apple.mobileinstallation.placeholder";

NSString *ADXPlaceholderPathForBundlePath(NSString *bundlePath) {
    if (!bundlePath.length) return nil;
    NSString *parent = bundlePath.stringByDeletingLastPathComponent;
    if (!parent.length) return nil;
    return [parent stringByAppendingPathComponent:ADXPlaceholderName];
}

BOOL ADXIsUpdateBlocked(NSString *bundlePath) {
    NSString *path = ADXPlaceholderPathForBundlePath(bundlePath);
    if (!path) return NO;
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) return YES;
    return NO;
}

/// 目标进程里分配字符串
static uint64_t adx_alloc_str(const char *str) {
    if (!str) return 0;
    uint64_t len = strlen(str) + 1;
    uint64_t buf = adx_remote_call(1000, "malloc", len, 0, 0, 0, 0, 0, 0, 0);
    if (buf) adx_remote_write(buf, str, len);
    return buf;
}

int ADXBlockApply(NSArray<NSString *> *paths, BOOL block,
                  void (^progress)(NSInteger, NSInteger)) {
    if (!paths.count) return 0;
    if (!ds_is_ready()) {
        ADXLogf(@"(block) 内核原语未就绪");
        return 1;
    }

    ADXLogf(@"(block) 等待 installd 唤醒（卡住请去 App Store 点任意 App 的「获取」）…");
    int retry = 0;
    while (adx_init_remote_call("installd", false) != 0) {
        sleep(2);
        retry++;
        if (retry % 5 == 0) {
            ADXLogf(@"(block) [WAIT] 仍在等待 installd…请去 App Store 点一次「获取」");
        }
        if (retry > 60) {
            ADXLogf(@"(block) [FAIL] 等待 installd 超时");
            return 2;
        }
    }
    ADXLogf(@"(block) installd 已附着");

    NSInteger total = (NSInteger)paths.count;
    NSInteger done = 0;
    int failed = 0;

    for (NSString *p in paths) {
        uint64_t pPtr = adx_alloc_str(p.UTF8String);
        if (!pPtr) {
            failed++; done++;
            if (progress) progress(done, total);
            continue;
        }
        if (block) {
            uint64_t r = adx_remote_call(1000, "mkdir", pPtr, 0755, 0, 0, 0, 0, 0, 0);
            adx_remote_call(1000, "chmod", pPtr, 0000, 0, 0, 0, 0, 0, 0);
            if (r != 0) ADXLogf(@"(block) mkdir 返回 %llu（可能已存在）：%@",
                                (unsigned long long)r, p.lastPathComponent);
        } else {
            adx_remote_call(1000, "chmod", pPtr, 0755, 0, 0, 0, 0, 0, 0);
            uint64_t r = adx_remote_call(1000, "rmdir", pPtr, 0, 0, 0, 0, 0, 0, 0);
            if (r != 0) {
                ADXLogf(@"(block) rmdir 返回 %llu：%@", (unsigned long long)r, p.lastPathComponent);
                failed++;
            }
        }
        adx_remote_call(1000, "free", pPtr, 0, 0, 0, 0, 0, 0, 0);
        done++;
        if (progress) progress(done, total);
    }

    adx_destroy_remote_call();
    ADXLogf(@"(block) 完成：%ld 项，失败 %d", (long)total, failed);
    return failed ? 3 : 0;
}