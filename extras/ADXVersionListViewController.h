//
//  ADXVersionListViewController.h
//  App 扩展层 — 降级：历史版本列表
//
#import <UIKit/UIKit.h>
#import "ADXApps.h"

NS_ASSUME_NONNULL_BEGIN

@interface ADXVersionListViewController : UITableViewController
- (instancetype)initWithApp:(ADXApp *)app;
@end

NS_ASSUME_NONNULL_END