//
//  KKTextAttribute.h
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/08.
//  Originally created by ibireme.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Enum Define

/// The attribute type
typedef NS_OPTIONS(NSInteger, KKTextAttributeType) {
    KKTextAttributeTypeNone     = 0,
    KKTextAttributeTypeUIKit    = 1 << 0, ///< UIKit attributes, such as UILabel/UITextField/drawInRect.
    KKTextAttributeTypeCoreText = 1 << 1, ///< CoreText attributes, used by CoreText.
    KKTextAttributeTypeKKText   = 1 << 2, ///< KKText attributes, used by KKText.
};

/// Get the attribute type from an attribute name.
extern KKTextAttributeType KKTextAttributeGetType(NSString *attributeName);

/**
 Line style in KKText (similar to NSUnderlineStyle).
 */
typedef NS_OPTIONS (NSInteger, KKTextLineStyle) {
    // basic style (bitmask:0xFF)
    KKTextLineStyleNone       = 0x00, ///< (        ) Do not draw a line (Default).
    KKTextLineStyleSingle     = 0x01, ///< (──────) Draw a single line.
    KKTextLineStyleThick      = 0x02, ///< (━━━━━━━) Draw a thick line.
    KKTextLineStyleDouble     = 0x09, ///< (══════) Draw a double line.
    
    // style pattern (bitmask:0xF00)
    KKTextLineStylePatternSolid      = 0x000, ///< (────────) Draw a solid line (Default).
    KKTextLineStylePatternDot        = 0x100, ///< (‑ ‑ ‑ ‑ ‑ ‑) Draw a line of dots.
    KKTextLineStylePatternDash       = 0x200, ///< (— — — —) Draw a line of dashes.
    KKTextLineStylePatternDashDot    = 0x300, ///< (— ‑ — ‑ — ‑) Draw a line of alternating dashes and dots.
    KKTextLineStylePatternDashDotDot = 0x400, ///< (— ‑ ‑ — ‑ ‑) Draw a line of alternating dashes and two dots.
    KKTextLineStylePatternCircleDot  = 0x900, ///< (••••••••••••) Draw a line of small circle dots.
};

/**
 Text vertical alignment.
 */
typedef NS_ENUM(NSInteger, KKTextVerticalAlignment) {
    KKTextVerticalAlignmentTop =    0, ///< Top alignment.
    KKTextVerticalAlignmentCenter = 1, ///< Center alignment.
    KKTextVerticalAlignmentBottom = 2, ///< Bottom alignment.
};

/**
 The direction define in KKText.
 */
typedef NS_OPTIONS(NSUInteger, KKTextDirection) {
    KKTextDirectionNone   = 0,
    KKTextDirectionTop    = 1 << 0,
    KKTextDirectionRight  = 1 << 1,
    KKTextDirectionBottom = 1 << 2,
    KKTextDirectionLeft   = 1 << 3,
};

/**
 The trunction type, tells the truncation engine which type of truncation is being requested.
 */
typedef NS_ENUM (NSUInteger, KKTextTruncationType) {
    /// No truncate.
    KKTextTruncationTypeNone   = 0,
    
    /// Truncate at the beginning of the line, leaving the end portion visible.
    KKTextTruncationTypeStart  = 1,
    
    /// Truncate at the end of the line, leaving the start portion visible.
    KKTextTruncationTypeEnd    = 2,
    
    /// Truncate in the middle of the line, leaving both the start and the end portions visible.
    KKTextTruncationTypeMiddle = 3,
};



#pragma mark - Attribute Name Defined in KKText

/// The value of this attribute is a `KKTextBackedString` object.
/// Use this attribute to store the original plain text if it is replaced by something else (such as attachment).
UIKIT_EXTERN NSString *const KKTextBackedStringAttributeName;

/// The value of this attribute is a `KKTextBinding` object.
/// Use this attribute to bind a range of text together, as if it was a single charactor.
UIKIT_EXTERN NSString *const KKTextBindingAttributeName;

/// The value of this attribute is a `KKTextShadow` object.
/// Use this attribute to add shadow to a range of text.
/// Shadow will be drawn below text glyphs. Use KKTextShadow.subShadow to add multi-shadow.
UIKIT_EXTERN NSString *const KKTextShadowAttributeName;

/// The value of this attribute is a `KKTextShadow` object.
/// Use this attribute to add inner shadow to a range of text.
/// Inner shadow will be drawn above text glyphs. Use KKTextShadow.subShadow to add multi-shadow.
UIKIT_EXTERN NSString *const KKTextInnerShadowAttributeName;

/// The value of this attribute is a `KKTextDecoration` object.
/// Use this attribute to add underline to a range of text.
/// The underline will be drawn below text glyphs.
UIKIT_EXTERN NSString *const KKTextUnderlineAttributeName;

/// The value of this attribute is a `KKTextDecoration` object.
/// Use this attribute to add strikethrough (delete line) to a range of text.
/// The strikethrough will be drawn above text glyphs.
UIKIT_EXTERN NSString *const KKTextStrikethroughAttributeName;

/// The value of this attribute is a `KKTextBorder` object.
/// Use this attribute to add cover border or cover color to a range of text.
/// The border will be drawn above the text glyphs.
UIKIT_EXTERN NSString *const KKTextBorderAttributeName;

/// The value of this attribute is a `KKTextBorder` object.
/// Use this attribute to add background border or background color to a range of text.
/// The border will be drawn below the text glyphs.
UIKIT_EXTERN NSString *const KKTextBackgroundBorderAttributeName;

/// The value of this attribute is a `KKTextBorder` object.
/// Use this attribute to add a code block border to one or more line of text.
/// The border will be drawn below the text glyphs.
UIKIT_EXTERN NSString *const KKTextBlockBorderAttributeName;

/// The value of this attribute is a `KKTextAttachment` object.
/// Use this attribute to add attachment to text.
/// It should be used in conjunction with a CTRunDelegate.
UIKIT_EXTERN NSString *const KKTextAttachmentAttributeName;

/// The value of this attribute is a `KKTextHighlight` object.
/// Use this attribute to add a touchable highlight state to a range of text.
UIKIT_EXTERN NSString *const KKTextHighlightAttributeName;

/// The value of this attribute is a `NSValue` object stores CGAffineTransform.
/// Use this attribute to add transform to each glyph in a range of text.
UIKIT_EXTERN NSString *const KKTextGlyphTransformAttributeName;



#pragma mark - String Token Define

UIKIT_EXTERN NSString *const KKTextAttachmentToken; ///< Object replacement character (U+FFFC), used for text attachment.
UIKIT_EXTERN NSString *const KKTextTruncationToken; ///< Horizontal ellipsis (U+2026), used for text truncation  "…".



#pragma mark - Attribute Value Define

/**
 The tap/long press action callback defined in KKText.
 
 @param containerView The text container view (such as KKLabel/KKTextView).
 @param text          The whole text.
 @param range         The text range in `text` (if no range, the range.location is NSNotFound).
 @param rect          The text frame in `containerView` (if no data, the rect is CGRectNull).
 */
typedef void(^KKTextAction)(UIView *containerView, NSAttributedString *text, NSRange range, CGRect rect);


/**
 KKTextBackedString objects are used by the NSAttributedString class cluster
 as the values for text backed string attributes (stored in the attributed 
 string under the key named KKTextBackedStringAttributeName).
 
 It may used for copy/paste plain text from attributed string.
 Example: If :) is replace by a custom emoji (such as😊), the backed string can be set to @":)".
 */
@interface KKTextBackedString : NSObject <NSCoding, NSCopying>
+ (instancetype)stringWithString:(nullable NSString *)string;
@property (nullable, nonatomic, copy) NSString *string; ///< backed string
@end


/**
 KKTextBinding objects are used by the NSAttributedString class cluster
 as the values for shadow attributes (stored in the attributed string under
 the key named KKTextBindingAttributeName).
 
 Add this to a range of text will make the specified characters 'binding together'.
 KKTextView will treat the range of text as a single character during text 
 selection and edit.
 */
@interface KKTextBinding : NSObject <NSCoding, NSCopying>
+ (instancetype)bindingWithDeleteConfirm:(BOOL)deleteConfirm;
@property (nonatomic) BOOL deleteConfirm; ///< confirm the range when delete in KKTextView
@end


/**
 KKTextShadow objects are used by the NSAttributedString class cluster
 as the values for shadow attributes (stored in the attributed string under
 the key named KKTextShadowAttributeName or KKTextInnerShadowAttributeName).
 
 It's similar to `NSShadow`, but offers more options.
 */
@interface KKTextShadow : NSObject <NSCoding, NSCopying>
+ (instancetype)shadowWithColor:(nullable UIColor *)color offset:(CGSize)offset radius:(CGFloat)radius;

@property (nullable, nonatomic, strong) UIColor *color; ///< shadow color
@property (nonatomic) CGSize offset;                    ///< shadow offset
@property (nonatomic) CGFloat radius;                   ///< shadow blur radius
@property (nonatomic) CGBlendMode blendMode;            ///< shadow blend mode
@property (nullable, nonatomic, strong) KKTextShadow *subShadow;  ///< a sub shadow which will be added above the parent shadow

+ (instancetype)shadowWithNSShadow:(NSShadow *)nsShadow; ///< convert NSShadow to KKTextShadow
- (NSShadow *)nsShadow; ///< convert KKTextShadow to NSShadow
@end


/**
 KKTextDecorationLine objects are used by the NSAttributedString class cluster
 as the values for decoration line attributes (stored in the attributed string under
 the key named KKTextUnderlineAttributeName or KKTextStrikethroughAttributeName).
 
 When it's used as underline, the line is drawn below text glyphs;
 when it's used as strikethrough, the line is drawn above text glyphs.
 */
@interface KKTextDecoration : NSObject <NSCoding, NSCopying>
+ (instancetype)decorationWithStyle:(KKTextLineStyle)style;
+ (instancetype)decorationWithStyle:(KKTextLineStyle)style width:(nullable NSNumber *)width color:(nullable UIColor *)color;
@property (nonatomic) KKTextLineStyle style;                   ///< line style
@property (nullable, nonatomic, strong) NSNumber *width;       ///< line width (nil means automatic width)
@property (nullable, nonatomic, strong) UIColor *color;        ///< line color (nil means automatic color)
@property (nullable, nonatomic, strong) KKTextShadow *shadow;  ///< line shadow
@end


/**
 KKTextBorder objects are used by the NSAttributedString class cluster
 as the values for border attributes (stored in the attributed string under
 the key named KKTextBorderAttributeName or KKTextBackgroundBorderAttributeName).
 
 It can be used to draw a border around a range of text, or draw a background
 to a range of text.
 
 Example:
    ╭──────╮
    │ Text │
    ╰──────╯
 */
@interface KKTextBorder : NSObject <NSCoding, NSCopying>
+ (instancetype)borderWithLineStyle:(KKTextLineStyle)lineStyle lineWidth:(CGFloat)width strokeColor:(nullable UIColor *)color;
+ (instancetype)borderWithFillColor:(nullable UIColor *)color cornerRadius:(CGFloat)cornerRadius;
@property (nonatomic) KKTextLineStyle lineStyle;              ///< border line style
@property (nonatomic) CGFloat strokeWidth;                    ///< border line width
@property (nullable, nonatomic, strong) UIColor *strokeColor; ///< border line color
@property (nonatomic) CGLineJoin lineJoin;                    ///< border line join
@property (nonatomic) UIEdgeInsets insets;                    ///< border insets for text bounds
@property (nonatomic) CGFloat cornerRadius;                   ///< border corder radius
@property (nullable, nonatomic, strong) KKTextShadow *shadow; ///< border shadow
@property (nullable, nonatomic, strong) UIColor *fillColor;   ///< inner fill color
@end


/**
 KKTextAttachment objects are used by the NSAttributedString class cluster 
 as the values for attachment attributes (stored in the attributed string under 
 the key named KKTextAttachmentAttributeName).
 
 When display an attributed string which contains `KKTextAttachment` object,
 the content will be placed in text metric. If the content is `UIImage`, 
 then it will be drawn to CGContext; if the content is `UIView` or `CALayer`, 
 then it will be added to the text container's view or layer.
 */
@interface KKTextAttachment : NSObject<NSCoding, NSCopying>
+ (instancetype)attachmentWithContent:(nullable id)content;
@property (nullable, nonatomic, strong) id content;             ///< Supported type: UIImage, UIView, CALayer
@property (nonatomic) UIViewContentMode contentMode;            ///< Content display mode.
@property (nonatomic) UIEdgeInsets contentInsets;               ///< The insets when drawing content.
@property (nullable, nonatomic, strong) NSDictionary *userInfo; ///< The user information dictionary.
@end


/**
 KKTextHighlight objects are used by the NSAttributedString class cluster
 as the values for touchable highlight attributes (stored in the attributed string
 under the key named KKTextHighlightAttributeName).
 
 When display an attributed string in `KKLabel` or `KKTextView`, the range of 
 highlight text can be toucheds down by users. If a range of text is turned into 
 highlighted state, the `attributes` in `KKTextHighlight` will be used to modify 
 (set or remove) the original attributes in the range for display.
 */
@interface KKTextHighlight : NSObject <NSCoding, NSCopying>

/**
 Attributes that you can apply to text in an attributed string when highlight.
 Key:   Same as CoreText/KKText Attribute Name.
 Value: Modify attribute value when highlight (NSNull for remove attribute).
 */
@property (nullable, nonatomic, copy) NSDictionary<NSString *, id> *attributes;

/**
 Creates a highlight object with specified attributes.
 
 @param attributes The attributes which will replace original attributes when highlight,
        If the value is NSNull, it will removed when highlight.
 */
+ (instancetype)highlightWithAttributes:(nullable NSDictionary<NSString *, id> *)attributes;

/**
 Convenience methods to create a default highlight with the specifeid background color.
 
 @param color The background border color.
 */
+ (instancetype)highlightWithBackgroundColor:(nullable UIColor *)color;

// Convenience methods below to set the `attributes`.
- (void)setFont:(nullable UIFont *)font;
- (void)setColor:(nullable UIColor *)color;
- (void)setStrokeWidth:(nullable NSNumber *)width;
- (void)setStrokeColor:(nullable UIColor *)color;
- (void)setShadow:(nullable KKTextShadow *)shadow;
- (void)setInnerShadow:(nullable KKTextShadow *)shadow;
- (void)setUnderline:(nullable KKTextDecoration *)underline;
- (void)setStrikethrough:(nullable KKTextDecoration *)strikethrough;
- (void)setBackgroundBorder:(nullable KKTextBorder *)border;
- (void)setBorder:(nullable KKTextBorder *)border;
- (void)setAttachment:(nullable KKTextAttachment *)attachment;

/**
 The user information dictionary, default is nil.
 */
@property (nullable, nonatomic, copy) NSDictionary *userInfo;

/**
 Tap action when user tap the highlight, default is nil.
 If the value is nil, KKTextView or KKLabel will ask it's delegate to handle the tap action.
 */
@property (nullable, nonatomic, copy) KKTextAction tapAction;

/**
 Long press action when user long press the highlight, default is nil.
 If the value is nil, KKTextView or KKLabel will ask it's delegate to handle the long press action.
 */
@property (nullable, nonatomic, copy) KKTextAction longPressAction;

@end

NS_ASSUME_NONNULL_END
