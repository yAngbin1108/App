//
//  ADXHomeViewController.m
//  App 扩展层 — 入口页
//
//  这里只放「第三方源码里没有」的能力：FairPlay 用户态砸壳、屏蔽 App Store
//  更新、解除安装限制、产物管理。第三方原有的砸壳 / 文件管理 / 内存编辑 /
//  进程列表 / 设置 / 偏移一概不动，仍在它们自己的标签页里。
//
#import "ADXHomeViewController.h"
#import "ADXAppListViewController.h"
#import "ADXBlockViewController.h"
#import "ADXDowngradeViewController.h"
#import "ADXIPAViewController.h"
#import "ADXInternal.h"

@implementation ADXHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"扩展";
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case 0: return @"砸壳（FairPlay · 无需内核）";
        case 1: return @"应用管理与产物";
        case 2: return @"设置";
        default: return @"说明";
    }
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s != 3) return nil;
    return @"FairPlay 砸壳走 mremap_encrypted()，由 fairplayd 解密后回读，"
           @"不需要内核漏洞；已安装应用的 SC_Info 里自带授权，所以能直接出包。"
           @"屏蔽更新需要内核读写就绪（先在「砸壳」页初始化）。";
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 1) return 3;
    if (s == 3) return 4;
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"adxhome";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];

    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightSemibold];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.text = nil;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (ip.section == 0) {
        cell.textLabel.text = @"FairPlay 砸壳";
        cell.detailTextLabel.text = @"选一个已安装应用，导出解密后的 IPA";
        return cell;
    }

    if (ip.section == 1) {
        if (ip.row == 0) {
            cell.textLabel.text = @"屏蔽 App Store 更新";
            cell.detailTextLabel.text = @"在 .app 父目录建 placeholder，安装服务跳过更新";
        } else if (ip.row == 1) {
            cell.textLabel.text = @"降级到历史版本";
            cell.detailTextLabel.text = @"查 iTunes / 版本源，注入 SpringBoard 提交旧版本下载";
        } else {
            cell.textLabel.text = @"产物（IPA）";
            cell.detailTextLabel.text = @"Documents/Decrypted · 点按分享";
        }
        return cell;
    }

    if (ip.section == 2) {
        cell.textLabel.text = @"解除安装限制";
        cell.detailTextLabel.text = @"出包时 MinimumOSVersion → 10.0，去掉设备能力限制";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [NSUserDefaults.standardUserDefaults boolForKey:@"adx.relax"];
        [sw addTarget:self action:@selector(relaxChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    switch (ip.row) {
        case 0: cell.textLabel.text = @"产物目录：Documents/Decrypted/（「文件」App 里也能看到）"; break;
        case 1: cell.textLabel.text = @"失败提示 ENOMEM = 这台设备的 fairplayd 拒绝，不代表账号问题。"; break;
        case 2: cell.textLabel.text = @"假加密壳（cryptid≠0 但 cryptsize=0）会按明文出包，不需要解密。"; break;
        default: cell.textLabel.text = @"本页功能为新增模块，第三方原有代码未做任何修改。"; break;
    }
    return cell;
}

- (void)relaxChanged:(UISwitch *)sw {
    [NSUserDefaults.standardUserDefaults setBool:sw.on forKey:@"adx.relax"];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) {
        [self.navigationController pushViewController:[ADXAppListViewController new] animated:YES];
    } else if (ip.section == 1) {
        UIViewController *vc = nil;
        if (ip.row == 0) vc = [ADXBlockViewController new];
        else if (ip.row == 1) vc = [ADXDowngradeViewController new];
        else vc = [ADXIPAViewController new];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

@end