//
//  KKTextViewParagraphContainerView.m
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/15.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "KKTextViewParagraphContainerView.h"

#if KKTEXT_MAC

@implementation _KKTextViewParagraphContext
@end

@implementation _KKTextViewParagraphContainerView

- (BOOL)isFlipped {
    // Use a top-left origin to match the KKTextView/documentView text coordinates.
    return YES;
}

- (BOOL)acceptsFirstResponder {
    // The outer KKTextView owns first responder status; paragraph views only host content.
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [self.textView _drawParagraphContainerView:self inRect:dirtyRect];
}

- (void)mouseDown:(NSEvent *)event {
    [self.textView mouseDown:event];
}

- (void)mouseDragged:(NSEvent *)event {
    [self.textView mouseDragged:event];
}

- (void)mouseUp:(NSEvent *)event {
    [self.textView mouseUp:event];
}

- (void)rightMouseDown:(NSEvent *)event {
    [self.textView rightMouseDown:event];
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    return [self.textView menuForEvent:event];
}

@end

#endif
