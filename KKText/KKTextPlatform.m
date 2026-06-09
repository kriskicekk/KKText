//
//  KKTextPlatform.m
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/08.
//  Originally created by ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "KKTextPlatform.h"

CGFloat KKTextPlatformScreenScale(void) {
#if KKTEXT_UIKIT
    return [UIScreen mainScreen].scale;
#else
    NSScreen *screen = NSScreen.mainScreen;
    return screen.backingScaleFactor ?: 1;
#endif
}

CGSize KKTextPlatformScreenSize(void) {
#if KKTEXT_UIKIT
    return [UIScreen mainScreen].bounds.size;
#else
    NSScreen *screen = NSScreen.mainScreen;
    CGSize size = screen.frame.size;
    if (size.width > size.height) {
        CGFloat tmp = size.width;
        size.width = size.height;
        size.height = tmp;
    }
    return size;
#endif
}

double KKTextPlatformSystemVersion(void) {
#if KKTEXT_UIKIT
    return [UIDevice currentDevice].systemVersion.doubleValue;
#else
    NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
    NSString *versionString = [NSString stringWithFormat:@"%ld.%ld", (long)version.majorVersion, (long)version.minorVersion];
    return versionString.doubleValue;
#endif
}

void KKTextPlatformPushContext(CGContextRef context) {
    if (!context) return;
#if KKTEXT_UIKIT
    UIGraphicsPushContext(context);
#else
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *graphicsContext = [NSGraphicsContext graphicsContextWithCGContext:context flipped:YES];
    NSGraphicsContext.currentContext = graphicsContext;
#endif
}

void KKTextPlatformPopContext(void) {
#if KKTEXT_UIKIT
    UIGraphicsPopContext();
#else
    [NSGraphicsContext restoreGraphicsState];
#endif
}

CGImageRef KKTextCreateImage(CGSize size, BOOL opaque, CGFloat scale, CGColorRef backgroundColor, void (^drawBlock)(CGContextRef context)) {
#if KKTEXT_UIKIT
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = opaque;
    format.scale = scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
        CGContextRef context = rendererContext.CGContext;
        if (opaque && context) {
            CGSize scaledSize = size;
            scaledSize.width *= scale;
            scaledSize.height *= scale;
            CGContextSaveGState(context); {
                if (!backgroundColor || CGColorGetAlpha(backgroundColor) < 1) {
                    CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
                    CGContextAddRect(context, CGRectMake(0, 0, scaledSize.width, scaledSize.height));
                    CGContextFillPath(context);
                }
                if (backgroundColor) {
                    CGContextSetFillColorWithColor(context, backgroundColor);
                    CGContextAddRect(context, CGRectMake(0, 0, scaledSize.width, scaledSize.height));
                    CGContextFillPath(context);
                }
            } CGContextRestoreGState(context);
        }
        drawBlock(context);
    }];
    return CGImageRetain(image.CGImage);
#else
    if (size.width < 1 || size.height < 1 || scale <= 0) return nil;
    size_t width = (size_t)ceil(size.width * scale);
    size_t height = (size_t)ceil(size.height * scale);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Host | (opaque ? kCGImageAlphaNoneSkipFirst : kCGImageAlphaPremultipliedFirst);
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace, bitmapInfo);
    CGColorSpaceRelease(colorSpace);
    if (!context) return nil;

    CGContextScaleCTM(context, scale, scale);
    if (opaque) {
        CGContextSaveGState(context); {
            if (!backgroundColor || CGColorGetAlpha(backgroundColor) < 1) {
                CGContextSetFillColorWithColor(context, NSColor.whiteColor.CGColor);
                CGContextFillRect(context, CGRectMake(0, 0, size.width, size.height));
            }
            if (backgroundColor) {
                CGContextSetFillColorWithColor(context, backgroundColor);
                CGContextFillRect(context, CGRectMake(0, 0, size.width, size.height));
            }
        } CGContextRestoreGState(context);
    }
    drawBlock(context);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
#endif
}
