//
//  KKBenchViewController.m
//  KKBenchTextView
//
//  Created by kris on 2026/06/16.
//

#import "KKBenchViewController.h"
#import "KKBenchRunner.h"

@interface KKBenchViewController ()
@property (nonatomic, strong) UIButton *runButton;
@property (nonatomic, strong) UITextView *resultTextView;
@property (nonatomic, strong) UIView *benchmarkHostView;
@property (nonatomic, strong) KKBenchRunner *runner;
@property (nonatomic) BOOL autorun;
@property (nonatomic) BOOL didAutorun;
@end

@implementation KKBenchViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"TextView Benchmark";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.autorun = [NSProcessInfo.processInfo.arguments containsObject:@"--autorun"];

    self.runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.runButton setTitle:@"Run Benchmark" forState:UIControlStateNormal];
    self.runButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.runButton addTarget:self action:@selector(runBenchmark) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.runButton];

    self.resultTextView = [UITextView new];
    self.resultTextView.editable = NO;
    self.resultTextView.alwaysBounceVertical = YES;
    self.resultTextView.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.resultTextView.textColor = UIColor.labelColor;
    self.resultTextView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.resultTextView.text = @"Run a Release build on a real device for useful numbers.";
    [self.view addSubview:self.resultTextView];

    self.benchmarkHostView = [[UIView alloc] initWithFrame:CGRectMake(-10000, -10000, 420, 720)];
    [self.view addSubview:self.benchmarkHostView];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.autorun && !self.didAutorun) {
        self.didAutorun = YES;
        [self runBenchmark];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGFloat width = self.view.bounds.size.width;
    self.runButton.frame = CGRectMake(20, insets.top + 12, width - 40, 44);
    self.resultTextView.frame = CGRectMake(16,
                                           CGRectGetMaxY(self.runButton.frame) + 12,
                                           width - 32,
                                           self.view.bounds.size.height - CGRectGetMaxY(self.runButton.frame) - insets.bottom - 28);
}

- (void)runBenchmark {
    self.runButton.enabled = NO;
    self.resultTextView.text = @"Running...";

    NSArray<KKBenchConfiguration *> *configurations = [self benchmarkConfigurationsFromLaunchArguments];
    [self runKKBenchConfigurations:configurations index:0 summaryText:[NSMutableString string]];
}

- (void)runKKBenchConfigurations:(NSArray<KKBenchConfiguration *> *)configurations
                              index:(NSUInteger)index
                        summaryText:(NSMutableString *)summaryText {
    if (index >= configurations.count) {
        self.resultTextView.text = summaryText.copy;
        self.runButton.enabled = YES;
        NSLog(@"KKBENCH_RESULT_BEGIN\n%@KKBENCH_RESULT_END", summaryText);
        if (self.autorun) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                exit(0);
            });
        }
        return;
    }

    KKBenchRunner *runner = [[KKBenchRunner alloc] initWithConfiguration:configurations[index]];
    self.runner = runner;
    self.resultTextView.text = [NSString stringWithFormat:@"Running %@/%@...\n\n%@",
                                @(index + 1),
                                @(configurations.count),
                                summaryText];

    __weak typeof(self) weakSelf = self;
    [runner runInHostView:self.benchmarkHostView completion:^(NSArray<KKBenchResult *> *results) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSString *summary = [KKBenchRunner summaryTextForResults:results];
        [summaryText appendFormat:@"Text length: %@\n%@", @(runner.benchmarkTextLength), summary];
        if (index + 1 < configurations.count) {
            [summaryText appendString:@"\n"];
        }
        [self runKKBenchConfigurations:configurations index:index + 1 summaryText:summaryText];
    }];
}

- (NSArray<KKBenchConfiguration *> *)benchmarkConfigurationsFromLaunchArguments {
    NSMutableArray<NSNumber *> *targetLengths = [NSMutableArray array];
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        NSString *value = nil;
        if ([argument hasPrefix:@"--text-length="]) {
            value = [argument substringFromIndex:@"--text-length=".length];
        } else if ([argument isEqualToString:@"--text-length"] && idx + 1 < arguments.count) {
            value = arguments[idx + 1];
        }
        if (value.length == 0) continue;
        for (NSString *component in [value componentsSeparatedByString:@","]) {
            NSInteger length = component.integerValue;
            if (length > 0) {
                [targetLengths addObject:@((NSUInteger)length)];
            }
        }
    }

    if (targetLengths.count == 0) {
        [targetLengths addObjectsFromArray:@[@100, @1000, @10000]];
    }

    NSMutableArray<KKBenchConfiguration *> *configurations = [NSMutableArray arrayWithCapacity:targetLengths.count];
    for (NSNumber *targetLength in targetLengths) {
        KKBenchConfiguration *configuration = [KKBenchConfiguration defaultConfiguration];
        configuration.targetCharacterCount = targetLength.unsignedIntegerValue;
        [configurations addObject:configuration];
    }
    return configurations.copy;
}

@end
