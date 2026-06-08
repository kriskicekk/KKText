//
//  UIPasteboard+KKText.m
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/08.
//  Originally created by ibireme.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "UIPasteboard+KKText.h"
#import "NSAttributedString+KKText.h"
#import <MobileCoreServices/MobileCoreServices.h>


#if __has_include("KKImage.h")
#import "KKImage.h"
#define KKTextAnimatedImageAvailable 1
#elif __has_include(<KKImage/KKImage.h>)
#import <KKImage/KKImage.h>
#define KKTextAnimatedImageAvailable 1
#elif __has_include(<KKWebImage/KKImage.h>)
#import <KKWebImage/KKImage.h>
#define KKTextAnimatedImageAvailable 1
#else
#define KKTextAnimatedImageAvailable 0
#endif


// Dummy class for category
@interface UIPasteboard_KKText : NSObject @end
@implementation UIPasteboard_KKText @end


NSString *const KKTextPasteboardTypeAttributedString = @"com.ibireme.NSAttributedString";
NSString *const KKTextUTTypeWEBP = @"com.google.webp";

@implementation UIPasteboard (KKText)


- (void)setKk_PNGData:(NSData *)PNGData {
    [self setData:PNGData forPasteboardType:(id)kUTTypePNG];
}

- (NSData *)kk_PNGData {
    return [self dataForPasteboardType:(id)kUTTypePNG];
}

- (void)setKk_JPEGData:(NSData *)JPEGData {
    [self setData:JPEGData forPasteboardType:(id)kUTTypeJPEG];
}

- (NSData *)kk_JPEGData {
    return [self dataForPasteboardType:(id)kUTTypeJPEG];
}

- (void)setKk_GIFData:(NSData *)GIFData {
    [self setData:GIFData forPasteboardType:(id)kUTTypeGIF];
}

- (NSData *)kk_GIFData {
    return [self dataForPasteboardType:(id)kUTTypeGIF];
}

- (void)setKk_WEBPData:(NSData *)WEBPData {
    [self setData:WEBPData forPasteboardType:KKTextUTTypeWEBP];
}

- (NSData *)kk_WEBPData {
    return [self dataForPasteboardType:KKTextUTTypeWEBP];
}

- (void)setKk_ImageData:(NSData *)imageData {
    [self setData:imageData forPasteboardType:(id)kUTTypeImage];
}

- (NSData *)kk_ImageData {
    return [self dataForPasteboardType:(id)kUTTypeImage];
}

- (void)setKk_AttributedString:(NSAttributedString *)attributedString {
    self.string = [attributedString kk_plainTextForRange:NSMakeRange(0, attributedString.length)];
    NSData *data = [attributedString kk_archiveToData];
    if (data) {
        NSDictionary *item = @{KKTextPasteboardTypeAttributedString : data};
        [self addItems:@[item]];
    }
    [attributedString enumerateAttribute:KKTextAttachmentAttributeName inRange:NSMakeRange(0, attributedString.length) options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired usingBlock:^(KKTextAttachment *attachment, NSRange range, BOOL *stop) {
        
        // save image
        UIImage *simpleImage = nil;
        if ([attachment.content isKindOfClass:[UIImage class]]) {
            simpleImage = attachment.content;
        } else if ([attachment.content isKindOfClass:[UIImageView class]]) {
            simpleImage = ((UIImageView *)attachment.content).image;
        }
        if (simpleImage) {
            NSDictionary *item = @{@"com.apple.uikit.image" : simpleImage};
            [self addItems:@[item]];
        }
        
#if KKTextAnimatedImageAvailable
        // save animated image
        if ([attachment.content isKindOfClass:[UIImageView class]]) {
            UIImageView *imageView = attachment.content;
            Class aniImageClass = NSClassFromString(@"KKImage");
            UIImage *image = imageView.image;
            if (aniImageClass && [image isKindOfClass:aniImageClass]) {
                NSData *data = [image valueForKey:@"animatedImageData"];
                NSNumber *type = [image valueForKey:@"animatedImageType"];
                if (data) {
                    switch (type.unsignedIntegerValue) {
                        case KKImageTypeGIF: {
                            NSDictionary *item = @{(id)kUTTypeGIF : data};
                            [self addItems:@[item]];
                        } break;
                        case KKImageTypePNG: { // APNG
                            NSDictionary *item = @{(id)kUTTypePNG : data};
                            [self addItems:@[item]];
                        } break;
                        case KKImageTypeWebP: {
                            NSDictionary *item = @{(id)KKTextUTTypeWEBP : data};
                            [self addItems:@[item]];
                        } break;
                        default: break;
                    }
                }
            }
        }
#endif
        
    }];
}

- (NSAttributedString *)kk_AttributedString {
    for (NSDictionary *items in self.items) {
        NSData *data = items[KKTextPasteboardTypeAttributedString];
        if (data) {
            return [NSAttributedString kk_unarchiveFromData:data];
        }
    }
    return nil;
}

@end
