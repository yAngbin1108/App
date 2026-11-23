//
//  ADXBlockUpdates.m
//  App 扩展层 — 阻止 App Store 更新（不需要注入任何进程）
//
//  原理和 Cyanide / AppDump 一样：在 .app 的【父目录】下放一个名为
//  com.apple.mobileinstallation.placeholder 的目录并 chmod 0000，安装服务看到它
//  就认为该应用「正在安装中」，从而跳过更新。
//
//  但这里不走「注入 installd + 远程 mkdir」那条路：那条路要求 RemoteCall，
//  而 RemoteCall 只能在 arm64e 构建里工作、且第三方实现在 arm64e 上会崩（真机已复现）。
//  我们本来就持有内核读写，所以改成：
//    1. 先按普通方式 mkdir（父目录若已经属于 mobile 就直接成功）；
//    2. 不行就把父目录的属主临时改成自己（apfs_own 走内核，不受 POSIX DAC 限制），
//       mkdir + chmod 0000，再改回原属主。
//  这样 arm64 构建里也能用，且完全不碰别的进程。
//
#import "ADXBlockUpdates.h"
#import "ADXInternal.h"
#import "darksword.h"
#import "apfs.h"
#import "SKKernelLock.h"

#import <sys/stat.h>
#include <errno.h>
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
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

#pragma mark - 属主

static BOOL adx_chown(NSString *path, uid_t uid, gid_t gid) {
    if (chown(path.fileSystemRepresentation, uid, gid) == 0) return YES;
    if (!ds_is_ready()) return NO;
    // 改不属于自己的文件只能走内核；apfs_own 要求调用方已持有内核锁。
    [SKKernelLock() lock];
    int rc = apfs_own(path.fileSystemRepresentation, uid, gid);
    [SKKernelLock() unlock];
    return rc == 0;
}

static BOOL adx_chmod(NSString *path, mode_t mode) {
    if (chmod(path.fileSystemRepresentation, mode) == 0) return YES;
    if (!ds_is_ready()) return NO;
    [SKKernelLock() lock];
    int rc = apfs_mod(path.fileSystemRepresentation, mode);
    [SKKernelLock() unlock];
    return rc == 0;
}

#pragma mark - 执行

int ADXBlockApply(NSArray<NSString *> *paths, BOOL block,
                  void (^progress)(NSInteger, NSInteger)) {
    if (!paths.count) return 0;
    if (!ds_is_ready()) {
        ADXLogf(@"(block) 内核读写未就绪");
        return 1;
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    uid_t me = geteuid();
    gid_t mygid = getegid();
    NSInteger total = (NSInteger)paths.count;
    NSInteger done = 0;
    int failed = 0;

    for (NSString *path in paths) {
        NSString *parent = path.stringByDeletingLastPathComponent;
        struct stat pst;
        BOOL havePst = (stat(parent.fileSystemRepresentation, &pst) == 0);
        uid_t ownerUID = havePst ? pst.st_uid : 0;
        gid_t ownerGID = havePst ? pst.st_gid : 0;
        BOOL chowned = NO;

        if (block) {
            if ([fm fileExistsAtPath:path]) {
                ADXLogf(@"(block) 已存在，跳过：%@", path.lastPathComponent);
            } else {
                BOOL ok = (mkdir(path.fileSystemRepresentation, 0755) == 0);
                if (!ok) {
                    // 父目录是 root 的 → 临时改成自己再建
                    chowned = adx_chown(parent, me, mygid);
                    if (chowned) ok = (mkdir(path.fileSystemRepresentation, 0755) == 0);
                    if (chowned) adx_chown(parent, ownerUID, ownerGID);
                }
                if (!ok) {
                    ADXLogf(@"(block) 建目录失败：%@（errno=%d）", path, errno);
                    failed++;
                } else {
                    if (!adx_chmod(path, 0000)) {
                        ADXLogf(@"(block) chmod 0000 失败：%@（errno=%d）", path, errno);
                        failed++;
                    } else {
                        ADXLogf(@"(block) 已阻止更新：%@", path);
                    }
                }
            }
        } else {
            if (![fm fileExistsAtPath:path]) {
                ADXLogf(@"(block) 本来就没阻止：%@", path);
            } else {
                if (chmod(path.fileSystemRepresentation, 0755) != 0) {
                    // 目录是 0000 且属主不是自己 → 先借父目录
                    chowned = adx_chown(parent, me, mygid);
                    if (chowned) adx_chmod(path, 0755);
                }
                int rc = rmdir(path.fileSystemRepresentation);
                if (chowned) adx_chown(parent, ownerUID, ownerGID);
                if (rc != 0) {
                    ADXLogf(@"(block) rmdir 失败：%@（errno=%d）", path, errno);
                    failed++;
                } else {
                    ADXLogf(@"(block) 已恢复更新：%@", path);
                }
            }
        }
        done++;
        if (progress) progress(done, total);
    }

    ADXLogf(@"(block) 完成：%ld 项，失败 %d", (long)total, failed);
    return failed ? 3 : 0;
}