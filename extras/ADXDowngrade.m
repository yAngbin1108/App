//
//  ADXDowngrade.m
//  App 扩展层 — 降级（注入 SpringBoard）
//
//  与第三方源码的砸壳页共存，不共用任何状态。逻辑照搬本项目 AppDump 的
//  kcdowngrade.m：RemoteCall 附着 SpringBoard → dlopen StoreKitUI →
//  SKUIItemOffer / SKUIItem 构造 → KVC 写 _itemOffer/_itemKindString/
//  _versionIdentifier → SKUIItemStateCenter -_performPurchases:…
//
#import "ADXDowngrade.h"
#import "ADXInternal.h"
#import "ADXRemoteCompat.h"
#import "darksword.h"
#import "pac.h"

#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>

static void klog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    ADXLogf(@"(kcd) %@", s);
}

/// buyParameters 模板（与 Cyanide 一致）
static NSString *dg_buy_params(long long trackId, long long versionId) {
    return [NSString stringWithFormat:
            @"productType=C&price=0&salableAdamId=%lld&pricingParameters=pricingParameter"
             "&appExtVrsId=%lld&clientBuyId=1&installed=0&trolled=1",
            trackId, versionId];
}

BOOL ADXDowngradeReady(void) {
    return ds_is_ready() && pacsignworks();
}

NSString *ADXDowngradeBlockedReason(void) {
    if (!ds_is_ready()) return @"内核读写未就绪：先去「砸壳」页跑完漏洞利用。";
    if (!pacsignworks())
        return @"当前是 arm64 构建，无法向 arm64e 的 SpringBoard 注入带 PAC 的指针。";
    return @"";
}

#pragma mark - 目标进程内的小工具

static uint64_t b_alloc_str(const char *str) {
    if (!str) return 0;
    uint64_t len = strlen(str) + 1;
    uint64_t buf = adx_remote_call(1000, "malloc", len, 0, 0, 0, 0, 0, 0, 0);
    if (buf) adx_remote_write(buf, str, len);
    return buf;
}

static uint64_t b_getClass(const char *name) {
    uint64_t p = b_alloc_str(name);
    if (!p) return 0;
    uint64_t c = adx_remote_call(1000, "objc_getClass", p, 0, 0, 0, 0, 0, 0, 0);
    adx_remote_call(1000, "free", p, 0, 0, 0, 0, 0, 0, 0);
    return c;
}

static uint64_t b_sel(const char *name) {
    uint64_t p = b_alloc_str(name);
    if (!p) return 0;
    uint64_t s = adx_remote_call(1000, "sel_registerName", p, 0, 0, 0, 0, 0, 0, 0);
    adx_remote_call(1000, "free", p, 0, 0, 0, 0, 0, 0, 0);
    return s;
}

static uint64_t b_nsstring(const char *utf8) {
    uint64_t cls = b_getClass("NSString");
    if (!cls) return 0;
    uint64_t buf = b_alloc_str(utf8);
    if (!buf) return 0;
    uint64_t sel = b_sel("stringWithUTF8String:");
    return adx_remote_call(1000, "objc_msgSend", cls, sel, buf, 0, 0, 0, 0, 0);
}

#pragma mark - 注入执行

/// 在 SpringBoard 内完成整个降级。必须与 adx_init_remote_call 同线程。
static int dg_run_injected(long long trackId, long long versionId, NSString *lookupJSON) {
    klog(@"[B] 附着 SpringBoard…");
    if (adx_init_remote_call("SpringBoard", false) != 0) {
        klog(@"[B] SpringBoard 附着失败：%@", adx_last_attach_error() ?: @"未知原因");
        return 20;
    }
    klog(@"[B] 会话就绪");

    uint64_t pathPtr = b_alloc_str("/System/Library/PrivateFrameworks/StoreKitUI.framework/StoreKitUI");
    if (!pathPtr) { adx_destroy_remote_call(); return 21; }
    uint64_t handle = adx_remote_call(1000, "dlopen", pathPtr, 9, 0, 0, 0, 0, 0, 0);
    adx_remote_call(1000, "free", pathPtr, 0, 0, 0, 0, 0, 0, 0);
    if (!handle) { klog(@"[B] dlopen StoreKitUI 失败"); adx_destroy_remote_call(); return 22; }
    klog(@"[B] StoreKitUI 已加载");

    uint64_t offCls = b_getClass("SKUIItemOffer");
    uint64_t itmCls = b_getClass("SKUIItem");
    uint64_t ctrCls = b_getClass("SKUIItemStateCenter");
    uint64_t ctxCls = b_getClass("SKUIClientContext");
    if (!offCls || !itmCls || !ctrCls || !ctxCls) {
        klog(@"[B] SKUI 类缺失");
        adx_destroy_remote_call();
        return 23;
    }

    NSString *params = dg_buy_params(trackId, versionId);
    uint64_t adamNS     = b_nsstring([[NSString stringWithFormat:@"%lld", trackId] UTF8String]);
    uint64_t paramsNS   = b_nsstring(params.UTF8String);
    uint64_t buyKeyNS   = b_nsstring("buyParams");
    uint64_t offerKeyNS = b_nsstring("_itemOffer");
    uint64_t kindKeyNS  = b_nsstring("_itemKindString");
    uint64_t verKeyNS   = b_nsstring("_versionIdentifier");
    uint64_t kindNS     = b_nsstring("iosSoftware");

    uint64_t dictCls = b_getClass("NSDictionary");
    uint64_t dictSel = b_sel("dictionaryWithObject:forKey:");
    uint64_t offerDict = adx_remote_call(1000, "objc_msgSend", dictCls, dictSel,
                                         paramsNS, buyKeyNS, 0, 0, 0, 0);

    // SKUIItem 的 lookup 字典：优先用 iTunes lookup 的原始条目，拿不到才退回兜底。
    uint64_t itemDict = 0;
    if (lookupJSON.length > 0) {
        uint64_t jsonStr = b_nsstring(lookupJSON.UTF8String);
        uint64_t data = jsonStr
            ? adx_remote_call(1000, "objc_msgSend", jsonStr, b_sel("dataUsingEncoding:"), 4, 0, 0, 0, 0, 0)
            : 0;
        if (data) {
            itemDict = adx_remote_call(1000, "objc_msgSend", b_getClass("NSJSONSerialization"),
                                       b_sel("JSONObjectWithData:options:error:"), data, 0, 0, 0, 0, 0);
        }
        klog(@"[B] lookup 字典：%@ (0x%llx)", itemDict ? @"iTunes 原始条目" : @"解析失败", itemDict);
    }
    if (!itemDict) {
        itemDict = adx_remote_call(1000, "objc_msgSend", dictCls, dictSel, adamNS, offerKeyNS, 0, 0, 0, 0);
        klog(@"[B] lookup 字典：兜底 {_itemOffer: trackId}");
    }
    klog(@"[B] lookup 字典键数=%llu",
         adx_remote_call(1000, "objc_msgSend", itemDict, b_sel("count"), 0, 0, 0, 0, 0, 0));

    uint64_t allocSel   = b_sel("alloc");
    uint64_t initDctSel = b_sel("initWithLookupDictionary:");
    uint64_t oAlloc = adx_remote_call(1000, "objc_msgSend", offCls, allocSel, 0, 0, 0, 0, 0, 0);
    uint64_t offer  = adx_remote_call(1000, "objc_msgSend", oAlloc, initDctSel, offerDict, 0, 0, 0, 0, 0);
    uint64_t iAlloc = adx_remote_call(1000, "objc_msgSend", itmCls, allocSel, 0, 0, 0, 0, 0, 0);
    uint64_t item   = adx_remote_call(1000, "objc_msgSend", iAlloc, initDctSel, itemDict, 0, 0, 0, 0, 0);
    klog(@"[B] offer=%llu item=%llu", offer, item);
    if (!offer || !item) { adx_destroy_remote_call(); return 24; }

    uint64_t setKVCSel = b_sel("setValue:forKey:");
    adx_remote_call(1000, "objc_msgSend", item, setKVCSel, offer, offerKeyNS, 0, 0, 0, 0);
    adx_remote_call(1000, "objc_msgSend", item, setKVCSel, kindNS, kindKeyNS, 0, 0, 0, 0);
    uint64_t numCls = b_getClass("NSNumber");
    uint64_t verNum = adx_remote_call(1000, "objc_msgSend", numCls, b_sel("numberWithLongLong:"),
                                      versionId, 0, 0, 0, 0, 0);
    adx_remote_call(1000, "objc_msgSend", item, setKVCSel, verNum, verKeyNS, 0, 0, 0, 0);
    klog(@"[B] KVC 已写 _itemOffer/_itemKindString/_versionIdentifier");

    uint64_t ctx = adx_remote_call(1000, "objc_msgSend", ctxCls, b_sel("defaultContext"), 0, 0, 0, 0, 0, 0);
    if (!ctx) {
        uint64_t a = adx_remote_call(1000, "objc_msgSend", ctxCls, allocSel, 0, 0, 0, 0, 0, 0);
        ctx = adx_remote_call(1000, "objc_msgSend", a, b_sel("init"), 0, 0, 0, 0, 0, 0);
        klog(@"[B] defaultContext 为空，改用空白实例 0x%llx", ctx);
    }
    uint64_t ctr = adx_remote_call(1000, "objc_msgSend", ctrCls, b_sel("defaultCenter"), 0, 0, 0, 0, 0, 0);
    if (!ctr) { klog(@"[B] defaultCenter 失败"); adx_destroy_remote_call(); return 25; }
    klog(@"[B] ctx=0x%llx ctr=0x%llx", ctx, ctr);

    uint64_t itemsArr = adx_remote_call(1000, "objc_msgSend", b_getClass("NSArray"),
                                        b_sel("arrayWithObject:"), item, 0, 0, 0, 0, 0);
    uint64_t purchases = adx_remote_call(1000, "objc_msgSend", ctr,
                                         b_sel("_newPurchasesWithItems:"), itemsArr, 0, 0, 0, 0, 0);
    klog(@"[B] purchases=%llu", purchases);
    if (!purchases) { adx_destroy_remote_call(); return 26; }

    uint64_t perfName = b_sel("_performPurchases:hasBundlePurchase:withClientContext:completionBlock:");
    uint64_t resp = adx_remote_call(1000, "objc_msgSend", ctr, b_sel("respondsToSelector:"),
                                    perfName, 0, 0, 0, 0, 0);
    uint64_t cnt = adx_remote_call(1000, "objc_msgSend", purchases, b_sel("count"), 0, 0, 0, 0, 0, 0);
    klog(@"[B] 提交前：responds=%llu purchases=%llu（%llu 项）ctx=0x%llx", resp, purchases, cnt, ctx);
    if (!resp) {
        klog(@"[B] SKUIItemStateCenter 没有 _performPurchases: 方法");
        adx_destroy_remote_call();
        return 26;
    }

    adx_remote_call(1000, "objc_msgSend", ctr, perfName, purchases, 0, ctx, 0, 0, 0);

    adx_destroy_remote_call();
    klog(@"[B] 已在 SpringBoard 内提交购买请求");
    return 0;
}

int ADXDowngradeRun(long long trackId, NSString *versionId, NSString *lookupJSON) {
    long long vid = [versionId longLongValue];
    if (vid <= 0) { klog(@"版本号无效：%@", versionId); return 2; }
    if (!ds_is_ready()) { klog(@"内核读写未就绪"); return 1; }
    if (!pacsignworks()) {
        klog(@"当前是 arm64 构建，无法注入 arm64e 的 SpringBoard（需要 pacia）");
        return 3;
    }

    klog(@"[注入 SpringBoard] track=%lld version=%lld", trackId, vid);

    // RemoteCall 会话是 __thread 的，整段必须在同一线程串行执行
    __block int rc = -1;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try { rc = dg_run_injected(trackId, vid, lookupJSON); }
        @catch (NSException *e) { klog(@"[B] 异常：%@", e.reason); rc = 99; }
        dispatch_semaphore_signal(sem);
    });
    if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC)) != 0) {
        klog(@"[B] 超时");
        return 98;
    }
    return rc;
}