//
//  NSImage+KKText.m
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/09.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "NSImage+KKText.h"

#if KKTEXT_MAC

@implementation NSImage (KKText)

- (CGImageRef)CGImage {
    CGRect rect = CGRectMake(0, 0, self.size.width, self.size.height);
    return [self CGImageForProposedRect:&rect context:nil hints:nil];
}

+ (instancetype)imageWithCGImage:(CGImageRef)cgImage {
    return [[self alloc] initWithCGImage:cgImage size:NSZeroSize];
}

+ (instancetype)imageWithCGImage:(CGImageRef)cgImage scale:(CGFloat)scale orientation:(NSInteger)orientation {
    CGSize size = CGSizeMake(CGImageGetWidth(cgImage) / scale, CGImageGetHeight(cgImage) / scale);
    return [[self alloc] initWithCGImage:cgImage size:size];
}

@end

#endif
