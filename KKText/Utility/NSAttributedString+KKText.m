//
//  NSAttributedString+KKText.m
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/08.
//  Originally created by ibireme.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "NSAttributedString+KKText.h"
#import "NSParagraphStyle+KKText.h"
#import "KKTextArchiver.h"
#import "KKTextRunDelegate.h"
#import "KKTextUtilities.h"
#import <CoreFoundation/CoreFoundation.h>


// Dummy class for category
@interface NSAttributedString_KKText : NSObject @end
@implementation NSAttributedString_KKText @end


static double _KKDeviceSystemVersion() {
    static double version;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        version = KKTextPlatformSystemVersion();
    });
    return version;
}

#ifndef kSystemVersion
#define kSystemVersion _KKDeviceSystemVersion()
#endif

#ifndef kiOS6Later
#define kiOS6Later (kSystemVersion >= 6)
#endif

#ifndef kiOS7Later
#define kiOS7Later (kSystemVersion >= 7)
#endif

#ifndef kiOS8Later
#define kiOS8Later (kSystemVersion >= 8)
#endif

#ifndef kiOS9Later
#define kiOS9Later (kSystemVersion >= 9)
#endif



@implementation NSAttributedString (KKText)

- (NSData *)kk_archiveToData {
    NSData *data = nil;
    @try {
        data = [KKTextArchiver archivedDataWithRootObject:self];
    }
    @catch (NSException *exception) {
        NSLog(@"%@",exception);
    }
    return data;
}

+ (instancetype)kk_unarchiveFromData:(NSData *)data {
    NSAttributedString *one = nil;
    @try {
        one = [KKTextUnarchiver unarchiveObjectWithData:data];
    }
    @catch (NSException *exception) {
        NSLog(@"%@",exception);
    }
    return one;
}

- (NSDictionary *)kk_attributesAtIndex:(NSUInteger)index {
    if (index > self.length || self.length == 0) return nil;
    if (self.length > 0 && index == self.length) index--;
    return [self attributesAtIndex:index effectiveRange:NULL];
}

- (id)kk_attribute:(NSString *)attributeName atIndex:(NSUInteger)index {
    if (!attributeName) return nil;
    if (index > self.length || self.length == 0) return nil;
    if (self.length > 0 && index == self.length) index--;
    return [self attribute:attributeName atIndex:index effectiveRange:NULL];
}

- (NSDictionary *)kk_attributes {
    return [self kk_attributesAtIndex:0];
}

- (UIFont *)kk_font {
    return [self kk_fontAtIndex:0];
}

- (UIFont *)kk_fontAtIndex:(NSUInteger)index {
    /*
     In iOS7 and later, UIFont is toll-free bridged to CTFontRef,
     although Apple does not mention it in documentation.
     
     In iOS6, UIFont is a wrapper for CTFontRef, so CoreText can alse use UIfont,
     but UILabel/UITextView cannot use CTFontRef.
     
     We use UIFont for both CoreText and UIKit.
     */
    UIFont *font = [self kk_attribute:NSFontAttributeName atIndex:index];
    if (kSystemVersion <= 6) {
        if (font) {
            if (CFGetTypeID((__bridge CFTypeRef)(font)) == CTFontGetTypeID()) {
                CTFontRef CTFont = (__bridge CTFontRef)(font);
                CFStringRef name = CTFontCopyPostScriptName(CTFont);
                CGFloat size = CTFontGetSize(CTFont);
                if (!name) {
                    font = nil;
                } else {
                    font = [UIFont fontWithName:(__bridge NSString *)(name) size:size];
                    CFRelease(name);
                }
            }
        }
    }
    return font;
}

- (NSNumber *)kk_kern {
    return [self kk_kernAtIndex:0];
}

- (NSNumber *)kk_kernAtIndex:(NSUInteger)index {
    return [self kk_attribute:NSKernAttributeName atIndex:index];
}

- (UIColor *)kk_color {
    return [self kk_colorAtIndex:0];
}

- (UIColor *)kk_colorAtIndex:(NSUInteger)index {
    UIColor *color = [self kk_attribute:NSForegroundColorAttributeName atIndex:index];
    if (!color) {
        CGColorRef ref = (__bridge CGColorRef)([self kk_attribute:(NSString *)kCTForegroundColorAttributeName atIndex:index]);
        color = [UIColor colorWithCGColor:ref];
    }
    if (color && ![color isKindOfClass:[UIColor class]]) {
        if (CFGetTypeID((__bridge CFTypeRef)(color)) == CGColorGetTypeID()) {
            color = [UIColor colorWithCGColor:(__bridge CGColorRef)(color)];
        } else {
            color = nil;
        }
    }
    return color;
}

- (UIColor *)kk_backgroundColor {
    return [self kk_backgroundColorAtIndex:0];
}

- (UIColor *)kk_backgroundColorAtIndex:(NSUInteger)index {
    return [self kk_attribute:NSBackgroundColorAttributeName atIndex:index];
}

- (NSNumber *)kk_strokeWidth {
    return [self kk_strokeWidthAtIndex:0];
}

- (NSNumber *)kk_strokeWidthAtIndex:(NSUInteger)index {
    return [self kk_attribute:NSStrokeWidthAttributeName atIndex:index];
}

- (UIColor *)kk_strokeColor {
    return [self kk_strokeColorAtIndex:0];
}

- (UIColor *)kk_strokeColorAtIndex:(NSUInteger)index {
    UIColor *color = [self kk_attribute:NSStrokeColorAttributeName atIndex:index];
    if (!color) {
        CGColorRef ref = (__bridge CGColorRef)([self kk_attribute:(NSString *)kCTStrokeColorAttributeName atIndex:index]);
        color = [UIColor colorWithCGColor:ref];
    }
    return color;
}

- (NSShadow *)kk_shadow {
    return [self kk_shadowAtIndex:0];
}

- (NSShadow *)kk_shadowAtIndex:(NSUInteger)index {
    return [self kk_attribute:NSShadowAttributeName atIndex:index];
}

- (NSUnderlineStyle)kk_strikethroughStyle {
    return [self kk_strikethroughStyleAtIndex:0];
}

- (NSUnderlineStyle)kk_strikethroughStyleAtIndex:(NSUInteger)index {
    NSNumber *style = [self kk_attribute:NSStrikethroughStyleAttributeName atIndex:index];
    return style.integerValue;
}

- (UIColor *)kk_strikethroughColor {
    return [self kk_strikethroughColorAtIndex:0];
}

- (UIColor *)kk_strikethroughColorAtIndex:(NSUInteger)index {
    if (kSystemVersion >= 7) {
        return [self kk_attribute:NSStrikethroughColorAttributeName atIndex:index];
    }
    return nil;
}

- (NSUnderlineStyle)kk_underlineStyle {
    return [self kk_underlineStyleAtIndex:0];
}

- (NSUnderlineStyle)kk_underlineStyleAtIndex:(NSUInteger)index {
    NSNumber *style = [self kk_attribute:NSUnderlineStyleAttributeName atIndex:index];
    return style.integerValue;
}

- (UIColor *)kk_underlineColor {
    return [self kk_underlineColorAtIndex:0];
}

- (UIColor *)kk_underlineColorAtIndex:(NSUInteger)index {
    UIColor *color = nil;
    if (kSystemVersion >= 7) {
        color = [self kk_attribute:NSUnderlineColorAttributeName atIndex:index];
    }
    if (!color) {
        CGColorRef ref = (__bridge CGColorRef)([self kk_attribute:(NSString *)kCTUnderlineColorAttributeName atIndex:index]);
        color = [UIColor colorWithCGColor:ref];
    }
    return color;
}

- (NSNumber *)kk_ligature {
    return [self kk_ligatureAtIndex:0];
}

- (NSNumber *)kk_ligatureAtIndex:(NSUInteger)index {
    return [self kk_attribute:NSLigatureAttributeName atIndex:index];
}

- (NSString *)kk_textEffect {
    return [self kk_textEffectAtIndex:0];
}

- (NSString *)kk_textEffectAtIndex:(NSUInteger)index {
    if (kSystemVersion >= 7) {
        return [self kk_attribute:NSTextEffectAttributeName atIndex:index];
    }
    return nil;
}

- (NSNumber *)kk_obliqueness {
    return [self kk_obliquenessAtIndex:0];
}

- (NSNumber *)kk_obliquenessAtIndex:(NSUInteger)index {
    if (kSystemVersion >= 7) {
        return [self kk_attribute:NSObliquenessAttributeName atIndex:index];
    }
    return nil;
}

- (NSNumber *)kk_expansion {
    return [self kk_expansionAtIndex:0];
}

- (NSNumber *)kk_expansionAtIndex:(NSUInteger)index {
    if (kSystemVersion >= 7) {
        return [self kk_attribute:NSExpansionAttributeName atIndex:index];
    }
    return nil;
}

- (NSNumber *)kk_baselineOffset {
    return [self kk_baselineOffsetAtIndex:0];
}

- (NSNumber *)kk_baselineOffsetAtIndex:(NSUInteger)index {
    if (kSystemVersion >= 7) {
        return [self kk_attribute:NSBaselineOffsetAttributeName atIndex:index];
    }
    return nil;
}

- (BOOL)kk_verticalGlyphForm {
    return [self kk_verticalGlyphFormAtIndex:0];
}

- (BOOL)kk_verticalGlyphFormAtIndex:(NSUInteger)index {
    NSNumber *num = [self kk_attribute:NSVerticalGlyphFormAttributeName atIndex:index];
    return num.boolValue;
}

- (NSString *)kk_language {
    return [self kk_languageAtIndex:0];
}

- (NSString *)kk_languageAtIndex:(NSUInteger)index {
    if (kSystemVersion >= 7) {
        return [self kk_attribute:(id)kCTLanguageAttributeName atIndex:index];
    }
    return nil;
}

- (NSArray *)kk_writingDirection {
    return [self kk_writingDirectionAtIndex:0];
}

- (NSArray *)kk_writingDirectionAtIndex:(NSUInteger)index {
    return [self kk_attribute:(id)kCTWritingDirectionAttributeName atIndex:index];
}

- (NSParagraphStyle *)kk_paragraphStyle {
    return [self kk_paragraphStyleAtIndex:0];
}

- (NSParagraphStyle *)kk_paragraphStyleAtIndex:(NSUInteger)index {
    /*
     NSParagraphStyle is NOT toll-free bridged to CTParagraphStyleRef.
     
     CoreText can use both NSParagraphStyle and CTParagraphStyleRef,
     but UILabel/UITextView can only use NSParagraphStyle.
     
     We use NSParagraphStyle in both CoreText and UIKit.
     */
    NSParagraphStyle *style = [self kk_attribute:NSParagraphStyleAttributeName atIndex:index];
    if (style) {
        if (CFGetTypeID((__bridge CFTypeRef)(style)) == CTParagraphStyleGetTypeID()) { \
            style = [NSParagraphStyle kk_styleWithCTStyle:(__bridge CTParagraphStyleRef)(style)];
        }
    }
    return style;
}

#define ParagraphAttribute(_attr_) \
NSParagraphStyle *style = self.kk_paragraphStyle; \
if (!style) style = [NSParagraphStyle defaultParagraphStyle]; \
return style. _attr_;

#define ParagraphAttributeAtIndex(_attr_) \
NSParagraphStyle *style = [self kk_paragraphStyleAtIndex:index]; \
if (!style) style = [NSParagraphStyle defaultParagraphStyle]; \
return style. _attr_;

- (NSTextAlignment)kk_alignment {
    ParagraphAttribute(alignment);
}

- (NSLineBreakMode)kk_lineBreakMode {
    ParagraphAttribute(lineBreakMode);
}

- (CGFloat)kk_lineSpacing {
    ParagraphAttribute(lineSpacing);
}

- (CGFloat)kk_paragraphSpacing {
    ParagraphAttribute(paragraphSpacing);
}

- (CGFloat)kk_paragraphSpacingBefore {
    ParagraphAttribute(paragraphSpacingBefore);
}

- (CGFloat)kk_firstLineHeadIndent {
    ParagraphAttribute(firstLineHeadIndent);
}

- (CGFloat)kk_headIndent {
    ParagraphAttribute(headIndent);
}

- (CGFloat)kk_tailIndent {
    ParagraphAttribute(tailIndent);
}

- (CGFloat)kk_minimumLineHeight {
    ParagraphAttribute(minimumLineHeight);
}

- (CGFloat)kk_maximumLineHeight {
    ParagraphAttribute(maximumLineHeight);
}

- (CGFloat)kk_lineHeightMultiple {
    ParagraphAttribute(lineHeightMultiple);
}

- (NSWritingDirection)kk_baseWritingDirection {
    ParagraphAttribute(baseWritingDirection);
}

- (float)kk_hyphenationFactor {
    ParagraphAttribute(hyphenationFactor);
}

- (CGFloat)kk_defaultTabInterval {
    if (!kiOS7Later) return 0;
    ParagraphAttribute(defaultTabInterval);
}

- (NSArray *)kk_tabStops {
    if (!kiOS7Later) return nil;
    ParagraphAttribute(tabStops);
}

- (NSTextAlignment)kk_alignmentAtIndex:(NSUInteger)index {
    ParagraphAttributeAtIndex(alignment);
}

- (NSLineBreakMode)kk_lineBreakModeAtIndex:(NSUInteger)index {
    ParagraphAttributeAtIndex(lineBreakMode);
}

- (CGFloat)kk_lineSpacingAtIndex:(NSUInteger)index {
    ParagraphAttributeAtIndex(lineSpacing);
}

- (CGFloat)kk_paragraphSpacingAtIndex:(NSUInteger)index {
    ParagraphAttributeAtIndex(paragraphSpacing);
}

- (CGFloat)kk_paragraphSpacingBeforeAtIndex:(NSUInteger)index {
    ParagraphAttributeAtIndex(paragraphSpacingBefore);
}

- (CGFloat)kk_firstLineHeadIndentAtIndex:(NSUInteger)index {
    ParagraphAttributeAtIndex(firstLineHeadIndent);
}

- (CGFloat)kk_headIndentAtIndex:(NSUInteger)index {
    ParagraphAttributeAtIndex(headIndent);
}

- (CGFloat)kk_tailIndentAtIndex:(NSUInteger)index {
    ParagraphAttributeAtIndex(tailIndent);
}

- (CGFloat)kk_minimumLineHeightAtIndex:(NSUInteger)index {
    ParagraphAttributeAtIndex(minimumLineHeight);
}

- (CGFloat)kk_maximumLineHeightAtIndex:(NSUInteger)index {
    ParagraphAttributeAtIndex(maximumLineHeight);
}

- (CGFloat)kk_lineHeightMultipleAtIndex:(NSUInteger)index {
    ParagraphAttributeAtIndex(lineHeightMultiple);
}

- (NSWritingDirection)kk_baseWritingDirectionAtIndex:(NSUInteger)index {
    ParagraphAttributeAtIndex(baseWritingDirection);
}

- (float)kk_hyphenationFactorAtIndex:(NSUInteger)index {
    ParagraphAttributeAtIndex(hyphenationFactor);
}

- (CGFloat)kk_defaultTabIntervalAtIndex:(NSUInteger)index {
    if (!kiOS7Later) return 0;
    ParagraphAttributeAtIndex(defaultTabInterval);
}

- (NSArray *)kk_tabStopsAtIndex:(NSUInteger)index {
    if (!kiOS7Later) return nil;
    ParagraphAttributeAtIndex(tabStops);
}

#undef ParagraphAttribute
#undef ParagraphAttributeAtIndex

- (KKTextShadow *)kk_textShadow {
    return [self kk_textShadowAtIndex:0];
}

- (KKTextShadow *)kk_textShadowAtIndex:(NSUInteger)index {
    return [self kk_attribute:KKTextShadowAttributeName atIndex:index];
}

- (KKTextShadow *)kk_textInnerShadow {
    return [self kk_textInnerShadowAtIndex:0];
}

- (KKTextShadow *)kk_textInnerShadowAtIndex:(NSUInteger)index {
    return [self kk_attribute:KKTextInnerShadowAttributeName atIndex:index];
}

- (KKTextDecoration *)kk_textUnderline {
    return [self kk_textUnderlineAtIndex:0];
}

- (KKTextDecoration *)kk_textUnderlineAtIndex:(NSUInteger)index {
    return [self kk_attribute:KKTextUnderlineAttributeName atIndex:index];
}

- (KKTextDecoration *)kk_textStrikethrough {
    return [self kk_textStrikethroughAtIndex:0];
}

- (KKTextDecoration *)kk_textStrikethroughAtIndex:(NSUInteger)index {
    return [self kk_attribute:KKTextStrikethroughAttributeName atIndex:index];
}

- (KKTextBorder *)kk_textBorder {
    return [self kk_textBorderAtIndex:0];
}

- (KKTextBorder *)kk_textBorderAtIndex:(NSUInteger)index {
    return [self kk_attribute:KKTextBorderAttributeName atIndex:index];
}

- (KKTextBorder *)kk_textBackgroundBorder {
    return [self kk_textBackgroundBorderAtIndex:0];
}

- (KKTextBorder *)kk_textBackgroundBorderAtIndex:(NSUInteger)index {
    return [self kk_attribute:KKTextBackedStringAttributeName atIndex:index];
}

- (CGAffineTransform)kk_textGlyphTransform {
    return [self kk_textGlyphTransformAtIndex:0];
}

- (CGAffineTransform)kk_textGlyphTransformAtIndex:(NSUInteger)index {
    NSValue *value = [self kk_attribute:KKTextGlyphTransformAttributeName atIndex:index];
    if (!value) return CGAffineTransformIdentity;
    return [value CGAffineTransformValue];
}

- (NSString *)kk_plainTextForRange:(NSRange)range {
    if (range.location == NSNotFound ||range.length == NSNotFound) return nil;
    NSMutableString *result = [NSMutableString string];
    if (range.length == 0) return result;
    NSString *string = self.string;
    [self enumerateAttribute:KKTextBackedStringAttributeName inRange:range options:kNilOptions usingBlock:^(id value, NSRange range, BOOL *stop) {
        KKTextBackedString *backed = value;
        if (backed && backed.string) {
            [result appendString:backed.string];
        } else {
            [result appendString:[string substringWithRange:range]];
        }
    }];
    return result;
}

+ (NSMutableAttributedString *)kk_attachmentStringWithContent:(id)content
                                                  contentMode:(UIViewContentMode)contentMode
                                                        width:(CGFloat)width
                                                       ascent:(CGFloat)ascent
                                                      descent:(CGFloat)descent {
    NSMutableAttributedString *atr = [[NSMutableAttributedString alloc] initWithString:KKTextAttachmentToken];
    
    KKTextAttachment *attach = [KKTextAttachment new];
    attach.content = content;
    attach.contentMode = contentMode;
    [atr kk_setTextAttachment:attach range:NSMakeRange(0, atr.length)];
    
    KKTextRunDelegate *delegate = [KKTextRunDelegate new];
    delegate.width = width;
    delegate.ascent = ascent;
    delegate.descent = descent;
    CTRunDelegateRef delegateRef = delegate.CTRunDelegate;
    [atr kk_setRunDelegate:delegateRef range:NSMakeRange(0, atr.length)];
    if (delegate) CFRelease(delegateRef);
    
    return atr;
}

+ (NSMutableAttributedString *)kk_attachmentStringWithContent:(id)content
                                                  contentMode:(UIViewContentMode)contentMode
                                               attachmentSize:(CGSize)attachmentSize
                                                  alignToFont:(UIFont *)font
                                                    alignment:(KKTextVerticalAlignment)alignment {
    NSMutableAttributedString *atr = [[NSMutableAttributedString alloc] initWithString:KKTextAttachmentToken];
    
    KKTextAttachment *attach = [KKTextAttachment new];
    attach.content = content;
    attach.contentMode = contentMode;
    [atr kk_setTextAttachment:attach range:NSMakeRange(0, atr.length)];
    
    KKTextRunDelegate *delegate = [KKTextRunDelegate new];
    delegate.width = attachmentSize.width;
    switch (alignment) {
        case KKTextVerticalAlignmentTop: {
            delegate.ascent = font.ascender;
            delegate.descent = attachmentSize.height - font.ascender;
            if (delegate.descent < 0) {
                delegate.descent = 0;
                delegate.ascent = attachmentSize.height;
            }
        } break;
        case KKTextVerticalAlignmentCenter: {
            CGFloat fontHeight = font.ascender - font.descender;
            CGFloat yOffset = font.ascender - fontHeight * 0.5;
            delegate.ascent = attachmentSize.height * 0.5 + yOffset;
            delegate.descent = attachmentSize.height - delegate.ascent;
            if (delegate.descent < 0) {
                delegate.descent = 0;
                delegate.ascent = attachmentSize.height;
            }
        } break;
        case KKTextVerticalAlignmentBottom: {
            delegate.ascent = attachmentSize.height + font.descender;
            delegate.descent = -font.descender;
            if (delegate.ascent < 0) {
                delegate.ascent = 0;
                delegate.descent = attachmentSize.height;
            }
        } break;
        default: {
            delegate.ascent = attachmentSize.height;
            delegate.descent = 0;
        } break;
    }
    
    CTRunDelegateRef delegateRef = delegate.CTRunDelegate;
    [atr kk_setRunDelegate:delegateRef range:NSMakeRange(0, atr.length)];
    if (delegate) CFRelease(delegateRef);
    
    return atr;
}

+ (NSMutableAttributedString *)kk_attachmentStringWithEmojiImage:(UIImage *)image
                                                        fontSize:(CGFloat)fontSize {
    if (!image || fontSize <= 0) return nil;
    
    BOOL hasAnim = NO;
#if KKTEXT_UIKIT
    if (image.images.count > 1) {
        hasAnim = YES;
    } else
#endif
    if (NSProtocolFromString(@"KKAnimatedImage") &&
        [image conformsToProtocol:NSProtocolFromString(@"KKAnimatedImage")]) {
        NSNumber *frameCount = [image valueForKey:@"animatedImageFrameCount"];
        if (frameCount.intValue > 1) hasAnim = YES;
    }
    
    CGFloat ascent = KKTextEmojiGetAscentWithFontSize(fontSize);
    CGFloat descent = KKTextEmojiGetDescentWithFontSize(fontSize);
    CGRect bounding = KKTextEmojiGetGlyphBoundingRectWithFontSize(fontSize);
    
    KKTextRunDelegate *delegate = [KKTextRunDelegate new];
    delegate.ascent = ascent;
    delegate.descent = descent;
    delegate.width = bounding.size.width + 2 * bounding.origin.x;
    
    KKTextAttachment *attachment = [KKTextAttachment new];
    attachment.contentMode = UIViewContentModeScaleAspectFit;
    attachment.contentInsets = UIEdgeInsetsMake(ascent - (bounding.size.height + bounding.origin.y), bounding.origin.x, descent + bounding.origin.y, bounding.origin.x);
    if (hasAnim) {
        Class imageClass = NSClassFromString(@"KKAnimatedImageView");
        if (!imageClass) imageClass = [UIImageView class];
        UIImageView *view = (id)[imageClass new];
        view.frame = bounding;
        view.image = image;
        view.contentMode = UIViewContentModeScaleAspectFit;
        attachment.content = view;
    } else {
        attachment.content = image;
    }
    
    NSMutableAttributedString *atr = [[NSMutableAttributedString alloc] initWithString:KKTextAttachmentToken];
    [atr kk_setTextAttachment:attachment range:NSMakeRange(0, atr.length)];
    CTRunDelegateRef ctDelegate = delegate.CTRunDelegate;
    [atr kk_setRunDelegate:ctDelegate range:NSMakeRange(0, atr.length)];
    if (ctDelegate) CFRelease(ctDelegate);
    
    return atr;
}

- (NSRange)kk_rangeOfAll {
    return NSMakeRange(0, self.length);
}

- (BOOL)kk_isSharedAttributesInAllRange {
    __block BOOL shared = YES;
    __block NSDictionary *firstAttrs = nil;
    [self enumerateAttributesInRange:self.kk_rangeOfAll options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
        if (range.location == 0) {
            firstAttrs = attrs;
        } else {
            if (firstAttrs.count != attrs.count) {
                shared = NO;
                *stop = YES;
            } else if (firstAttrs) {
                if (![firstAttrs isEqualToDictionary:attrs]) {
                    shared = NO;
                    *stop = YES;
                }
            }
        }
    }];
    return shared;
}

- (BOOL)kk_canDrawWithUIKit {
    static NSMutableSet *failSet;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        failSet = [NSMutableSet new];
        [failSet addObject:(id)kCTGlyphInfoAttributeName];
        [failSet addObject:(id)kCTCharacterShapeAttributeName];
        if (kiOS7Later) {
            [failSet addObject:(id)kCTLanguageAttributeName];
        }
        [failSet addObject:(id)kCTRunDelegateAttributeName];
        [failSet addObject:(id)kCTBaselineClassAttributeName];
        [failSet addObject:(id)kCTBaselineInfoAttributeName];
        [failSet addObject:(id)kCTBaselineReferenceInfoAttributeName];
        if (kiOS8Later) {
            [failSet addObject:(id)kCTRubyAnnotationAttributeName];
        }
        [failSet addObject:KKTextShadowAttributeName];
        [failSet addObject:KKTextInnerShadowAttributeName];
        [failSet addObject:KKTextUnderlineAttributeName];
        [failSet addObject:KKTextStrikethroughAttributeName];
        [failSet addObject:KKTextBorderAttributeName];
        [failSet addObject:KKTextBackgroundBorderAttributeName];
        [failSet addObject:KKTextBlockBorderAttributeName];
        [failSet addObject:KKTextAttachmentAttributeName];
        [failSet addObject:KKTextHighlightAttributeName];
        [failSet addObject:KKTextGlyphTransformAttributeName];
    });
    
#define Fail { result = NO; *stop = YES; return; }
    __block BOOL result = YES;
    [self enumerateAttributesInRange:self.kk_rangeOfAll options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
        if (attrs.count == 0) return;
        for (NSString *str in attrs.allKeys) {
            if ([failSet containsObject:str]) Fail;
        }
        if (!kiOS7Later) {
            UIFont *font = attrs[NSFontAttributeName];
            if (CFGetTypeID((__bridge CFTypeRef)(font)) == CTFontGetTypeID()) Fail;
        }
        if (attrs[(id)kCTForegroundColorAttributeName] && !attrs[NSForegroundColorAttributeName]) Fail;
        if (attrs[(id)kCTStrokeColorAttributeName] && !attrs[NSStrokeColorAttributeName]) Fail;
        if (attrs[(id)kCTUnderlineColorAttributeName]) {
            if (!kiOS7Later) Fail;
            if (!attrs[NSUnderlineColorAttributeName]) Fail;
        }
        NSParagraphStyle *style = attrs[NSParagraphStyleAttributeName];
        if (style && CFGetTypeID((__bridge CFTypeRef)(style)) == CTParagraphStyleGetTypeID()) Fail;
    }];
    return result;
#undef Fail
}

@end

@implementation NSMutableAttributedString (KKText)

- (void)kk_setAttributes:(NSDictionary *)attributes {
    [self setKk_attributes:attributes];
}

- (void)setKk_attributes:(NSDictionary *)attributes {
    if (attributes == (id)[NSNull null]) attributes = nil;
    [self setAttributes:@{} range:NSMakeRange(0, self.length)];
    [attributes enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [self kk_setAttribute:key value:obj];
    }];
}

- (void)kk_setAttribute:(NSString *)name value:(id)value {
    [self kk_setAttribute:name value:value range:NSMakeRange(0, self.length)];
}

- (void)kk_setAttribute:(NSString *)name value:(id)value range:(NSRange)range {
    if (!name || [NSNull isEqual:name]) return;
    if (value && ![NSNull isEqual:value]) [self addAttribute:name value:value range:range];
    else [self removeAttribute:name range:range];
}

- (void)kk_removeAttributesInRange:(NSRange)range {
    [self setAttributes:nil range:range];
}

#pragma mark - Property Setter

- (void)setKk_font:(UIFont *)font {
    /*
     In iOS7 and later, UIFont is toll-free bridged to CTFontRef,
     although Apple does not mention it in documentation.
     
     In iOS6, UIFont is a wrapper for CTFontRef, so CoreText can alse use UIfont,
     but UILabel/UITextView cannot use CTFontRef.
     
     We use UIFont for both CoreText and UIKit.
     */
    [self kk_setFont:font range:NSMakeRange(0, self.length)];
}

- (void)setKk_kern:(NSNumber *)kern {
    [self kk_setKern:kern range:NSMakeRange(0, self.length)];
}

- (void)setKk_color:(UIColor *)color {
    [self kk_setColor:color range:NSMakeRange(0, self.length)];
}

- (void)setKk_backgroundColor:(UIColor *)backgroundColor {
    [self kk_setBackgroundColor:backgroundColor range:NSMakeRange(0, self.length)];
}

- (void)setKk_strokeWidth:(NSNumber *)strokeWidth {
    [self kk_setStrokeWidth:strokeWidth range:NSMakeRange(0, self.length)];
}

- (void)setKk_strokeColor:(UIColor *)strokeColor {
    [self kk_setStrokeColor:strokeColor range:NSMakeRange(0, self.length)];
}

- (void)setKk_shadow:(NSShadow *)shadow {
    [self kk_setShadow:shadow range:NSMakeRange(0, self.length)];
}

- (void)setKk_strikethroughStyle:(NSUnderlineStyle)strikethroughStyle {
    [self kk_setStrikethroughStyle:strikethroughStyle range:NSMakeRange(0, self.length)];
}

- (void)setKk_strikethroughColor:(UIColor *)strikethroughColor {
    [self kk_setStrikethroughColor:strikethroughColor range:NSMakeRange(0, self.length)];
}

- (void)setKk_underlineStyle:(NSUnderlineStyle)underlineStyle {
    [self kk_setUnderlineStyle:underlineStyle range:NSMakeRange(0, self.length)];
}

- (void)setKk_underlineColor:(UIColor *)underlineColor {
    [self kk_setUnderlineColor:underlineColor range:NSMakeRange(0, self.length)];
}

- (void)setKk_ligature:(NSNumber *)ligature {
    [self kk_setLigature:ligature range:NSMakeRange(0, self.length)];
}

- (void)setKk_textEffect:(NSString *)textEffect {
    [self kk_setTextEffect:textEffect range:NSMakeRange(0, self.length)];
}

- (void)setKk_obliqueness:(NSNumber *)obliqueness {
    [self kk_setObliqueness:obliqueness range:NSMakeRange(0, self.length)];
}

- (void)setKk_expansion:(NSNumber *)expansion {
    [self kk_setExpansion:expansion range:NSMakeRange(0, self.length)];
}

- (void)setKk_baselineOffset:(NSNumber *)baselineOffset {
    [self kk_setBaselineOffset:baselineOffset range:NSMakeRange(0, self.length)];
}

- (void)setKk_verticalGlyphForm:(BOOL)verticalGlyphForm {
    [self kk_setVerticalGlyphForm:verticalGlyphForm range:NSMakeRange(0, self.length)];
}

- (void)setKk_language:(NSString *)language {
    [self kk_setLanguage:language range:NSMakeRange(0, self.length)];
}

- (void)setKk_writingDirection:(NSArray *)writingDirection {
    [self kk_setWritingDirection:writingDirection range:NSMakeRange(0, self.length)];
}

- (void)setKk_paragraphStyle:(NSParagraphStyle *)paragraphStyle {
    /*
     NSParagraphStyle is NOT toll-free bridged to CTParagraphStyleRef.
     
     CoreText can use both NSParagraphStyle and CTParagraphStyleRef,
     but UILabel/UITextView can only use NSParagraphStyle.
     
     We use NSParagraphStyle in both CoreText and UIKit.
     */
    [self kk_setParagraphStyle:paragraphStyle range:NSMakeRange(0, self.length)];
}

- (void)setKk_alignment:(NSTextAlignment)alignment {
    [self kk_setAlignment:alignment range:NSMakeRange(0, self.length)];
}

- (void)setKk_baseWritingDirection:(NSWritingDirection)baseWritingDirection {
    [self kk_setBaseWritingDirection:baseWritingDirection range:NSMakeRange(0, self.length)];
}

- (void)setKk_lineSpacing:(CGFloat)lineSpacing {
    [self kk_setLineSpacing:lineSpacing range:NSMakeRange(0, self.length)];
}

- (void)setKk_paragraphSpacing:(CGFloat)paragraphSpacing {
    [self kk_setParagraphSpacing:paragraphSpacing range:NSMakeRange(0, self.length)];
}

- (void)setKk_paragraphSpacingBefore:(CGFloat)paragraphSpacingBefore {
    [self kk_setParagraphSpacing:paragraphSpacingBefore range:NSMakeRange(0, self.length)];
}

- (void)setKk_firstLineHeadIndent:(CGFloat)firstLineHeadIndent {
    [self kk_setFirstLineHeadIndent:firstLineHeadIndent range:NSMakeRange(0, self.length)];
}

- (void)setKk_headIndent:(CGFloat)headIndent {
    [self kk_setHeadIndent:headIndent range:NSMakeRange(0, self.length)];
}

- (void)setKk_tailIndent:(CGFloat)tailIndent {
    [self kk_setTailIndent:tailIndent range:NSMakeRange(0, self.length)];
}

- (void)setKk_lineBreakMode:(NSLineBreakMode)lineBreakMode {
    [self kk_setLineBreakMode:lineBreakMode range:NSMakeRange(0, self.length)];
}

- (void)setKk_minimumLineHeight:(CGFloat)minimumLineHeight {
    [self kk_setMinimumLineHeight:minimumLineHeight range:NSMakeRange(0, self.length)];
}

- (void)setKk_maximumLineHeight:(CGFloat)maximumLineHeight {
    [self kk_setMaximumLineHeight:maximumLineHeight range:NSMakeRange(0, self.length)];
}

- (void)setKk_lineHeightMultiple:(CGFloat)lineHeightMultiple {
    [self kk_setLineHeightMultiple:lineHeightMultiple range:NSMakeRange(0, self.length)];
}

- (void)setKk_hyphenationFactor:(float)hyphenationFactor {
    [self kk_setHyphenationFactor:hyphenationFactor range:NSMakeRange(0, self.length)];
}

- (void)setKk_defaultTabInterval:(CGFloat)defaultTabInterval {
    [self kk_setDefaultTabInterval:defaultTabInterval range:NSMakeRange(0, self.length)];
}

- (void)setKk_tabStops:(NSArray *)tabStops {
    [self kk_setTabStops:tabStops range:NSMakeRange(0, self.length)];
}

- (void)setKk_textShadow:(KKTextShadow *)textShadow {
    [self kk_setTextShadow:textShadow range:NSMakeRange(0, self.length)];
}

- (void)setKk_textInnerShadow:(KKTextShadow *)textInnerShadow {
    [self kk_setTextInnerShadow:textInnerShadow range:NSMakeRange(0, self.length)];
}

- (void)setKk_textUnderline:(KKTextDecoration *)textUnderline {
    [self kk_setTextUnderline:textUnderline range:NSMakeRange(0, self.length)];
}

- (void)setKk_textStrikethrough:(KKTextDecoration *)textStrikethrough {
    [self kk_setTextStrikethrough:textStrikethrough range:NSMakeRange(0, self.length)];
}

- (void)setKk_textBorder:(KKTextBorder *)textBorder {
    [self kk_setTextBorder:textBorder range:NSMakeRange(0, self.length)];
}

- (void)setKk_textBackgroundBorder:(KKTextBorder *)textBackgroundBorder {
    [self kk_setTextBackgroundBorder:textBackgroundBorder range:NSMakeRange(0, self.length)];
}

- (void)setKk_textGlyphTransform:(CGAffineTransform)textGlyphTransform {
    [self kk_setTextGlyphTransform:textGlyphTransform range:NSMakeRange(0, self.length)];
}

#pragma mark - Range Setter

- (void)kk_setFont:(UIFont *)font range:(NSRange)range {
    /*
     In iOS7 and later, UIFont is toll-free bridged to CTFontRef,
     although Apple does not mention it in documentation.
     
     In iOS6, UIFont is a wrapper for CTFontRef, so CoreText can alse use UIfont,
     but UILabel/UITextView cannot use CTFontRef.
     
     We use UIFont for both CoreText and UIKit.
     */
    [self kk_setAttribute:NSFontAttributeName value:font range:range];
}

- (void)kk_setKern:(NSNumber *)kern range:(NSRange)range {
    [self kk_setAttribute:NSKernAttributeName value:kern range:range];
}

- (void)kk_setColor:(UIColor *)color range:(NSRange)range {
    [self kk_setAttribute:(id)kCTForegroundColorAttributeName value:(id)color.CGColor range:range];
    [self kk_setAttribute:NSForegroundColorAttributeName value:color range:range];
}

- (void)kk_setBackgroundColor:(UIColor *)backgroundColor range:(NSRange)range {
    [self kk_setAttribute:NSBackgroundColorAttributeName value:backgroundColor range:range];
}

- (void)kk_setStrokeWidth:(NSNumber *)strokeWidth range:(NSRange)range {
    [self kk_setAttribute:NSStrokeWidthAttributeName value:strokeWidth range:range];
}

- (void)kk_setStrokeColor:(UIColor *)strokeColor range:(NSRange)range {
    [self kk_setAttribute:(id)kCTStrokeColorAttributeName value:(id)strokeColor.CGColor range:range];
    [self kk_setAttribute:NSStrokeColorAttributeName value:strokeColor range:range];
}

- (void)kk_setShadow:(NSShadow *)shadow range:(NSRange)range {
    [self kk_setAttribute:NSShadowAttributeName value:shadow range:range];
}

- (void)kk_setStrikethroughStyle:(NSUnderlineStyle)strikethroughStyle range:(NSRange)range {
    NSNumber *style = strikethroughStyle == 0 ? nil : @(strikethroughStyle);
    [self kk_setAttribute:NSStrikethroughStyleAttributeName value:style range:range];
}

- (void)kk_setStrikethroughColor:(UIColor *)strikethroughColor range:(NSRange)range {
    if (kSystemVersion >= 7) {
        [self kk_setAttribute:NSStrikethroughColorAttributeName value:strikethroughColor range:range];
    }
}

- (void)kk_setUnderlineStyle:(NSUnderlineStyle)underlineStyle range:(NSRange)range {
    NSNumber *style = underlineStyle == 0 ? nil : @(underlineStyle);
    [self kk_setAttribute:NSUnderlineStyleAttributeName value:style range:range];
}

- (void)kk_setUnderlineColor:(UIColor *)underlineColor range:(NSRange)range {
    [self kk_setAttribute:(id)kCTUnderlineColorAttributeName value:(id)underlineColor.CGColor range:range];
    if (kSystemVersion >= 7) {
        [self kk_setAttribute:NSUnderlineColorAttributeName value:underlineColor range:range];
    }
}

- (void)kk_setLigature:(NSNumber *)ligature range:(NSRange)range {
    [self kk_setAttribute:NSLigatureAttributeName value:ligature range:range];
}

- (void)kk_setTextEffect:(NSString *)textEffect range:(NSRange)range {
    if (kSystemVersion >= 7) {
        [self kk_setAttribute:NSTextEffectAttributeName value:textEffect range:range];
    }
}

- (void)kk_setObliqueness:(NSNumber *)obliqueness range:(NSRange)range {
    if (kSystemVersion >= 7) {
        [self kk_setAttribute:NSObliquenessAttributeName value:obliqueness range:range];
    }
}

- (void)kk_setExpansion:(NSNumber *)expansion range:(NSRange)range {
    if (kSystemVersion >= 7) {
        [self kk_setAttribute:NSExpansionAttributeName value:expansion range:range];
    }
}

- (void)kk_setBaselineOffset:(NSNumber *)baselineOffset range:(NSRange)range {
    if (kSystemVersion >= 7) {
        [self kk_setAttribute:NSBaselineOffsetAttributeName value:baselineOffset range:range];
    }
}

- (void)kk_setVerticalGlyphForm:(BOOL)verticalGlyphForm range:(NSRange)range {
    NSNumber *v = verticalGlyphForm ? @(YES) : nil;
    [self kk_setAttribute:NSVerticalGlyphFormAttributeName value:v range:range];
}

- (void)kk_setLanguage:(NSString *)language range:(NSRange)range {
    if (kSystemVersion >= 7) {
        [self kk_setAttribute:(id)kCTLanguageAttributeName value:language range:range];
    }
}

- (void)kk_setWritingDirection:(NSArray *)writingDirection range:(NSRange)range {
    [self kk_setAttribute:(id)kCTWritingDirectionAttributeName value:writingDirection range:range];
}

- (void)kk_setParagraphStyle:(NSParagraphStyle *)paragraphStyle range:(NSRange)range {
    /*
     NSParagraphStyle is NOT toll-free bridged to CTParagraphStyleRef.
     
     CoreText can use both NSParagraphStyle and CTParagraphStyleRef,
     but UILabel/UITextView can only use NSParagraphStyle.
     
     We use NSParagraphStyle in both CoreText and UIKit.
     */
    [self kk_setAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:range];
}

#define ParagraphStyleSet(_attr_) \
[self enumerateAttribute:NSParagraphStyleAttributeName \
                 inRange:range \
                 options:kNilOptions \
              usingBlock: ^(NSParagraphStyle *value, NSRange subRange, BOOL *stop) { \
                  NSMutableParagraphStyle *style = nil; \
                  if (value) { \
                      if (CFGetTypeID((__bridge CFTypeRef)(value)) == CTParagraphStyleGetTypeID()) { \
                          value = [NSParagraphStyle kk_styleWithCTStyle:(__bridge CTParagraphStyleRef)(value)]; \
                      } \
                      if (value. _attr_ == _attr_) return; \
                      style = value.mutableCopy; \
                  } else { \
                      if ([NSParagraphStyle defaultParagraphStyle]. _attr_ == _attr_) return; \
                      style = [NSParagraphStyle defaultParagraphStyle].mutableCopy; \
                  } \
                  style. _attr_ = _attr_; \
                  [self kk_setParagraphStyle:style.copy range:subRange]; \
              }];

- (void)kk_setAlignment:(NSTextAlignment)alignment range:(NSRange)range {
    ParagraphStyleSet(alignment);
}

- (void)kk_setBaseWritingDirection:(NSWritingDirection)baseWritingDirection range:(NSRange)range {
    ParagraphStyleSet(baseWritingDirection);
}

- (void)kk_setLineSpacing:(CGFloat)lineSpacing range:(NSRange)range {
    ParagraphStyleSet(lineSpacing);
}

- (void)kk_setParagraphSpacing:(CGFloat)paragraphSpacing range:(NSRange)range {
    ParagraphStyleSet(paragraphSpacing);
}

- (void)kk_setParagraphSpacingBefore:(CGFloat)paragraphSpacingBefore range:(NSRange)range {
    ParagraphStyleSet(paragraphSpacingBefore);
}

- (void)kk_setFirstLineHeadIndent:(CGFloat)firstLineHeadIndent range:(NSRange)range {
    ParagraphStyleSet(firstLineHeadIndent);
}

- (void)kk_setHeadIndent:(CGFloat)headIndent range:(NSRange)range {
    ParagraphStyleSet(headIndent);
}

- (void)kk_setTailIndent:(CGFloat)tailIndent range:(NSRange)range {
    ParagraphStyleSet(tailIndent);
}

- (void)kk_setLineBreakMode:(NSLineBreakMode)lineBreakMode range:(NSRange)range {
    ParagraphStyleSet(lineBreakMode);
}

- (void)kk_setMinimumLineHeight:(CGFloat)minimumLineHeight range:(NSRange)range {
    ParagraphStyleSet(minimumLineHeight);
}

- (void)kk_setMaximumLineHeight:(CGFloat)maximumLineHeight range:(NSRange)range {
    ParagraphStyleSet(maximumLineHeight);
}

- (void)kk_setLineHeightMultiple:(CGFloat)lineHeightMultiple range:(NSRange)range {
    ParagraphStyleSet(lineHeightMultiple);
}

- (void)kk_setHyphenationFactor:(float)hyphenationFactor range:(NSRange)range {
    ParagraphStyleSet(hyphenationFactor);
}

- (void)kk_setDefaultTabInterval:(CGFloat)defaultTabInterval range:(NSRange)range {
    if (!kiOS7Later) return;
    ParagraphStyleSet(defaultTabInterval);
}

- (void)kk_setTabStops:(NSArray *)tabStops range:(NSRange)range {
    if (!kiOS7Later) return;
    ParagraphStyleSet(tabStops);
}

#undef ParagraphStyleSet

- (void)kk_setSuperscript:(NSNumber *)superscript range:(NSRange)range {
    if ([superscript isEqualToNumber:@(0)]) {
        superscript = nil;
    }
    [self kk_setAttribute:(id)kCTSuperscriptAttributeName value:superscript range:range];
}

- (void)kk_setGlyphInfo:(CTGlyphInfoRef)glyphInfo range:(NSRange)range {
    [self kk_setAttribute:(id)kCTGlyphInfoAttributeName value:(__bridge id)glyphInfo range:range];
}

- (void)kk_setCharacterShape:(NSNumber *)characterShape range:(NSRange)range {
    [self kk_setAttribute:(id)kCTCharacterShapeAttributeName value:characterShape range:range];
}

- (void)kk_setRunDelegate:(CTRunDelegateRef)runDelegate range:(NSRange)range {
    [self kk_setAttribute:(id)kCTRunDelegateAttributeName value:(__bridge id)runDelegate range:range];
}

- (void)kk_setBaselineClass:(CFStringRef)baselineClass range:(NSRange)range {
    [self kk_setAttribute:(id)kCTBaselineClassAttributeName value:(__bridge id)baselineClass range:range];
}

- (void)kk_setBaselineInfo:(CFDictionaryRef)baselineInfo range:(NSRange)range {
    [self kk_setAttribute:(id)kCTBaselineInfoAttributeName value:(__bridge id)baselineInfo range:range];
}

- (void)kk_setBaselineReferenceInfo:(CFDictionaryRef)referenceInfo range:(NSRange)range {
    [self kk_setAttribute:(id)kCTBaselineReferenceInfoAttributeName value:(__bridge id)referenceInfo range:range];
}

- (void)kk_setRubyAnnotation:(CTRubyAnnotationRef)ruby range:(NSRange)range {
    if (kSystemVersion >= 8) {
        [self kk_setAttribute:(id)kCTRubyAnnotationAttributeName value:(__bridge id)ruby range:range];
    }
}

- (void)kk_setAttachment:(NSTextAttachment *)attachment range:(NSRange)range {
    if (kSystemVersion >= 7) {
        [self kk_setAttribute:NSAttachmentAttributeName value:attachment range:range];
    }
}

- (void)kk_setLink:(id)link range:(NSRange)range {
    if (kSystemVersion >= 7) {
        [self kk_setAttribute:NSLinkAttributeName value:link range:range];
    }
}

- (void)kk_setTextBackedString:(KKTextBackedString *)textBackedString range:(NSRange)range {
    [self kk_setAttribute:KKTextBackedStringAttributeName value:textBackedString range:range];
}

- (void)kk_setTextBinding:(KKTextBinding *)textBinding range:(NSRange)range {
    [self kk_setAttribute:KKTextBindingAttributeName value:textBinding range:range];
}

- (void)kk_setTextShadow:(KKTextShadow *)textShadow range:(NSRange)range {
    [self kk_setAttribute:KKTextShadowAttributeName value:textShadow range:range];
}

- (void)kk_setTextInnerShadow:(KKTextShadow *)textInnerShadow range:(NSRange)range {
    [self kk_setAttribute:KKTextInnerShadowAttributeName value:textInnerShadow range:range];
}

- (void)kk_setTextUnderline:(KKTextDecoration *)textUnderline range:(NSRange)range {
    [self kk_setAttribute:KKTextUnderlineAttributeName value:textUnderline range:range];
}

- (void)kk_setTextStrikethrough:(KKTextDecoration *)textStrikethrough range:(NSRange)range {
    [self kk_setAttribute:KKTextStrikethroughAttributeName value:textStrikethrough range:range];
}

- (void)kk_setTextBorder:(KKTextBorder *)textBorder range:(NSRange)range {
    [self kk_setAttribute:KKTextBorderAttributeName value:textBorder range:range];
}

- (void)kk_setTextBackgroundBorder:(KKTextBorder *)textBackgroundBorder range:(NSRange)range {
    [self kk_setAttribute:KKTextBackgroundBorderAttributeName value:textBackgroundBorder range:range];
}

- (void)kk_setTextAttachment:(KKTextAttachment *)textAttachment range:(NSRange)range {
    [self kk_setAttribute:KKTextAttachmentAttributeName value:textAttachment range:range];
}

- (void)kk_setTextHighlight:(KKTextHighlight *)textHighlight range:(NSRange)range {
    [self kk_setAttribute:KKTextHighlightAttributeName value:textHighlight range:range];
}

- (void)kk_setTextBlockBorder:(KKTextBorder *)textBlockBorder range:(NSRange)range {
    [self kk_setAttribute:KKTextBlockBorderAttributeName value:textBlockBorder range:range];
}

- (void)kk_setTextRubyAnnotation:(KKTextRubyAnnotation *)ruby range:(NSRange)range {
    if (kiOS8Later) {
        CTRubyAnnotationRef rubyRef = [ruby CTRubyAnnotation];
        [self kk_setRubyAnnotation:rubyRef range:range];
        if (rubyRef) CFRelease(rubyRef);
    }
}

- (void)kk_setTextGlyphTransform:(CGAffineTransform)textGlyphTransform range:(NSRange)range {
    NSValue *value = CGAffineTransformIsIdentity(textGlyphTransform) ? nil : [NSValue valueWithCGAffineTransform:textGlyphTransform];
    [self kk_setAttribute:KKTextGlyphTransformAttributeName value:value range:range];
}

- (void)kk_setTextHighlightRange:(NSRange)range
                           color:(UIColor *)color
                 backgroundColor:(UIColor *)backgroundColor
                        userInfo:(NSDictionary *)userInfo
                       tapAction:(KKTextAction)tapAction
                 longPressAction:(KKTextAction)longPressAction {
    KKTextHighlight *highlight = [KKTextHighlight highlightWithBackgroundColor:backgroundColor];
    highlight.userInfo = userInfo;
    highlight.tapAction = tapAction;
    highlight.longPressAction = longPressAction;
    if (color) [self kk_setColor:color range:range];
    [self kk_setTextHighlight:highlight range:range];
}

- (void)kk_setTextHighlightRange:(NSRange)range
                           color:(UIColor *)color
                 backgroundColor:(UIColor *)backgroundColor
                       tapAction:(KKTextAction)tapAction {
    [self kk_setTextHighlightRange:range
                         color:color
               backgroundColor:backgroundColor
                      userInfo:nil
                     tapAction:tapAction
               longPressAction:nil];
}

- (void)kk_setTextHighlightRange:(NSRange)range
                           color:(UIColor *)color
                 backgroundColor:(UIColor *)backgroundColor
                        userInfo:(NSDictionary *)userInfo {
    [self kk_setTextHighlightRange:range
                         color:color
               backgroundColor:backgroundColor
                      userInfo:userInfo
                     tapAction:nil
               longPressAction:nil];
}

- (void)kk_insertString:(NSString *)string atIndex:(NSUInteger)location {
    [self replaceCharactersInRange:NSMakeRange(location, 0) withString:string];
    [self kk_removeDiscontinuousAttributesInRange:NSMakeRange(location, string.length)];
}

- (void)kk_appendString:(NSString *)string {
    NSUInteger length = self.length;
    [self replaceCharactersInRange:NSMakeRange(length, 0) withString:string];
    [self kk_removeDiscontinuousAttributesInRange:NSMakeRange(length, string.length)];
}

- (void)kk_setClearColorToJoinedEmoji {
    NSString *str = self.string;
    if (str.length < 8) return;
    
    // Most string do not contains the joined-emoji, test the joiner first.
    BOOL containsJoiner = NO;
    {
        CFStringRef cfStr = (__bridge CFStringRef)str;
        BOOL needFree = NO;
        UniChar *chars = NULL;
        chars = (void *)CFStringGetCharactersPtr(cfStr);
        if (!chars) {
            chars = malloc(str.length * sizeof(UniChar));
            if (chars) {
                needFree = YES;
                CFStringGetCharacters(cfStr, CFRangeMake(0, str.length), chars);
            }
        }
        if (!chars) { // fail to get unichar..
            containsJoiner = YES;
        } else {
            for (int i = 0, max = (int)str.length; i < max; i++) {
                if (chars[i] == 0x200D) { // 'ZERO WIDTH JOINER' (U+200D)
                    containsJoiner = YES;
                    break;
                }
            }
            if (needFree) free(chars);
        }
    }
    if (!containsJoiner) return;
    
    // NSRegularExpression is designed to be immutable and thread safe.
    static NSRegularExpression *regex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"((👨‍👩‍👧‍👦|👨‍👩‍👦‍👦|👨‍👩‍👧‍👧|👩‍👩‍👧‍👦|👩‍👩‍👦‍👦|👩‍👩‍👧‍👧|👨‍👨‍👧‍👦|👨‍👨‍👦‍👦|👨‍👨‍👧‍👧)+|(👨‍👩‍👧|👩‍👩‍👦|👩‍👩‍👧|👨‍👨‍👦|👨‍👨‍👧))" options:kNilOptions error:nil];
    });
    
    UIColor *clear = [UIColor clearColor];
    [regex enumerateMatchesInString:str options:kNilOptions range:NSMakeRange(0, str.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        [self kk_setColor:clear range:result.range];
    }];
}

- (void)kk_removeDiscontinuousAttributesInRange:(NSRange)range {
    NSArray *keys = [NSMutableAttributedString kk_allDiscontinuousAttributeKeys];
    for (NSString *key in keys) {
        [self removeAttribute:key range:range];
    }
}

+ (NSArray *)kk_allDiscontinuousAttributeKeys {
    static NSMutableArray *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[(id)kCTSuperscriptAttributeName,
                 (id)kCTRunDelegateAttributeName,
                 KKTextBackedStringAttributeName,
                 KKTextBindingAttributeName,
                 KKTextAttachmentAttributeName].mutableCopy;
        if (kiOS8Later) {
            [keys addObject:(id)kCTRubyAnnotationAttributeName];
        }
        if (kiOS7Later) {
            [keys addObject:NSAttachmentAttributeName];
        }
    });
    return keys;
}

@end
