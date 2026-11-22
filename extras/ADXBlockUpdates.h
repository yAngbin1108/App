//
//  ADXBlockUpdates.h
//  App 扩展层 — 阻止 App Store 更新（Cyanide 的 placeholder 做法）
//
//  机制（移植自 AppDump 的 kcblock）：注入 installd，在 .app 的**父目录**下
//  建一个名为 com.apple.mobileinstallation.placeholder 的目录并 chmod 0000，
//  安装服务看到它就认为该应用「正在安装」，从而跳过更新。解除时反向操作。
//
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// placeholder 目录名
FOUNDATION_EXPORT NSString *const ADXPlaceholderName;

/// .app 父目录下的 placeholder 完整路径
NSString * _Nullable ADXPlaceholderPathForBundlePath(NSString * _Nullable bundlePath);

/// 当前是否已被阻止（只看文件系统，不需要内核）
BOOL ADXIsUpdateBlocked(NSString *bundlePath);

/// 执行阻止 / 恢复。
/// @return 0 全部成功；1 内核原语未就绪；2 附着 installd 失败；3 部分失败
int ADXBlockApply(NSArray<NSString *> *paths,
                  BOOL block,
                  void (^ _Nullable progress)(NSInteger done, NSInteger total));

NS_ASSUME_NONNULL_END