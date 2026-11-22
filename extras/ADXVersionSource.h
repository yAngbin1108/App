//
//  ADXVersionSource.h
//  App 扩展层 — App Store 元数据与历史版本查询
//
//  移植自本项目 AppDump 的 downgrademgr：iTunes lookup 逐国家查 trackId，
//  历史版本走 bilin / iosdump 两个源，合并去重后按时间倒序。
//
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 用 bundleId 查 App Store 条目（多国家逐个试）。
/// 返回字典：trackId(NSNumber) / name / bundleId / version / sellerName / lookupJSON(NSString)
/// 查不到返回 nil，error 里给一句人话。
NSDictionary * _Nullable ADXLookupApp(NSString *bundleID, NSString * _Nullable * _Nullable error);

/// 抓历史版本。返回数组，元素为字典：
/// versionId(NSString) / version / build / date / size / source
/// note 里给统计信息（哪个源返回了多少、失败原因）。
NSArray<NSDictionary *> *ADXFetchVersions(long long trackId, NSString * _Nullable * _Nullable note);

NS_ASSUME_NONNULL_END