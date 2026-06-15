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

@interface _KKTextViewParagraphContext : NSObject
@property (nonatomic) NSRange range;
@property (nonatomic) CGSize layoutContainerSize;
@property (nonatomic, strong) NSMutableAttributedString *text;
@property (nullable, nonatomic, strong) KKTextLayout *layout;
@property (nullable, nonatomic, strong) _KKTextViewParagraphContainerView *contentView;
@end

@interface _KKTextViewParagraphContainerView : NSView
@property (nullable, nonatomic, weak) KKTextView *textView;
@property (nullable, nonatomic, strong) _KKTextViewParagraphContext *paragraphContext;
@end

@interface KKTextView (KKTextViewParagraphContainerView)
- (void)_drawParagraphContainerView:(_KKTextViewParagraphContainerView *)paragraphView inRect:(NSRect)dirtyRect;
@end

NS_ASSUME_NONNULL_END

#endif
