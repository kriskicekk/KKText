//
//  NSImage+KKText.h
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/09.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "KKTextPlatform.h"

#if KKTEXT_MAC

@interface NSImage (KKText)
@property (nonatomic, readonly) CGImageRef _Nullable CGImage;
+ (nullable instancetype)imageWithCGImage:(CGImageRef _Nonnull)cgImage;
+ (nullable instancetype)imageWithCGImage:(CGImageRef _Nonnull)cgImage scale:(CGFloat)scale orientation:(NSInteger)orientation;
@end

#endif
