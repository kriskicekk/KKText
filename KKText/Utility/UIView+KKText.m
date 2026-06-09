//
//  UIView+KKText.m
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/08.
//  Originally created by ibireme.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "UIView+KKText.h"

// Dummy class for category
@interface UIView_KKText : NSObject @end
@implementation UIView_KKText @end


@implementation UIView (KKText)

- (UIViewController *)kk_viewController {
    for (UIView *view = self; view; view = view.superview) {
        UIResponder *nextResponder = [view nextResponder];
        if ([nextResponder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)nextResponder;
        }
    }
    return nil;
}

#if KKTEXT_UIKIT

- (CGFloat)kk_visibleAlpha {
    if ([self isKindOfClass:[UIWindow class]]) {
        if (self.hidden) return 0;
        return self.alpha;
    }
    if (!self.window) return 0;
    CGFloat alpha = 1;
    UIView *v = self;
    while (v) {
        if (v.hidden) {
            alpha = 0;
            break;
        }
        alpha *= v.alpha;
        v = v.superview;
    }
    return alpha;
}

- (CGPoint)kk_convertPoint:(CGPoint)point toViewOrWindow:(UIView *)view {
    if (!view) {
        if ([self isKindOfClass:[UIWindow class]]) {
            return [((UIWindow *)self) convertPoint:point toWindow:nil];
        } else {
            return [self convertPoint:point toView:nil];
        }
    }
    
    UIWindow *from = [self isKindOfClass:[UIWindow class]] ? (id)self : self.window;
    UIWindow *to = [view isKindOfClass:[UIWindow class]] ? (id)view : view.window;
    if ((!from || !to) || (from == to)) return [self convertPoint:point toView:view];
    point = [self convertPoint:point toView:from];
    point = [to convertPoint:point fromWindow:from];
    point = [view convertPoint:point fromView:to];
    return point;
}

- (CGPoint)kk_convertPoint:(CGPoint)point fromViewOrWindow:(UIView *)view {
    if (!view) {
        if ([self isKindOfClass:[UIWindow class]]) {
            return [((UIWindow *)self) convertPoint:point fromWindow:nil];
        } else {
            return [self convertPoint:point fromView:nil];
        }
    }
    
    UIWindow *from = [view isKindOfClass:[UIWindow class]] ? (id)view : view.window;
    UIWindow *to = [self isKindOfClass:[UIWindow class]] ? (id)self : self.window;
    if ((!from || !to) || (from == to)) return [self convertPoint:point fromView:view];
    point = [from convertPoint:point fromView:view];
    point = [to convertPoint:point fromWindow:from];
    point = [self convertPoint:point fromView:to];
    return point;
}

- (CGRect)kk_convertRect:(CGRect)rect toViewOrWindow:(UIView *)view {
    if (!view) {
        if ([self isKindOfClass:[UIWindow class]]) {
            return [((UIWindow *)self) convertRect:rect toWindow:nil];
        } else {
            return [self convertRect:rect toView:nil];
        }
    }
    
    UIWindow *from = [self isKindOfClass:[UIWindow class]] ? (id)self : self.window;
    UIWindow *to = [view isKindOfClass:[UIWindow class]] ? (id)view : view.window;
    if (!from || !to) return [self convertRect:rect toView:view];
    if (from == to) return [self convertRect:rect toView:view];
    rect = [self convertRect:rect toView:from];
    rect = [to convertRect:rect fromWindow:from];
    rect = [view convertRect:rect fromView:to];
    return rect;
}

- (CGRect)kk_convertRect:(CGRect)rect fromViewOrWindow:(UIView *)view {
    if (!view) {
        if ([self isKindOfClass:[UIWindow class]]) {
            return [((UIWindow *)self) convertRect:rect fromWindow:nil];
        } else {
            return [self convertRect:rect fromView:nil];
        }
    }
    
    UIWindow *from = [view isKindOfClass:[UIWindow class]] ? (id)view : view.window;
    UIWindow *to = [self isKindOfClass:[UIWindow class]] ? (id)self : self.window;
    if ((!from || !to) || (from == to)) return [self convertRect:rect fromView:view];
    rect = [from convertRect:rect fromView:view];
    rect = [to convertRect:rect fromWindow:from];
    rect = [self convertRect:rect fromView:to];
    return rect;
}

#else

- (CGFloat)kk_visibleAlpha {
    if (!self.window || self.hidden) return 0;
    CGFloat alpha = 1;
    for (UIView *view = self; view; view = view.superview) {
        if (view.hidden) return 0;
        alpha *= view.alphaValue;
    }
    return alpha;
}

- (CGPoint)kk_convertPoint:(CGPoint)point toViewOrWindow:(UIView *)view {
    if (!view) return [self convertPoint:point toView:nil];
    NSWindow *fromWindow = self.window;
    NSWindow *toWindow = [view isKindOfClass:[NSWindow class]] ? (id)view : view.window;
    if (!fromWindow || !toWindow || fromWindow == toWindow) {
        return [self convertPoint:point toView:view];
    }
    point = [self convertPoint:point toView:nil];
    point = [fromWindow convertPointToScreen:point];
    point = [toWindow convertPointFromScreen:point];
    if ([view isKindOfClass:[NSWindow class]]) return point;
    return [view convertPoint:point fromView:nil];
}

- (CGPoint)kk_convertPoint:(CGPoint)point fromViewOrWindow:(UIView *)view {
    if (!view) return [self convertPoint:point fromView:nil];
    NSWindow *fromWindow = [view isKindOfClass:[NSWindow class]] ? (id)view : view.window;
    NSWindow *toWindow = self.window;
    if (!fromWindow || !toWindow || fromWindow == toWindow) {
        return [self convertPoint:point fromView:view];
    }
    if (![view isKindOfClass:[NSWindow class]]) {
        point = [view convertPoint:point toView:nil];
    }
    point = [fromWindow convertPointToScreen:point];
    point = [toWindow convertPointFromScreen:point];
    return [self convertPoint:point fromView:nil];
}

- (CGRect)kk_convertRect:(CGRect)rect toViewOrWindow:(UIView *)view {
    if (!view) return [self convertRect:rect toView:nil];
    NSWindow *fromWindow = self.window;
    NSWindow *toWindow = [view isKindOfClass:[NSWindow class]] ? (id)view : view.window;
    if (!fromWindow || !toWindow || fromWindow == toWindow) {
        return [self convertRect:rect toView:view];
    }
    rect = [self convertRect:rect toView:nil];
    rect = [fromWindow convertRectToScreen:rect];
    rect = [toWindow convertRectFromScreen:rect];
    if ([view isKindOfClass:[NSWindow class]]) return rect;
    return [view convertRect:rect fromView:nil];
}

- (CGRect)kk_convertRect:(CGRect)rect fromViewOrWindow:(UIView *)view {
    if (!view) return [self convertRect:rect fromView:nil];
    NSWindow *fromWindow = [view isKindOfClass:[NSWindow class]] ? (id)view : view.window;
    NSWindow *toWindow = self.window;
    if (!fromWindow || !toWindow || fromWindow == toWindow) {
        return [self convertRect:rect fromView:view];
    }
    if (![view isKindOfClass:[NSWindow class]]) {
        rect = [view convertRect:rect toView:nil];
    }
    rect = [fromWindow convertRectToScreen:rect];
    rect = [toWindow convertRectFromScreen:rect];
    return [self convertRect:rect fromView:nil];
}

#endif

@end
