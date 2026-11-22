//
//  ADXRunLogViewController.m
//  App 扩展层 — 通用「执行 + 实时日志」页
//
#import "ADXRunLogViewController.h"
#import "ADXInternal.h"

@interface ADXRunLogViewController ()
@property (nonatomic, copy) ADXRunBlock run;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, assign) BOOL started;
@end

@implementation ADXRunLogViewController

- (instancetype)initWithTitle:(NSString *)title run:(ADXRunBlock)run {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = title;
        _run = [run copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [self.spinner startAnimating];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;

    self.status = [[UILabel alloc] init];
    self.status.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
    self.status.textColor = UIColor.secondaryLabelColor;
    self.status.numberOfLines = 3;
    self.status.text = @"执行中…";
    self.status.translatesAutoresizingMaskIntoConstraints = NO;

    self.logView = [[UITextView alloc] init];
    self.logView.editable = NO;
    self.logView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.logView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.logView.layer.cornerRadius = 10;
    self.logView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    self.logView.text = @"";
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:self.spinner];
    [self.view addSubview:self.status];
    [self.view addSubview:self.logView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.status.centerYAnchor],
        [self.status.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [self.status.leadingAnchor constraintEqualToAnchor:self.spinner.trailingAnchor constant:10],
        [self.status.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [self.logView.topAnchor constraintEqualToAnchor:self.status.bottomAnchor constant:10],
        [self.logView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [self.logView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [self.logView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.started) return;
    self.started = YES;

    __weak typeof(self) weakSelf = self;
    void (^logBlock)(NSString *) = ^(NSString *line) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSString *cur = strongSelf.logView.text ?: @"";
            strongSelf.logView.text = cur.length ? [cur stringByAppendingFormat:@"\n%@", line] : line;
            NSString *t = strongSelf.logView.text;
            if (t.length) [strongSelf.logView scrollRangeToVisible:NSMakeRange(t.length - 1, 1)];
        });
    };
    void (^doneBlock)(NSString *) = ^(NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.spinner stopAnimating];
            strongSelf.status.text = message;
        });
    };

    ADXRunBlock run = self.run;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
            if (run) run(logBlock, doneBlock);
        } @catch (NSException *e) {
            logBlock([NSString stringWithFormat:@"异常：%@", e.reason]);
            doneBlock(@"失败（异常）");
        }
    });
}

@end