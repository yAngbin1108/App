//
//  ADXBlockViewController.m
//  App 扩展层 — 屏蔽 App Store 更新（列表 + 开关）
//
#import "ADXBlockViewController.h"
#import "ADXApps.h"
#import "ADXBlockUpdates.h"
#import "ADXInternal.h"
#import "darksword.h"

@interface ADXBlockViewController ()
@property (nonatomic, strong) NSArray<ADXApp *> *apps;
@property (nonatomic, assign) BOOL busy;
@end

@implementation ADXBlockViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"屏蔽更新";
    self.tableView.rowHeight = 60;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self
                                                      action:@selector(reload)];
    [self reload];
}

- (void)reload {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<ADXApp *> *user = [NSMutableArray array];
        for (ADXApp *a in ADXScanInstalledApps()) {
            if (!a.isSystem) [user addObject:a];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.apps = user;
            [strongSelf.tableView reloadData];
        });
    });
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.apps.count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return self.apps.count ? @"用户应用（开关 = 阻止 / 恢复更新）" : nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return @"需要先在「砸壳」页跑完漏洞利用（内核读写就绪）。"
           @"阻止更新时要在 App Store 点一次任意 App 的「获取」，把 installd 唤醒。";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"adxblock";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];

    ADXApp *a = self.apps[ip.row];
    cell.textLabel.text = a.name;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightSemibold];
    cell.detailTextLabel.text = a.bundleID;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = ADXIsUpdateBlocked(a.bundlePath);
    sw.enabled = !self.busy;
    sw.tag = ip.row;
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)switchChanged:(UISwitch *)sw {
    NSInteger row = sw.tag;
    if (row < 0 || row >= (NSInteger)self.apps.count) return;
    ADXApp *app = self.apps[row];
    NSString *path = ADXPlaceholderPathForBundlePath(app.bundlePath);
    if (!path) { sw.on = !sw.on; return; }

    BOOL block = sw.on;
    if (!ds_is_ready()) {
        sw.on = !block;
        [self alertTitle:@"内核未就绪"
                 message:@"请先在「砸壳」页运行漏洞利用，看到内核读写就绪后再回来。"];
        return;
    }

    self.busy = YES;
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int rc = ADXBlockApply(@[ path ], block, nil);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.busy = NO;
            [strongSelf.tableView reloadData];
            NSString *msg = nil;
            switch (rc) {
                case 0: msg = block ? [NSString stringWithFormat:@"已阻止「%@」的更新", app.name]
                                    : [NSString stringWithFormat:@"已恢复「%@」的更新", app.name];
                        break;
                case 1: msg = @"内核读写未就绪"; break;
                case 2: msg = @"无法附着 installd。\n\n请去 App Store 点任意 App 的「获取」把它唤醒，再回来重试。"; break;
                case 4: msg = @"这个包是 arm64 构建，RemoteCall 无法注入 arm64e 的 installd。\n\n请安装 arm64e 版本的 App 再试。"; break;
                default: msg = @"部分失败，详见日志 (block) 开头的记录。"; break;
            }
            [strongSelf alertTitle:rc == 0 ? @"完成" : @"未完成" message:msg];
        });
    });
}

- (void)alertTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                               message:message
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end