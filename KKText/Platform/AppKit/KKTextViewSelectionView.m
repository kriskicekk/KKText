//
//  KKTextViewSelectionView.m
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/16.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "KKTextViewSelectionView.h"

#if KKTEXT_MAC

@implementation _KKTextViewSelectionView

- (BOOL)isFlipped {
    // Use a top-left origin so selectionView matches the documentView/KKTextLayout document coordinates.
    return YES;
}

- (BOOL)acceptsFirstResponder {
    // The outer KKTextView always owns first responder status.
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [self.textView _drawSelectionViewInRect:dirtyRect];
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
