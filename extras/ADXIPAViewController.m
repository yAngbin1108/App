//
//  ADXIPAViewController.m
//  App 扩展层 — 产物列表（长按/点按分享，左滑删除）
//
#import "ADXIPAViewController.h"
#import "ADXInternal.h"

@interface ADXIPAViewController ()
@property (nonatomic, strong) NSMutableArray<NSString *> *files;
@end

@implementation ADXIPAViewController

- (NSString *)directory {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"Decrypted"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"产物";
    self.tableView.rowHeight = 60;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self action:@selector(reload)];
    [self reload];
}

- (void)reload {
    NSString *dir = [self directory];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    NSArray<NSString *> *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    NSMutableArray *ipas = [NSMutableArray array];
    for (NSString *n in items) {
        if ([n.pathExtension.lowercaseString isEqualToString:@"ipa"]) [ipas addObject:n];
    }
    [ipas sortUsingSelector:@selector(compare:)];
    self.files = ipas;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.files.count;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (self.files.count) return nil;
    return @"还没有产物。去「砸壳」页选一个应用导出。";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"adxipa";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];

    NSString *name = self.files[ip.row];
    NSString *path = [[self directory] stringByAppendingPathComponent:name];
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    cell.textLabel.text = name;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
    cell.detailTextLabel.text = ADXBytesText([attrs[NSFileSize] unsignedLongLongValue]);
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDetailButton;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [self shareAtIndexPath:ip];
}

- (void)tableView:(UITableView *)tv accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)ip {
    [self shareAtIndexPath:ip];
}

- (void)shareAtIndexPath:(NSIndexPath *)ip {
    if (ip.row >= (NSInteger)self.files.count) return;
    NSString *path = [[self directory] stringByAppendingPathComponent:self.files[ip.row]];
    UIActivityViewController *vc =
        [[UIActivityViewController alloc] initWithActivityItems:@[ [NSURL fileURLWithPath:path] ]
                                         applicationActivities:nil];
    vc.popoverPresentationController.sourceView = self.tableView;
    vc.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:ip];
    [self presentViewController:vc animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    __weak typeof(self) weakSelf = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                      title:@"删除"
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { done(NO); return; }
        NSString *path = [[strongSelf directory] stringByAppendingPathComponent:strongSelf.files[ip.row]];
        BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        [strongSelf reload];
        done(ok);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[ del ]];
}

@end