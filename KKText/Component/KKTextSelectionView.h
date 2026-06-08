//
//  KKTextSelectionView.h
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

#if __has_include(<KKText/KKText.h>)
#import <KKText/KKTextAttribute.h>
#import <KKText/KKTextInput.h>
#else
#import "KKTextAttribute.h"
#import "KKTextInput.h"
#endif

NS_ASSUME_NONNULL_BEGIN

/**
 A single dot view. The frame should be foursquare.
 Change the background color for display.
 
 @discussion Typically, you should not use this class directly.
 */
@interface KKSelectionGrabberDot : UIView
/// Dont't access this property. It was used by `KKTextEffectWindow`.
@property (nonatomic, strong) UIView *mirror;
@end


/**
 A grabber (stick with a dot).
 
 @discussion Typically, you should not use this class directly.
 */
@interface KKSelectionGrabber : UIView

@property (nonatomic, readonly) KKSelectionGrabberDot *dot; ///< the dot view
@property (nonatomic) KKTextDirection dotDirection;         ///< don't support composite direction
@property (nullable, nonatomic, strong) UIColor *color;     ///< tint color, default is nil

@end


/**
 The selection view for text edit and select.
 
 @discussion Typically, you should not use this class directly.
 */
@interface KKTextSelectionView : UIView

@property (nullable, nonatomic, weak) UIView *hostView; ///< the holder view
@property (nullable, nonatomic, strong) UIColor *color; ///< the tint color
@property (nonatomic, getter = isCaretBlinks) BOOL caretBlinks; ///< whether the caret is blinks
@property (nonatomic, getter = isCaretVisible) BOOL caretVisible; ///< whether the caret is visible
@property (nonatomic, getter = isVerticalForm) BOOL verticalForm; ///< weather the text view is vertical form

@property (nonatomic) CGRect caretRect; ///< caret rect (width==0 or height==0)
@property (nullable, nonatomic, copy) NSArray<KKTextSelectionRect *> *selectionRects; ///< default is nil

@property (nonatomic, readonly) UIView *caretView;
@property (nonatomic, readonly) KKSelectionGrabber *startGrabber;
@property (nonatomic, readonly) KKSelectionGrabber *endGrabber;

- (BOOL)isGrabberContainsPoint:(CGPoint)point;
- (BOOL)isStartGrabberContainsPoint:(CGPoint)point;
- (BOOL)isEndGrabberContainsPoint:(CGPoint)point;
- (BOOL)isCaretContainsPoint:(CGPoint)point;
- (BOOL)isSelectionRectsContainsPoint:(CGPoint)point;

@end

NS_ASSUME_NONNULL_END
