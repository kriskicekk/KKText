//
//  KKTextPlatform.h
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/08.
//  Originally created by ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import <TargetConditionals.h>

#if TARGET_OS_OSX
    #define KKTEXT_MAC 1
    #define KKTEXT_UIKIT 0

    #import <AppKit/AppKit.h>
    #import <CoreText/CoreText.h>
    #import <QuartzCore/QuartzCore.h>

    #ifndef UIKIT_EXTERN
        #define UIKIT_EXTERN FOUNDATION_EXTERN
    #endif

    #define UIView NSView
    #define UIWindow NSWindow
    #define UIViewController NSViewController
    #define UIResponder NSResponder
    #define UIApplication NSApplication
    #define UIColor NSColor
    #define UIFont NSFont
    #define UIImage NSImage
    #define UIImageView NSImageView
    #define UIBezierPath NSBezierPath
    #define UIEdgeInsets NSEdgeInsets
    #define UIEdgeInsetsZero NSEdgeInsetsZero
    #define UIEdgeInsetsMake NSEdgeInsetsMake
    #define UIEdgeInsetsInsetRect NSEdgeInsetsInsetRect
    #define NSStringFromCGPoint NSStringFromPoint
    #define NSStringFromCGSize NSStringFromSize
    #define NSStringFromCGRect NSStringFromRect
    #define UIFontDescriptorTraitBold NSFontDescriptorTraitBold
    #define UIFontDescriptorTraitItalic NSFontDescriptorTraitItalic
    #define UITextPosition NSObject
    #define UITextRange NSObject
    #define UITextSelectionRect NSObject

    typedef NS_OPTIONS(NSUInteger, UIDataDetectorTypes) {
        UIDataDetectorTypePhoneNumber = 1 << 0,
        UIDataDetectorTypeLink = 1 << 1,
        UIDataDetectorTypeAddress = 1 << 2,
        UIDataDetectorTypeCalendarEvent = 1 << 3,
        UIDataDetectorTypeNone = 0,
        UIDataDetectorTypeAll = NSUIntegerMax
    };

    typedef NS_ENUM(NSInteger, UIViewContentMode) {
        UIViewContentModeScaleToFill,
        UIViewContentModeScaleAspectFit,
        UIViewContentModeScaleAspectFill,
        UIViewContentModeRedraw,
        UIViewContentModeCenter,
        UIViewContentModeTop,
        UIViewContentModeBottom,
        UIViewContentModeLeft,
        UIViewContentModeRight,
        UIViewContentModeTopLeft,
        UIViewContentModeTopRight,
        UIViewContentModeBottomLeft,
        UIViewContentModeBottomRight,
    };

    typedef NS_ENUM(NSInteger, UITextLayoutDirection) {
        UITextLayoutDirectionRight = 2,
        UITextLayoutDirectionLeft,
        UITextLayoutDirectionUp,
        UITextLayoutDirectionDown
    };

    typedef NS_ENUM(NSInteger, UITextWritingDirection) {
        UITextWritingDirectionNatural = -1,
        UITextWritingDirectionLeftToRight = 0,
        UITextWritingDirectionRightToLeft = 1
    };

    static inline CGRect KKTextEdgeInsetsInsetRect(CGRect rect, UIEdgeInsets insets) {
        return CGRectMake(rect.origin.x + insets.left,
                          rect.origin.y + insets.top,
                          rect.size.width - insets.left - insets.right,
                          rect.size.height - insets.top - insets.bottom);
    }

    static inline BOOL UIEdgeInsetsEqualToEdgeInsets(UIEdgeInsets insets1, UIEdgeInsets insets2) {
        return insets1.top == insets2.top &&
               insets1.left == insets2.left &&
               insets1.bottom == insets2.bottom &&
               insets1.right == insets2.right;
    }

    #undef UIEdgeInsetsInsetRect
    #define UIEdgeInsetsInsetRect KKTextEdgeInsetsInsetRect

    #import "NSView+KKText.h"
    #import "NSValue+KKText.h"
    #import "NSBezierPath+KKText.h"
    #import "NSImage+KKText.h"

    static inline NSTextAlignment NSTextAlignmentFromCTTextAlignment(CTTextAlignment alignment) {
        switch (alignment) {
            case kCTTextAlignmentLeft: return NSTextAlignmentLeft;
            case kCTTextAlignmentRight: return NSTextAlignmentRight;
            case kCTTextAlignmentCenter: return NSTextAlignmentCenter;
            case kCTTextAlignmentJustified: return NSTextAlignmentJustified;
            case kCTTextAlignmentNatural: return NSTextAlignmentNatural;
        }
        return NSTextAlignmentNatural;
    }

    static inline CTTextAlignment NSTextAlignmentToCTTextAlignment(NSTextAlignment alignment) {
        switch (alignment) {
            case NSTextAlignmentLeft: return kCTTextAlignmentLeft;
            case NSTextAlignmentRight: return kCTTextAlignmentRight;
            case NSTextAlignmentCenter: return kCTTextAlignmentCenter;
            case NSTextAlignmentJustified: return kCTTextAlignmentJustified;
            case NSTextAlignmentNatural: return kCTTextAlignmentNatural;
        }
        return kCTTextAlignmentNatural;
    }

#else
    #define KKTEXT_MAC 0
    #define KKTEXT_UIKIT 1

    #import <UIKit/UIKit.h>
#endif

CGFloat KKTextPlatformScreenScale(void);
CGSize KKTextPlatformScreenSize(void);
double KKTextPlatformSystemVersion(void);
void KKTextPlatformPushContext(CGContextRef _Nonnull context);
void KKTextPlatformPopContext(void);
CGImageRef _Nullable KKTextCreateImage(CGSize size, BOOL opaque, CGFloat scale, CGColorRef _Nullable backgroundColor, void (^ _Nonnull drawBlock)(CGContextRef _Nonnull context)) CF_RETURNS_RETAINED;
