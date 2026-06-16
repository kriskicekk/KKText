//
//  KKBenchRunner.m
//  KKBenchTextView
//
//  Created by kris on 2026/06/16.
//

#import "KKBenchRunner.h"

#import <QuartzCore/QuartzCore.h>
#import <YYText/YYText.h>
#import <KKText/KKText.h>

@implementation KKBenchConfiguration

+ (instancetype)defaultConfiguration {
    KKBenchConfiguration *configuration = [self new];
    configuration.paragraphCount = 10;
    configuration.charactersPerParagraph = 1000;
    configuration.warmupCount = 2;
    configuration.measuredRepeatCount = 5;
    configuration.textViewSize = CGSizeMake(360, 640);
    return configuration;
}

@end

@implementation KKBenchResult

- (CFTimeInterval)yyAverageTime {
    return self.operationCount == 0 ? 0 : self.yyTotalTime / self.operationCount;
}

- (CFTimeInterval)kkAverageTime {
    return self.operationCount == 0 ? 0 : self.kkTotalTime / self.operationCount;
}

- (double)kkToYYRatio {
    return self.yyAverageTime <= 0 ? 0 : self.kkAverageTime / self.yyAverageTime;
}

- (NSString *)summaryLine {
    return [NSString stringWithFormat:@"%@ | YY %.3f ms/op | KK %.3f ms/op | %.2fx",
            self.name,
            self.yyAverageTime * 1000.0,
            self.kkAverageTime * 1000.0,
            self.kkToYYRatio];
}

@end

typedef NSUInteger (^KKBenchOperationBlock)(UIView *textView, NSAttributedString *baseText);

@interface KKBenchRunner ()
@property (nonatomic, copy) NSAttributedString *benchmarkText;
@end

@implementation KKBenchRunner

- (instancetype)init {
    return [self initWithConfiguration:[KKBenchConfiguration defaultConfiguration]];
}

- (instancetype)initWithConfiguration:(KKBenchConfiguration *)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration ?: [KKBenchConfiguration defaultConfiguration];
    }
    return self;
}

- (void)runInHostView:(UIView *)hostView completion:(KKBenchCompletion)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.benchmarkText = [self makeBenchmarkText];
        NSArray<KKBenchResult *> *results = [self runBenchmarksInHostView:hostView];
        if (completion) completion(results);
    });
}

- (NSUInteger)benchmarkTextLength {
    return self.benchmarkText.length;
}

+ (NSString *)summaryTextForResults:(NSArray<KKBenchResult *> *)results {
    NSMutableString *text = [NSMutableString string];
    [text appendString:@"YYTextView vs KKTextView Benchmark\n"];
    [text appendString:@"--------------------------------\n"];
    [text appendString:@"Lower is better. Ratio = KK average / YY average.\n\n"];
    for (KKBenchResult *result in results) {
        [text appendFormat:@"%@\n", result.summaryLine];
    }
    return text.copy;
}

#pragma mark - Benchmarks

- (NSArray<KKBenchResult *> *)runBenchmarksInHostView:(UIView *)hostView {
    NSMutableArray<KKBenchResult *> *results = [NSMutableArray array];

    [results addObject:[self measureBenchmarkNamed:@"set attributedText"
                                          hostView:hostView
                                needsInitialLayout:NO
                                         operation:^NSUInteger(UIView *textView, NSAttributedString *baseText) {
        [self setAttributedText:baseText onTextView:textView];
        [self flushTextView:textView];
        return 1;
    }]];

    [results addObject:[self measureBenchmarkNamed:@"insert beginning x30"
                                          hostView:hostView
                                needsInitialLayout:YES
                                         operation:^NSUInteger(UIView *textView, NSAttributedString *baseText) {
        for (NSUInteger i = 0; i < 30; i++) {
            [self setSelectedRange:NSMakeRange(0, 0) onTextView:textView];
            [self insertText:@"x" intoTextView:textView];
        }
        [self flushTextView:textView];
        return 30;
    }]];

    [results addObject:[self measureBenchmarkNamed:@"insert middle x30"
                                          hostView:hostView
                                needsInitialLayout:YES
                                         operation:^NSUInteger(UIView *textView, NSAttributedString *baseText) {
        NSUInteger location = baseText.length / 2;
        for (NSUInteger i = 0; i < 30; i++) {
            [self setSelectedRange:NSMakeRange(location + i, 0) onTextView:textView];
            [self insertText:@"x" intoTextView:textView];
        }
        [self flushTextView:textView];
        return 30;
    }]];

    [results addObject:[self measureBenchmarkNamed:@"append x30"
                                          hostView:hostView
                                needsInitialLayout:YES
                                         operation:^NSUInteger(UIView *textView, NSAttributedString *baseText) {
        for (NSUInteger i = 0; i < 30; i++) {
            NSUInteger length = [self textLengthForTextView:textView];
            [self setSelectedRange:NSMakeRange(length, 0) onTextView:textView];
            [self insertText:@"x" intoTextView:textView];
        }
        [self flushTextView:textView];
        return 30;
    }]];

    [results addObject:[self measureBenchmarkNamed:@"delete backward x30"
                                          hostView:hostView
                                needsInitialLayout:YES
                                         operation:^NSUInteger(UIView *textView, NSAttributedString *baseText) {
        NSUInteger location = baseText.length / 2;
        for (NSUInteger i = 0; i < 30; i++) {
            [self setSelectedRange:NSMakeRange(MAX(location, 1), 0) onTextView:textView];
            [self deleteBackwardInTextView:textView];
        }
        [self flushTextView:textView];
        return 30;
    }]];

    [results addObject:[self measureBenchmarkNamed:@"selection x100"
                                          hostView:hostView
                                needsInitialLayout:YES
                                         operation:^NSUInteger(UIView *textView, NSAttributedString *baseText) {
        NSUInteger length = MAX(baseText.length, 1);
        for (NSUInteger i = 0; i < 100; i++) {
            NSUInteger location = (i * 97) % length;
            [self setSelectedRange:NSMakeRange(location, MIN((NSUInteger)8, length - location)) onTextView:textView];
        }
        [self flushTextView:textView];
        return 100;
    }]];

    [results addObject:[self measureBenchmarkNamed:@"scrollRangeToVisible x80"
                                          hostView:hostView
                                needsInitialLayout:YES
                                         operation:^NSUInteger(UIView *textView, NSAttributedString *baseText) {
        NSUInteger length = MAX(baseText.length, 1);
        for (NSUInteger i = 0; i < 80; i++) {
            NSUInteger location = (i * 131) % length;
            [self scrollRange:NSMakeRange(location, 0) toVisibleInTextView:textView];
        }
        [self flushTextView:textView];
        return 80;
    }]];

    return results.copy;
}

- (KKBenchResult *)measureBenchmarkNamed:(NSString *)name
                                  hostView:(UIView *)hostView
                        needsInitialLayout:(BOOL)needsInitialLayout
                                 operation:(KKBenchOperationBlock)operation {
    KKBenchResult *result = [KKBenchResult new];
    result.name = name;
    NSUInteger totalOperationCount = 0;

    for (NSUInteger i = 0; i < self.configuration.warmupCount; i++) {
        [self measureTextViewClass:YYTextView.class hostView:hostView needsInitialLayout:needsInitialLayout operation:operation operationCount:NULL];
        [self measureTextViewClass:KKTextView.class hostView:hostView needsInitialLayout:needsInitialLayout operation:operation operationCount:NULL];
    }

    for (NSUInteger i = 0; i < self.configuration.measuredRepeatCount; i++) {
        NSUInteger yyOperationCount = 0;
        NSUInteger kkOperationCount = 0;
        result.yyTotalTime += [self measureTextViewClass:YYTextView.class hostView:hostView needsInitialLayout:needsInitialLayout operation:operation operationCount:&yyOperationCount];
        result.kkTotalTime += [self measureTextViewClass:KKTextView.class hostView:hostView needsInitialLayout:needsInitialLayout operation:operation operationCount:&kkOperationCount];
        totalOperationCount += MAX(yyOperationCount, kkOperationCount);
    }

    result.operationCount = totalOperationCount;
    return result;
}

- (CFTimeInterval)measureTextViewClass:(Class)textViewClass
                              hostView:(UIView *)hostView
                    needsInitialLayout:(BOOL)needsInitialLayout
                             operation:(KKBenchOperationBlock)operation
                        operationCount:(NSUInteger *)operationCount {
    @autoreleasepool {
        UIView *textView = [self makeTextViewWithClass:textViewClass];
        [hostView addSubview:textView];
        if (needsInitialLayout) {
            [self setAttributedText:self.benchmarkText onTextView:textView];
            [self flushTextView:textView];
        }

        CFTimeInterval start = CACurrentMediaTime();
        NSUInteger count = operation(textView, self.benchmarkText);
        CFTimeInterval elapsed = CACurrentMediaTime() - start;

        [textView removeFromSuperview];
        if (operationCount) *operationCount = count;
        return elapsed;
    }
}

#pragma mark - Text View Access

- (UIView *)makeTextViewWithClass:(Class)textViewClass {
    UIView *view = [[textViewClass alloc] initWithFrame:(CGRect){CGPointZero, self.configuration.textViewSize}];
    view.backgroundColor = UIColor.whiteColor;

    if ([view isKindOfClass:YYTextView.class]) {
        YYTextView *textView = (YYTextView *)view;
        textView.editable = YES;
        textView.selectable = YES;
        textView.font = [UIFont systemFontOfSize:15];
        textView.textColor = UIColor.blackColor;
        textView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    } else if ([view isKindOfClass:KKTextView.class]) {
        KKTextView *textView = (KKTextView *)view;
        textView.editable = YES;
        textView.selectable = YES;
        textView.font = [UIFont systemFontOfSize:15];
        textView.textColor = UIColor.blackColor;
        textView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    }

    return view;
}

- (void)setAttributedText:(NSAttributedString *)text onTextView:(UIView *)view {
    if ([view isKindOfClass:YYTextView.class]) {
        ((YYTextView *)view).attributedText = text;
    } else if ([view isKindOfClass:KKTextView.class]) {
        ((KKTextView *)view).attributedText = text;
    }
}

- (NSUInteger)textLengthForTextView:(UIView *)view {
    if ([view isKindOfClass:YYTextView.class]) {
        return ((YYTextView *)view).text.length;
    } else if ([view isKindOfClass:KKTextView.class]) {
        return ((KKTextView *)view).text.length;
    }
    return 0;
}

- (void)setSelectedRange:(NSRange)range onTextView:(UIView *)view {
    if ([view isKindOfClass:YYTextView.class]) {
        ((YYTextView *)view).selectedRange = range;
    } else if ([view isKindOfClass:KKTextView.class]) {
        ((KKTextView *)view).selectedRange = range;
    }
}

- (void)insertText:(NSString *)text intoTextView:(UIView *)view {
    if ([view isKindOfClass:YYTextView.class]) {
        [(YYTextView *)view insertText:text];
    } else if ([view isKindOfClass:KKTextView.class]) {
        [(KKTextView *)view insertText:text];
    }
}

- (void)deleteBackwardInTextView:(UIView *)view {
    if ([view isKindOfClass:YYTextView.class]) {
        [(YYTextView *)view deleteBackward];
    } else if ([view isKindOfClass:KKTextView.class]) {
        [(KKTextView *)view deleteBackward];
    }
}

- (void)scrollRange:(NSRange)range toVisibleInTextView:(UIView *)view {
    if ([view isKindOfClass:YYTextView.class]) {
        [(YYTextView *)view scrollRangeToVisible:range];
    } else if ([view isKindOfClass:KKTextView.class]) {
        [(KKTextView *)view scrollRangeToVisible:range];
    }
}

- (void)flushTextView:(UIView *)view {
    [view setNeedsLayout];
    [view layoutIfNeeded];
    [view setNeedsDisplay];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.001, true);
}

#pragma mark - Fixture

- (NSAttributedString *)makeBenchmarkText {
    NSMutableString *string = self.configuration.targetCharacterCount > 0 ? [self makeTargetLengthString] : [NSMutableString string];
    NSString *seed = @"KKText benchmark mixes English text, 中文文本, punctuation, numbers 1234567890, and emoji 🙂. ";

    if (self.configuration.targetCharacterCount == 0) {
        for (NSUInteger paragraph = 0; paragraph < self.configuration.paragraphCount; paragraph++) {
            NSUInteger targetLength = (paragraph + 1) * self.configuration.charactersPerParagraph + paragraph;
            while (string.length < targetLength) {
                [string appendString:seed];
            }
            if (paragraph + 1 < self.configuration.paragraphCount) {
                [string appendString:@"\n"];
            }
        }
    }

    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:string];
    NSRange fullRange = NSMakeRange(0, text.length);
    [text addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:15] range:fullRange];
    [text addAttribute:NSForegroundColorAttributeName value:[UIColor colorWithWhite:0.12 alpha:1] range:fullRange];

    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.lineSpacing = 2;
    style.paragraphSpacing = 8;
    [text addAttribute:NSParagraphStyleAttributeName value:style range:fullRange];

    for (NSUInteger location = 0; location < text.length; location += 600) {
        NSUInteger length = MIN((NSUInteger)80, text.length - location);
        [text addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:18] range:NSMakeRange(location, length)];
    }

    for (NSUInteger location = 200; location < text.length; location += 900) {
        NSUInteger length = MIN((NSUInteger)60, text.length - location);
        [text addAttribute:NSForegroundColorAttributeName value:[UIColor colorWithRed:0.28 green:0.23 blue:0.68 alpha:1] range:NSMakeRange(location, length)];
    }

    return text.copy;
}

- (NSMutableString *)makeTargetLengthString {
    NSUInteger targetLength = self.configuration.targetCharacterCount;
    NSUInteger paragraphLength = MAX((NSUInteger)1, self.configuration.charactersPerParagraph);
    NSString *seed = @"KKText benchmark mixes English text, 中文文本, punctuation, numbers 1234567890, and emoji 🙂. ";
    NSMutableString *string = [NSMutableString stringWithCapacity:targetLength];
    NSUInteger remainingLength = targetLength;

    while (remainingLength > 0) {
        if (string.length > 0) {
            [string appendString:@"\n"];
            remainingLength--;
            if (remainingLength == 0) break;
        }

        NSUInteger chunkLength = MIN(paragraphLength, remainingLength);
        [string appendString:[self makeSeedStringWithLength:chunkLength seed:seed]];
        remainingLength -= chunkLength;
    }

    return string;
}

- (NSString *)makeSeedStringWithLength:(NSUInteger)targetLength seed:(NSString *)seed {
    NSMutableString *string = [NSMutableString stringWithCapacity:targetLength];
    while (string.length < targetLength) {
        [string appendString:seed];
    }

    if (string.length > targetLength) {
        NSUInteger deleteLocation = targetLength;
        if (deleteLocation < string.length) {
            NSRange composedRange = [string rangeOfComposedCharacterSequenceAtIndex:deleteLocation];
            if (composedRange.location < deleteLocation) {
                deleteLocation = composedRange.location;
            }
        }
        [string deleteCharactersInRange:NSMakeRange(deleteLocation, string.length - deleteLocation)];
    }

    return string.copy;
}

@end
