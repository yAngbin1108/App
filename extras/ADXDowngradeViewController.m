//
//  ADXDowngradeViewController.m
//  App 扩展层 — 降级：选择应用
//
#import "ADXDowngradeViewController.h"
#import "ADXVersionListViewController.h"
#import "ADXApps.h"
#import "ADXDowngrade.h"
#import "ADXInternal.h"

@interface ADXDowngradeViewController ()
@property (nonatomic, strong) NSArray<ADXApp *> *apps;
@end

@implementation ADXDowngradeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"降级";
    self.tableView.rowHeight = 56;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self action:@selector(reload)];
    [self reload];
}

- (void)reload {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<ADXApp *> *user = [NSMutableArray array];
        for (ADXApp *a in ADXScanInstalledApps()) if (!a.isSystem) [user addObject:a];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.apps = user;
            [strongSelf.tableView reloadData];
        });
    });
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.apps.count; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return self.apps.count ? @"用户应用（只列出 App Store 上架过的才有历史版本）" : nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    NSString *blocked = ADXDowngradeBlockedReason();
    return blocked.length ? blocked
                          : @"降级会在 SpringBoard 内提交指定版本的购买请求；提交后回到桌面等 App Store 下载。";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"adxdown";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    ADXApp *a = self.apps[ip.row];
    cell.textLabel.text = a.name;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightSemibold];
    cell.detailTextLabel.text = a.bundleID;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    ADXApp *a = self.apps[ip.row];
    ADXVersionListViewController *vc = [[ADXVersionListViewController alloc] initWithApp:a];
    [self.navigationController pushViewController:vc animated:YES];
}

@end