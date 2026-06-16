//
//  KKTextViewDocumentView.h
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/16.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "KKTextView.h"

#if KKTEXT_MAC

NS_ASSUME_NONNULL_BEGIN

// The NSScrollView document view that hosts paragraph containers and the selection view.
// The outer KKTextView keeps first-responder/editing state; this view only draws and forwards events.
@interface _KKTextViewDocumentView : NSView
@property (nullable, nonatomic, weak) KKTextView *textView;
@end

@interface KKTextView (KKTextViewDocumentView)
- (void)_drawDocumentViewInRect:(NSRect)dirtyRect;
@end

NS_ASSUME_NONNULL_END

#endif
