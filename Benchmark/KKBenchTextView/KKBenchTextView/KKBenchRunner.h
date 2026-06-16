//
//  KKBenchRunner.h
//  KKBenchTextView
//
//  Created by kris on 2026/06/16.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface KKBenchConfiguration : NSObject
@property (nonatomic) NSUInteger paragraphCount;
@property (nonatomic) NSUInteger charactersPerParagraph;
@property (nonatomic) NSUInteger targetCharacterCount;
@property (nonatomic) NSUInteger warmupCount;
@property (nonatomic) NSUInteger measuredRepeatCount;
@property (nonatomic) CGSize textViewSize;
+ (instancetype)defaultConfiguration;
@end

@interface KKBenchResult : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) NSUInteger operationCount;
@property (nonatomic) CFTimeInterval yyTotalTime;
@property (nonatomic) CFTimeInterval kkTotalTime;
@property (nonatomic, readonly) CFTimeInterval yyAverageTime;
@property (nonatomic, readonly) CFTimeInterval kkAverageTime;
@property (nonatomic, readonly) double kkToYYRatio;
- (NSString *)summaryLine;
@end

typedef void (^KKBenchCompletion)(NSArray<KKBenchResult *> *results);

@interface KKBenchRunner : NSObject
@property (nonatomic, strong) KKBenchConfiguration *configuration;
@property (nonatomic, readonly) NSUInteger benchmarkTextLength;

- (instancetype)initWithConfiguration:(KKBenchConfiguration *)configuration NS_DESIGNATED_INITIALIZER;
- (instancetype)init;
- (void)runInHostView:(UIView *)hostView completion:(KKBenchCompletion)completion;
+ (NSString *)summaryTextForResults:(NSArray<KKBenchResult *> *)results;

@end

NS_ASSUME_NONNULL_END
