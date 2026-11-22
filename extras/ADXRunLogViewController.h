//
//  ADXRunLogViewController.h
//  App 扩展层 — 通用「执行 + 实时日志」页
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^ADXRunBlock)(void (^log)(NSString *line), void (^done)(NSString *message));

@interface ADXRunLogViewController : UIViewController
/// run 在后台线程执行；log/done 可以任意线程调用，内部会切回主线程。
- (instancetype)initWithTitle:(NSString *)title run:(ADXRunBlock)run;
@end

NS_ASSUME_NONNULL_END