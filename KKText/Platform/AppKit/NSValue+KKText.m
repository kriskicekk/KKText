//
//  NSValue+KKText.m
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/09.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "NSValue+KKText.h"

#if KKTEXT_MAC

@implementation NSValue (KKText)

+ (NSValue *)valueWithCGPoint:(CGPoint)point {
    return [NSValue valueWithBytes:&point objCType:@encode(CGPoint)];
}

+ (NSValue *)valueWithCGSize:(CGSize)size {
    return [NSValue valueWithBytes:&size objCType:@encode(CGSize)];
}

+ (NSValue *)valueWithCGRect:(CGRect)rect {
    return [NSValue valueWithBytes:&rect objCType:@encode(CGRect)];
}

+ (NSValue *)valueWithCGAffineTransform:(CGAffineTransform)transform {
    return [NSValue valueWithBytes:&transform objCType:@encode(CGAffineTransform)];
}

+ (NSValue *)valueWithUIEdgeInsets:(UIEdgeInsets)insets {
    return [NSValue valueWithBytes:&insets objCType:@encode(UIEdgeInsets)];
}

- (CGPoint)CGPointValue {
    CGPoint point = CGPointZero;
    [self getValue:&point];
    return point;
}

- (CGSize)CGSizeValue {
    CGSize size = CGSizeZero;
    [self getValue:&size];
    return size;
}

- (CGRect)CGRectValue {
    CGRect rect = CGRectZero;
    [self getValue:&rect];
    return rect;
}

- (CGAffineTransform)CGAffineTransformValue {
    CGAffineTransform transform = CGAffineTransformIdentity;
    [self getValue:&transform];
    return transform;
}

- (UIEdgeInsets)UIEdgeInsetsValue {
    UIEdgeInsets insets = UIEdgeInsetsZero;
    [self getValue:&insets];
    return insets;
}

@end

#endif
