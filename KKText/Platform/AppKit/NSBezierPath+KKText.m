//
//  NSBezierPath+KKText.m
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/09.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "NSBezierPath+KKText.h"

#if KKTEXT_MAC

@implementation NSBezierPath (KKText)

+ (instancetype)bezierPathWithRoundedRect:(CGRect)rect cornerRadius:(CGFloat)cornerRadius {
    return [self bezierPathWithRoundedRect:rect xRadius:cornerRadius yRadius:cornerRadius];
}

- (void)appendPath:(NSBezierPath *)path {
    [self appendBezierPath:path];
}

@end

#endif
