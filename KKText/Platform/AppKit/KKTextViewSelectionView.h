//
//  KKTextViewSelectionView.h
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

// A dedicated selection layer that only draws selection and caret.
// Selection changes can avoid repainting paragraph text, closer to the iOS selection view model.
@interface _KKTextViewSelectionView : NSView
@property (nullable, nonatomic, weak) KKTextView *textView;
@end

@interface KKTextView (KKTextViewSelectionView)
- (void)_drawSelectionViewInRect:(NSRect)dirtyRect;
@end

NS_ASSUME_NONNULL_END

#endif
