//
//  NSValue+KKText.h
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/09.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "KKTextPlatform.h"

#if KKTEXT_MAC

@interface NSValue (KKText)
+ (NSValue * _Nonnull)valueWithCGPoint:(CGPoint)point;
+ (NSValue * _Nonnull)valueWithCGSize:(CGSize)size;
+ (NSValue * _Nonnull)valueWithCGRect:(CGRect)rect;
+ (NSValue * _Nonnull)valueWithCGAffineTransform:(CGAffineTransform)transform;
+ (NSValue * _Nonnull)valueWithUIEdgeInsets:(UIEdgeInsets)insets;
@property (nonatomic, readonly) CGPoint CGPointValue;
@property (nonatomic, readonly) CGSize CGSizeValue;
@property (nonatomic, readonly) CGRect CGRectValue;
@property (nonatomic, readonly) CGAffineTransform CGAffineTransformValue;
@property (nonatomic, readonly) UIEdgeInsets UIEdgeInsetsValue;
@end

#endif
