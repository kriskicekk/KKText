//
//  KKTextTransaction.h
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/08.
//  Originally created by ibireme.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 KKTextTransaction let you perform a selector once before current runloop sleep.
 */
@interface KKTextTransaction : NSObject

/**
 Creates and returns a transaction with a specified target and selector.
 
 @param target    A specified target, the target is retained until runloop end.
 @param selector  A selector for target.
 
 @return A new transaction, or nil if an error occurs.
 */
+ (KKTextTransaction *)transactionWithTarget:(id)target selector:(SEL)selector;

/**
 Commit the trancaction to main runloop.
 
 @discussion It will perform the selector on the target once before main runloop's
 current loop sleep. If the same transaction (same target and same selector) has 
 already commit to runloop in this loop, this method do nothing.
 */
- (void)commit;

@end

NS_ASSUME_NONNULL_END
