//
//  KKTextViewParagraphContainerView.h
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/15.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "KKTextView.h"

#if KKTEXT_MAC

NS_ASSUME_NONNULL_BEGIN

@class _KKTextViewParagraphContainerView;

// Layout context for a single paragraph.
// It binds the global text range, local paragraph text, hidden tail/probe, layout, and view.
@interface _KKTextViewParagraphContext : NSObject
/// The real text range for this paragraph in _innerText, excluding the trailing line break.
@property (nonatomic) NSRange range;
/// The line-break range after this paragraph; length can be 0, 1, or 2 for CRLF.
@property (nonatomic) NSRange lineBreakRange;
/// The container size used to build the layout, used to decide whether an old layout can be reused.
@property (nonatomic) CGSize layoutContainerSize;
/// Real visible text in the paragraph, excluding line-break tail/probe/sentinel text.
@property (nonatomic, strong) NSMutableAttributedString *text;
/// Hidden trailing text used only for layout measurement, such as line break + probe or end sentinel.
@property (nonatomic, strong) NSMutableAttributedString *layoutTailText;
/// This paragraph's own layout; local refresh rebuilds only changed paragraphs.
@property (nullable, nonatomic, strong) KKTextLayout *layout;
/// The AppKit view for this paragraph.
@property (nullable, nonatomic, strong) _KKTextViewParagraphContainerView *contentView;
@end

// Text content container view for a single paragraph.
// It owns no editing state and only forwards drawing and mouse events to the outer KKTextView.
@interface _KKTextViewParagraphContainerView : NSView
@property (nullable, nonatomic, weak) KKTextView *textView;
@property (nullable, nonatomic, weak) _KKTextViewParagraphContext *paragraphContext;
@end

@interface KKTextView (KKTextViewParagraphContainerView)
- (void)_drawParagraphContainerView:(_KKTextViewParagraphContainerView *)paragraphView inRect:(NSRect)dirtyRect;
@end

NS_ASSUME_NONNULL_END

#endif
