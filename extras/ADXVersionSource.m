//
//  ADXVersionSource.m
//  App 扩展层 — App Store 元数据与历史版本查询
//
#import "ADXVersionSource.h"
#import "ADXInternal.h"

#pragma mark - 同步 HTTP

static NSData *adx_http_get(NSString *urlString, NSTimeInterval timeout) {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return nil;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = timeout;
    req.HTTPShouldHandleCookies = NO;
    [req setValue:@"App/1.0 (iPhone; iOS)" forHTTPHeaderField:@"User-Agent"];

    __block NSData *result = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession] dataTaskWithRequest:req
                                        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (data.length && !err) result = data;
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW,
                                               (int64_t)((timeout + 2.0) * NSEC_PER_SEC)));
    return result;
}

static id adx_http_json(NSString *urlString, NSTimeInterval timeout) {
    NSData *data = adx_http_get(urlString, timeout);
    if (!data.length) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return obj;
}

#pragma mark - 字段提取

static NSString *adx_field(NSDictionary *item, NSArray<NSString *> *keys) {
    for (NSString *k in keys) {
        id v = item[k];
        if ([v isKindOfClass:NSString.class]) {
            NSString *t = [(NSString *)v stringByTrimmingCharactersInSet:
                           NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (t.length) return t;
        } else if ([v isKindOfClass:NSNumber.class]) {
            return [(NSNumber *)v stringValue];
        }
    }
    return @"";
}

/// 版本号净化：等于 versionId、或纯数字且长度 >= 7（那是外部版本 ID）都当没有版本号。
static NSString *adx_sanitize_version(NSString *raw, NSString *versionId) {
    NSString *t = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!t.length) return @"";
    if (versionId.length && [t isEqualToString:versionId]) return @"";
    BOOL allDigits = YES;
    for (NSUInteger i = 0; i < t.length; i++) {
        unichar c = [t characterAtIndex:i];
        if (c < '0' || c > '9') { allDigits = NO; break; }
    }
    if (allDigits && t.length >= 7) return @"";
    return t;
}

static NSDate *adx_parse_date(NSString *raw) {
    NSString *t = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!t.length) return nil;
    double n = t.doubleValue;
    if (n > 1000000000.0) return [NSDate dateWithTimeIntervalSince1970:n];

    static NSArray<NSString *> *formats;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formats = @[ @"yyyy-MM-dd HH:mm:ss", @"yyyy-MM-dd'T'HH:mm:ssZ", @"yyyy-MM-dd",
                     @"yyyy/MM/dd", @"yyyy-MM-dd'T'HH:mm:ss.SSSZ" ];
    });
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    df.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    for (NSString *fmt in formats) {
        df.dateFormat = fmt;
        NSDate *d = [df dateFromString:t];
        if (d) return d;
    }
    return nil;
}

#pragma mark - trackId 查询

NSDictionary *ADXLookupApp(NSString *bundleID, NSString **error) {
    if (!bundleID.length) {
        if (error) *error = @"bundleId 为空";
        return nil;
    }
    // 中国区上架的 App 必须靠前（只在中区上架的应用换区才查得到）
    NSArray<NSString *> *countries = @[ @"CN", @"US", @"HK", @"TW", @"JP", @"SG",
                                        @"GB", @"KR", @"CA", @"AU", @"DE", @"FR" ];
    NSString *encoded = [bundleID stringByAddingPercentEncodingWithAllowedCharacters:
                         NSCharacterSet.URLQueryAllowedCharacterSet];
    for (NSString *cc in countries) {
        NSString *url = [NSString stringWithFormat:
                         @"https://itunes.apple.com/lookup?bundleId=%@&limit=1&media=software&country=%@",
                         encoded, cc];
        NSDictionary *json = adx_http_json(url, 6.0);
        NSArray *results = [json isKindOfClass:NSDictionary.class] ? json[@"results"] : nil;
        if (![results isKindOfClass:NSArray.class] || !results.count) continue;
        NSDictionary *item = results.firstObject;
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSNumber *track = [item[@"trackId"] isKindOfClass:NSNumber.class] ? item[@"trackId"] : nil;
        NSString *bid = [item[@"bundleId"] isKindOfClass:NSString.class] ? item[@"bundleId"] : nil;
        if (!track || !bid.length) continue;

        NSData *itemData = [NSJSONSerialization dataWithJSONObject:item options:0 error:NULL];
        NSString *itemJSON = itemData ? [[NSString alloc] initWithData:itemData
                                                              encoding:NSUTF8StringEncoding] : @"";
        ADXLogf(@"(downgrade) lookup 命中：%@ / %@ (trackId=%lld, 区=%@)", bid,
                item[@"trackName"] ?: @"?", track.longLongValue, cc);
        return @{ @"trackId": track,
                  @"name": [item[@"trackName"] isKindOfClass:NSString.class] ? item[@"trackName"] : bid,
                  @"bundleId": bid,
                  @"version": [item[@"version"] isKindOfClass:NSString.class] ? item[@"version"] : @"",
                  @"sellerName": [item[@"sellerName"] isKindOfClass:NSString.class] ? item[@"sellerName"] : @"",
                  @"lookupJSON": itemJSON ?: @"" };
    }
    if (error) *error = [NSString stringWithFormat:
                         @"App Store 查不到 %@（已试 %lu 个区）—— 侧载 / 已下架的应用没有历史版本",
                         bundleID, (unsigned long)countries.count];
    return nil;
}

#pragma mark - 历史版本

static NSArray<NSDictionary *> *adx_parse_source(NSString *name, id json, NSString * *noteOut) {
    NSMutableArray *out = [NSMutableArray array];
    NSArray *items = nil;
    if ([json isKindOfClass:NSArray.class]) {
        items = json;
    } else if ([json isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = json;
        for (NSString *key in @[ @"data", @"versions", @"result" ]) {
            id v = dict[key];
            if ([v isKindOfClass:NSArray.class]) { items = v; break; }
            if ([v isKindOfClass:NSDictionary.class] && [v[@"data"] isKindOfClass:NSArray.class]) {
                items = v[@"data"];
                break;
            }
        }
    }
    if (!items) {
        if (noteOut) *noteOut = [*noteOut stringByAppendingFormat:@"%@: 无数组; ", name];
        return out;
    }

    for (NSDictionary *item in items) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSString *vid = adx_field(item, @[ @"external_identifier", @"externalVersionId",
                                           @"external_version_id", @"version_id", @"versionId", @"id" ]);
        if (!vid.length) continue;
        BOOL allDigits = YES;
        for (NSUInteger i = 0; i < vid.length; i++) {
            unichar c = [vid characterAtIndex:i];
            if (c < '0' || c > '9') { allDigits = NO; break; }
        }
        if (!allDigits) continue;

        NSString *rawVersion = adx_field(item, @[ @"bundle_version", @"bundleShortVersionString",
                                                  @"short_version", @"version" ]);
        NSString *rawBuild = adx_field(item, @[ @"build", @"bundleVersion", @"bundle_version_string" ]);
        NSString *version = adx_sanitize_version(rawVersion, vid);
        NSString *build = adx_sanitize_version(rawBuild, vid);
        if (build.length && [build isEqualToString:version]) build = @"";

        NSString *date = adx_field(item, @[ @"created_at", @"createdAt", @"date", @"releaseDate",
                                            @"released", @"uploaded_at", @"timestamp" ]);
        NSString *size = adx_field(item, @[ @"size", @"fileSize" ]);

        [out addObject:@{ @"versionId": vid,
                          @"version": version,
                          @"build": build,
                          @"date": date,
                          @"size": size,
                          @"source": name }];
    }
    if (noteOut) *noteOut = [*noteOut stringByAppendingFormat:@"%@: %lu 个; ", name, (unsigned long)out.count];
    return out;
}

NSArray<NSDictionary *> *ADXFetchVersions(long long trackId, NSString **note) {
    NSString *notes = @"";
    NSMutableArray<NSDictionary *> *all = [NSMutableArray array];

    NSArray<NSDictionary *> *sources = @[
        @{ @"name": @"bilin", @"template": @"https://apis.bilin.eu.org/history/{id}" },
        @{ @"name": @"iosdump", @"template": @"https://iosdump.apdoilaan.work/history/{id}" },
    ];
    for (NSDictionary *src in sources) {
        NSString *url = [src[@"template"] stringByReplacingOccurrencesOfString:@"{id}"
                                                                   withString:[NSString stringWithFormat:@"%lld", trackId]];
        id json = adx_http_json(url, 15.0);
        NSString *one = @"";
        if (!json) {
            notes = [notes stringByAppendingFormat:@"%@: 请求失败; ", src[@"name"]];
            continue;
        }
        [all addObjectsFromArray:adx_parse_source(src[@"name"], json, &one)];
        notes = [notes stringByAppendingString:one];
    }

    // 按 versionId 去重（保留版本号更完整的那条），再按时间倒序
    NSMutableDictionary<NSString *, NSDictionary *> *byId = [NSMutableDictionary dictionary];
    for (NSDictionary *v in all) {
        NSString *vid = v[@"versionId"];
        NSDictionary *old = byId[vid];
        if (!old) { byId[vid] = v; continue; }
        if (![old[@"version"] length] && [v[@"version"] length]) byId[vid] = v;
    }
    NSArray<NSDictionary *> *merged = byId.allValues;
    merged = [merged sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSDate *da = adx_parse_date(a[@"date"]);
        NSDate *db = adx_parse_date(b[@"date"]);
        if (da && db && ![da isEqualToDate:db]) return [db compare:da];
        long long ia = [a[@"versionId"] longLongValue];
        long long ib = [b[@"versionId"] longLongValue];
        if (ia == ib) return NSOrderedSame;
        return ia > ib ? NSOrderedAscending : NSOrderedDescending;
    }];

    if (note) *note = [notes stringByAppendingFormat:@"合计 %lu 个（去重后 %lu 个，按时间倒序）",
                       (unsigned long)all.count, (unsigned long)merged.count];
    ADXLogf(@"(downgrade) 历史版本：%@", note ? *note : @"");
    return merged;
}