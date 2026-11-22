//
//  ADXHook.m
//  App 扩展层 — 把「扩展」标签页挂到第三方 App 的标签栏里
//
//  第三方代码一个字都不改：这里用运行时替换 UITabBarController 的
//  -setViewControllers:，当调用者是 SKRootTabBarController（第三方主界面）
//  且数组里还没有我们的页面时，追加一个 ADXHomeViewController。
//  第三方自己重建标签（设置页关掉时）也一样能保住这个 tab。
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ADXInternal.h"
#import "ADXHomeViewController.h"

static NSString *const kADXTabTitle = @"扩展";

static BOOL ADXIsOurController(UIViewController *vc) {
    UIViewController *probe = vc;
    if ([probe isKindOfClass:UINavigationController.class]) {
        probe = ((UINavigationController *)probe).viewControllers.firstObject;
    }
    return [probe isKindOfClass:ADXHomeViewController.class];
}

static UINavigationController *ADXMakeTab(void) {
    ADXHomeViewController *home = [[ADXHomeViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:home];
    nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:kADXTabTitle
                                                  image:[UIImage systemImageNamed:@"square.grid.2x2.fill"]
                                          selectedImage:nil];
    return nav;
}

@interface UITabBarController (ADXInject)
- (void)adx_setViewControllers:(NSArray<UIViewController *> *)viewControllers;
@end

@implementation UITabBarController (ADXInject)

- (void)adx_setViewControllers:(NSArray<UIViewController *> *)viewControllers {
    NSArray<UIViewController *> *list = viewControllers ?: @[];
    Class sk = NSClassFromString(@"SKRootTabBarController");
    if (sk && [self isKindOfClass:sk]) {
        BOOL present = NO;
        for (UIViewController *vc in list) {
            if (ADXIsOurController(vc)) { present = YES; break; }
        }
        if (!present) {
            NSMutableArray *mutable = [list mutableCopy];
            [mutable addObject:ADXMakeTab()];
            list = mutable;
            ADXLogf(@"(adx) 已把扩展页挂到标签栏（共 %lu 个）", (unsigned long)list.count);
        }
    }
    // 方法已交换：这里调用的是系统原来的 -setViewControllers:
    [self adx_setViewControllers:list];
}

@end

static void ADXSwizzleTabSetter(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = [UITabBarController class];
        Method original = class_getInstanceMethod(cls, @selector(setViewControllers:));
        Method replacement = class_getInstanceMethod(cls, @selector(adx_setViewControllers:));
        if (original && replacement) method_exchangeImplementations(original, replacement);
    });
}

/// 兜底：万一标签栏是在 swizzle 之前就建好的（理论上不会），激活时补一次。
static void ADXInstallTabIfPossible(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (!app) return;
    UIWindow *key = nil;
    for (UIWindow *w in app.windows) {
        if (w.isKeyWindow) { key = w; break; }
    }
    if (!key) key = app.windows.firstObject;
    UIViewController *root = key.rootViewController;
    if (![root isKindOfClass:UITabBarController.class]) return;

    UITabBarController *tabs = (UITabBarController *)root;
    for (UIViewController *vc in tabs.viewControllers) {
        if (ADXIsOurController(vc)) return;
    }
    NSMutableArray *vcs = [tabs.viewControllers mutableCopy] ?: [NSMutableArray array];
    [vcs addObject:ADXMakeTab()];
    [tabs adx_setViewControllers:vcs];   // 走我们交换后的入口，内部再交给系统
}

__attribute__((constructor)) static void ADXHookInit(void) {
    ADXSwizzleTabSetter();
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                     usingBlock:^(NSNotification *note) {
            ADXInstallTabIfPossible();
        }];
        [nc addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                     usingBlock:^(NSNotification *note) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ ADXInstallTabIfPossible(); });
        }];
    });
}