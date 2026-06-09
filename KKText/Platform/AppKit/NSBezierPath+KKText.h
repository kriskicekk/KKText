//
//  NSBezierPath+KKText.h
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/09.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "KKTextPlatform.h"

#if KKTEXT_MAC

@interface NSBezierPath (KKText)
+ (instancetype _Nonnull)bezierPathWithRoundedRect:(CGRect)rect cornerRadius:(CGFloat)cornerRadius;
- (void)appendPath:(NSBezierPath * _Nonnull)path;
@end

#endif
