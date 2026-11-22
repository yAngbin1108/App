//
//  ADXDowngrade.h
//  App 扩展层 — App Store 历史版本降级
//
//  移植自本项目 AppDump 的 kcdowngrade（注入 SpringBoard 驱动 StoreKitUI）。
//  需要 arm64e 构建（RemoteCall 要往 arm64e 的 SpringBoard 写带 PAC 的指针）。
//
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 前置条件：内核读写就绪 + 当前构建能生成 PAC 签名（即 arm64e）。
BOOL ADXDowngradeReady(void);
/// 最近一次阻塞原因（未就绪时给界面显示）。
NSString *ADXDowngradeBlockedReason(void);

/// 在 SpringBoard 内提交指定历史版本的购买/下载请求。
/// @param trackId   App Store track id
/// @param versionId 目标版本的外部标识（externalVersionId）
/// @param lookupJSON iTunes lookup 原始条目的 JSON 文本（SKUIItem 的 lookup 字典），可为 nil
/// @return 0 成功；1 内核未就绪；2 版本号无效；3 需要 arm64e；
///         20~26 注入各步骤失败；98 超时；99 异常
int ADXDowngradeRun(long long trackId, NSString *versionId, NSString * _Nullable lookupJSON);

NS_ASSUME_NONNULL_END