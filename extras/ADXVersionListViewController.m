//
//  ADXVersionListViewController.m
//  App 扩展层 — 降级：历史版本列表（iTunes lookup → 版本源 → 提交购买）
//
#import "ADXVersionListViewController.h"
#import "ADXRunLogViewController.h"
#import "ADXDowngrade.h"
#import "ADXVersionSource.h"
#import "ADXInternal.h"

@interface ADXVersionListViewController ()
@property (nonatomic, strong) ADXApp *app;
@property (nonatomic, strong) NSArray<NSDictionary *> *versions;
@property (nonatomic, copy) NSString *note;
@property (nonatomic, strong, nullable) NSDictionary *lookup;
@property (nonatomic, copy) NSString *errorText;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL loading;
@end

@implementation ADXVersionListViewController

- (instancetype)initWithApp:(ADXApp *)app {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _app = app;
        self.title = app.name;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 60;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
    [self reload];
}

- (void)reload {
    if (self.loading) return;
    self.loading = YES;
    self.errorText = @"";
    [self.spinner startAnimating];
    [self.tableView reloadData];

    NSString *bundleID = self.app.bundleID;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *lookupErr = nil;
        NSDictionary *app = ADXLookupApp(bundleID, &lookupErr);
        NSArray *versions = @[];
        NSString *note = @"";
        NSString *err = lookupErr ?: @"";
        if (app) {
            versions = ADXFetchVersions([app[@"trackId"] longLongValue], &note);
            if (!versions.count) err = note.length ? note : @"两个版本源都没有返回数据";
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.loading = NO;
            [strongSelf.spinner stopAnimating];
            strongSelf.lookup = app;
            strongSelf.versions = versions;
            strongSelf.note = note;
            strongSelf.errorText = err;
            [strongSelf.tableView reloadData];
        });
    });
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"App Store 条目";
    return self.versions.count ? @"历史版本（点一个开始降级）" : nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) {
        NSString *blocked = ADXDowngradeBlockedReason();
        if (blocked.length) return blocked;
        return self.errorText.length ? self.errorText : nil;
    }
    return self.note.length ? self.note : nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? (self.lookup ? 1 : 1) : self.versions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"adxver";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (ip.section == 0) {
        cell.textLabel.text = self.app.name;
        if (self.lookup) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"trackId %@ · 当前版本 %@",
                                         self.lookup[@"trackId"], self.lookup[@"version"]];
            cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        } else {
            cell.detailTextLabel.text = self.loading ? @"正在向 App Store 查询…"
                                                     : (self.errorText.length ? self.errorText : @"查不到");
            cell.detailTextLabel.textColor = self.loading ? UIColor.secondaryLabelColor : UIColor.systemRedColor;
        }
        return cell;
    }

    NSDictionary *v = self.versions[ip.row];
    NSString *ver = [v[@"version"] length] ? v[@"version"] : @"未知版本";
    NSString *build = v[@"build"];
    cell.textLabel.text = build.length ? [NSString stringWithFormat:@"%@ (%@)", ver, build] : ver;
    NSMutableArray *bits = [NSMutableArray array];
    if ([v[@"date"] length]) [bits addObject:v[@"date"]];
    if ([v[@"source"] length]) [bits addObject:v[@"source"]];
    [bits addObject:[NSString stringWithFormat:@"id %@", v[@"versionId"]]];
    cell.detailTextLabel.text = [bits componentsJoinedByString:@" · "];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != 1 || ip.row >= (NSInteger)self.versions.count) return;

    NSDictionary *v = self.versions[ip.row];
    NSString *ver = [v[@"version"] length] ? v[@"version"] : [NSString stringWithFormat:@"id %@", v[@"versionId"]];
    NSString *blocked = ADXDowngradeBlockedReason();
    if (blocked.length) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"还不能降级"
                                                                   message:blocked
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }

    NSString *msg = [NSString stringWithFormat:
                     @"将请求 App Store 下载「%@ %@」。\n\n前提：App Store 已登录、该 Apple ID 拥有这个 App。\n"
                      "提交成功后回到桌面，下载由 App Store 完成。",
                     self.app.name, ver];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"确认降级"
                                                                  message:msg
                                                           preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"开始" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) { [weakSelf runDowngrade:v]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)runDowngrade:(NSDictionary *)version {
    long long trackId = [self.lookup[@"trackId"] longLongValue];
    NSString *versionId = version[@"versionId"];
    NSString *lookupJSON = self.lookup[@"lookupJSON"];
    NSString *title = [NSString stringWithFormat:@"降级 %@ %@", self.app.name,
                       [version[@"version"] length] ? version[@"version"] : versionId];

    ADXRunLogViewController *vc =
        [[ADXRunLogViewController alloc] initWithTitle:title run:^(void (^log)(NSString *), void (^done)(NSString *)) {
        log([NSString stringWithFormat:@"trackId=%lld versionId=%@", trackId, versionId]);
        int rc = ADXDowngradeRun(trackId, versionId, lookupJSON);
        NSString *msg = nil;
        switch (rc) {
            case 0: msg = @"已提交，请回桌面查看 App Store 下载"; break;
            case 1: msg = @"内核读写未就绪"; break;
            case 2: msg = @"版本号无效"; break;
            case 3: msg = @"当前是 arm64 构建，需要 arm64e 版本"; break;
            case 20: msg = @"无法附着 SpringBoard"; break;
            case 21: msg = @"目标进程内分配内存失败"; break;
            case 22: msg = @"dlopen StoreKitUI 失败"; break;
            case 23: msg = @"SpringBoard 里没有 SKUI 相关类"; break;
            case 24: msg = @"构造 SKUIItem/SKUIItemOffer 失败"; break;
            case 25: msg = @"取不到 SKUIItemStateCenter"; break;
            case 26: msg = @"构造 purchases / 方法不存在"; break;
            case 98: msg = @"超时（120 秒）"; break;
            case 99: msg = @"异常"; break;
            default: msg = [NSString stringWithFormat:@"失败（rc=%d）", rc]; break;
        }
        log([NSString stringWithFormat:@"结果：%@", msg]);
        done(msg);
    }];
    [self.navigationController pushViewController:vc animated:YES];
}

@end