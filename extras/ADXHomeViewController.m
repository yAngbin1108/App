//
//  ADXHomeViewController.m
//  App 扩展层 — 入口页
//
//  这里只放「第三方源码里没有」的能力：FairPlay 用户态砸壳、解除安装限制。
//  第三方原有的砸壳/文件管理/内存编辑/进程列表一概不动，仍在它们自己的标签页。
//
#import "ADXHomeViewController.h"
#import "ADXAppListViewController.h"
#import "ADXInternal.h"

@implementation ADXHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"扩展";
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case 0: return @"砸壳（FairPlay · 无需内核）";
        case 1: return @"设置";
        default: return @"说明";
    }
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s != 2) return nil;
    return @"FairPlay 砸壳走 mremap_encrypted()，由 fairplayd 解密后回读，"
           @"不需要内核漏洞；已安装应用的 SC_Info 里自带授权，所以能直接出包。";
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 2 ? 3 : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"adxhome";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];

    if (ip.section == 0) {
        cell.textLabel.text = @"FairPlay 砸壳";
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = @"选一个已安装应用，导出解密后的 IPA";
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }

    if (ip.section == 1) {
        cell.textLabel.text = @"解除安装限制";
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = @"出包时把 MinimumOSVersion 降到 10.0、去掉设备能力限制";
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [NSUserDefaults.standardUserDefaults boolForKey:@"adx.relax"];
        [sw addTarget:self action:@selector(relaxChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    cell.textLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (ip.row == 0) cell.textLabel.text = @"产物目录：Documents/Decrypted/";
    else if (ip.row == 1) cell.textLabel.text = @"失败提示 ENOMEM = 这台设备的 fairplayd 拒绝，不代表账号问题。";
    else cell.textLabel.text = @"本页功能为新增模块，第三方原有代码未做任何修改。";
    return cell;
}

- (void)relaxChanged:(UISwitch *)sw {
    [NSUserDefaults.standardUserDefaults setBool:sw.on forKey:@"adx.relax"];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) {
        [self.navigationController pushViewController:[ADXAppListViewController new] animated:YES];
    }
}

@end