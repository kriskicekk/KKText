//
//  NSView+KKText.m
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/09.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "NSView+KKText.h"

#if KKTEXT_MAC

#import <objc/runtime.h>

static const void *KKTextViewContentModeKey = &KKTextViewContentModeKey;
static const void *KKTextViewBackgroundColorKey = &KKTextViewBackgroundColorKey;
static const void *KKTextViewOpaqueKey = &KKTextViewOpaqueKey;
static const void *KKTextViewUserInteractionEnabledKey = &KKTextViewUserInteractionEnabledKey;

@implementation NSView (KKTextCompatibility)

- (UIViewContentMode)contentMode {
    NSNumber *mode = objc_getAssociatedObject(self, KKTextViewContentModeKey);
    return mode ? (UIViewContentMode)mode.integerValue : UIViewContentModeScaleToFill;
}

- (void)setContentMode:(UIViewContentMode)contentMode {
    objc_setAssociatedObject(self, KKTextViewContentModeKey, @(contentMode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.needsDisplay = YES;
}

- (UIColor *)backgroundColor {
    return objc_getAssociatedObject(self, KKTextViewBackgroundColorKey);
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
    objc_setAssociatedObject(self, KKTextViewBackgroundColorKey, backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.wantsLayer = YES;
    self.layer.backgroundColor = backgroundColor.CGColor;
    self.needsDisplay = YES;
}

- (BOOL)opaque {
    NSNumber *opaque = objc_getAssociatedObject(self, KKTextViewOpaqueKey);
    return opaque.boolValue;
}

- (void)setOpaque:(BOOL)opaque {
    objc_setAssociatedObject(self, KKTextViewOpaqueKey, @(opaque), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.needsDisplay = YES;
}

- (BOOL)isUserInteractionEnabled {
    NSNumber *enabled = objc_getAssociatedObject(self, KKTextViewUserInteractionEnabledKey);
    return enabled ? enabled.boolValue : YES;
}

- (void)setUserInteractionEnabled:(BOOL)userInteractionEnabled {
    objc_setAssociatedObject(self, KKTextViewUserInteractionEnabledKey, @(userInteractionEnabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

#endif
