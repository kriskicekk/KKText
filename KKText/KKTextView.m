//
//  KKTextView.m
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/08.
//  Originally created by ibireme.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "KKTextView.h"
#import "KKTextInput.h"
#import "KKTextContainerView.h"
#import "KKTextSelectionView.h"
#import "KKTextMagnifier.h"
#import "KKTextEffectWindow.h"
#import "KKTextKeyboardManager.h"
#import "KKTextUtilities.h"
#import "KKTextTransaction.h"
#import "KKTextWeakProxy.h"
#import "NSAttributedString+KKText.h"
#import "UIPasteboard+KKText.h"
#import "UIView+KKText.h"


static double _KKDeviceSystemVersion(void) {
    static double version;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        version = KKTextPlatformSystemVersion();
    });
    return version;
}

#ifndef kSystemVersion
#define kSystemVersion _KKDeviceSystemVersion()
#endif

#ifndef kiOS6Later
#define kiOS6Later (kSystemVersion >= 6)
#endif

#ifndef kiOS7Later
#define kiOS7Later (kSystemVersion >= 7)
#endif

#ifndef kiOS8Later
#define kiOS8Later (kSystemVersion >= 8)
#endif

#ifndef kiOS9Later
#define kiOS9Later (kSystemVersion >= 9)
#endif



#define kDefaultUndoLevelMax 20 // Default maximum undo level

#define kAutoScrollMinimumDuration 0.1 // Time in seconds to tick auto-scroll.
#define kLongPressMinimumDuration 0.5 // Time in seconds the fingers must be held down for long press gesture.
#define kLongPressAllowableMovement 10.0 // Maximum movement in points allowed before the long press fails.

#define kMagnifierRangedTrackFix -6.0 // Magnifier ranged offset fix.
#define kMagnifierRangedPopoverOffset 4.0 // Magnifier ranged popover offset.
#define kMagnifierRangedCaptureOffset -6.0 // Magnifier ranged capture center offset.

#define kHighlightFadeDuration 0.15 // Time in seconds for highlight fadeout animation.

#define kDefaultInset UIEdgeInsetsMake(6, 4, 6, 4)
#define kDefaultVerticalInset UIEdgeInsetsMake(4, 6, 4, 6)

static NSRange KKTextViewMakeSafeRange(NSRange range, NSUInteger length) {
    if (range.location == NSNotFound) return NSMakeRange(length, 0);
    if (range.location > length) range.location = length;
    if (range.length > length - range.location) range.length = length - range.location;
    return range;
}


NSString *const KKTextViewTextDidBeginEditingNotification = @"KKTextViewTextDidBeginEditing";
NSString *const KKTextViewTextDidChangeNotification = @"KKTextViewTextDidChange";
NSString *const KKTextViewTextDidEndEditingNotification = @"KKTextViewTextDidEndEditing";


typedef NS_ENUM (NSUInteger, KKTextGrabberDirection) {
    kStart = 1,
    kEnd   = 2,
};

typedef NS_ENUM(NSUInteger, KKTextMoveDirection) {
    kLeft   = 1,
    kTop    = 2,
    kRight  = 3,
    kBottom = 4,
};


/// An object that captures the state of the text view. Used for undo and redo.
@interface _KKTextViewUndoObject : NSObject
@property (nonatomic, strong) NSAttributedString *text;
@property (nonatomic, assign) NSRange selectedRange;
@end
@implementation _KKTextViewUndoObject
+ (instancetype)objectWithText:(NSAttributedString *)text range:(NSRange)range {
    _KKTextViewUndoObject *obj = [self new];
    obj.text = text ? text : [NSAttributedString new];
    obj.selectedRange = range;
    return obj;
}
@end

@class _KKTextViewParagraphContext;

typedef NS_ENUM(NSUInteger, _KKTextViewSelectionRectMode) {
    _KKTextViewSelectionRectModeAll,
    _KKTextViewSelectionRectModeWithoutStartAndEnd,
    _KKTextViewSelectionRectModeOnlyStartAndEnd,
};

@interface _KKTextViewParagraphContext : NSObject
@property (nonatomic) NSRange range;
@property (nonatomic) NSRange lineBreakRange;
@property (nonatomic) CGSize layoutContainerSize;
@property (nonatomic, strong) NSMutableAttributedString *text;
@property (nonatomic, strong) NSMutableAttributedString *layoutTailText;
@property (nullable, nonatomic, strong) KKTextLayout *layout;
@property (nullable, nonatomic, strong) KKTextContainerView *contentView;
@end

@implementation _KKTextViewParagraphContext
@end


@interface KKTextView () <UIScrollViewDelegate, UIAlertViewDelegate, KKTextDebugTarget, KKTextKeyboardObserver> {
    
    KKTextRange *_selectedTextRange; /// nonnull
    KKTextRange *_markedTextRange;
    
    __weak id<KKTextViewDelegate> _outerDelegate;
    
    UIImageView *_placeHolderView;
    
    NSMutableAttributedString *_innerText; ///< nonnull, inner attributed text
    NSMutableAttributedString *_delectedText; ///< detected text for display
    KKTextContainer *_innerContainer; ///< nonnull, inner text container
    NSMutableArray<_KKTextViewParagraphContext *> *_paragraphContexts; ///< paragraph text layouts
    
    KKTextContainerView *_containerView; ///< nonnull
    KKTextSelectionView *_selectionView; ///< nonnull
    KKTextMagnifier *_magnifierCaret; ///< nonnull
    KKTextMagnifier *_magnifierRanged; ///< nonnull
    
    NSMutableAttributedString *_typingAttributesHolder; ///< nonnull, typing attributes
    NSDataDetector *_dataDetector;
    CGFloat _magnifierRangedOffset;
    
    NSRange _highlightRange; ///< current highlight range
    KKTextHighlight *_highlight; ///< highlight attribute in `_highlightRange`
    KKTextRange *_trackingRange; ///< the tracking range, may out of _innerText.
    
    BOOL _insetModifiedByKeyboard; ///< text is covered by keyboard, and the contentInset is modified
    UIEdgeInsets _originalContentInset; ///< the original contentInset before modified
    UIEdgeInsets _originalScrollIndicatorInsets; ///< the original scrollIndicatorInsets before modified
    
    NSTimer *_longPressTimer;
    NSTimer *_autoScrollTimer;
    CGFloat _autoScrollOffset; ///< current auto scroll offset which shoud add to scroll view
    NSInteger _autoScrollAcceleration; ///< an acceleration coefficient for auto scroll
    NSTimer *_selectionDotFixTimer; ///< fix the selection dot in window if the view is moved by parents
    CGPoint _previousOriginInWindow;
    
    CGPoint _touchBeganPoint;
    CGPoint _trackingPoint;
    NSTimeInterval _touchBeganTime;
    NSTimeInterval _trackingTime;
    
    NSMutableArray *_undoStack;
    NSMutableArray *_redoStack;
    NSRange _lastTypeRange;
    NSRange _pendingParagraphEditNewRange;
    NSInteger _pendingParagraphEditDelta;
    BOOL _hasPendingParagraphEdit;
    
    struct {
        unsigned int trackingGrabber : 2;       ///< KKTextGrabberDirection, current tracking grabber
        unsigned int trackingCaret : 1;         ///< track the caret
        unsigned int trackingPreSelect : 1;     ///< track pre-select
        unsigned int trackingTouch : 1;         ///< is in touch phase
        unsigned int swallowTouch : 1;          ///< don't forward event to next responder
        unsigned int touchMoved : 3;            ///< KKTextMoveDirection, move direction after touch began
        unsigned int selectedWithoutEdit : 1;   ///< show selected range but not first responder
        unsigned int deleteConfirm : 1;         ///< delete a binding text range
        unsigned int ignoreFirstResponder : 1;  ///< ignore become first responder temporary
        unsigned int ignoreTouchBegan : 1;      ///< ignore begin tracking touch temporary
        
        unsigned int showingMagnifierCaret : 1;
        unsigned int showingMagnifierRanged : 1;
        unsigned int showingMenu : 1;
        unsigned int showingHighlight : 1;
        
        unsigned int typingAttributesOnce : 1;  ///< apply the typing attributes once
        unsigned int clearsOnInsertionOnce : 1; ///< select all once when become first responder
        unsigned int autoScrollTicked : 1;      ///< auto scroll did tick scroll at this timer period
        unsigned int firstShowDot : 1;          ///< the selection grabber dot has displayed at least once
        unsigned int needUpdate : 1;            ///< the layout or selection view is 'dirty' and need update
        unsigned int placeholderNeedUpdate : 1; ///< the placeholder need update it's contents
        
        unsigned int insideUndoBlock : 1;
        unsigned int firstResponderBeforeUndoAlert : 1;
    } _state;
}

@end


@implementation KKTextView

#pragma mark - @protocol UITextInputTraits
@synthesize autocapitalizationType = _autocapitalizationType;
@synthesize autocorrectionType = _autocorrectionType;
@synthesize spellCheckingType = _spellCheckingType;
@synthesize keyboardType = _keyboardType;
@synthesize keyboardAppearance = _keyboardAppearance;
@synthesize returnKeyType = _returnKeyType;
@synthesize enablesReturnKeyAutomatically = _enablesReturnKeyAutomatically;
@synthesize secureTextEntry = _secureTextEntry;

#pragma mark - @protocol UITextInput
@synthesize selectedTextRange = _selectedTextRange;  //copy nonnull (KKTextRange*)
@synthesize markedTextRange = _markedTextRange;      //readonly     (KKTextRange*)
@synthesize markedTextStyle = _markedTextStyle;      //copy
@synthesize inputDelegate = _inputDelegate;         //assign
@synthesize tokenizer = _tokenizer;                 //readonly

#pragma mark - @protocol UITextInput optional
@synthesize selectionAffinity = _selectionAffinity;


#pragma mark - Private

/// Update layout and selection before runloop sleep/end.
- (void)_commitUpdate {
#if !TARGET_INTERFACE_BUILDER
    _state.needUpdate = YES;
    [[KKTextTransaction transactionWithTarget:self selector:@selector(_updateIfNeeded)] commit];
#else
    [self _update];
#endif
}

/// Update layout and selection view if needed.
- (void)_updateIfNeeded {
    if (_state.needUpdate) {
        [self _update];
    }
}

/// Update layout and selection view immediately.
- (void)_update {
    _state.needUpdate = NO;
    [self _updateLayout];
    [self _updateSelectionView];
}

/// Update layout immediately.
- (void)_updateLayout {
    NSMutableAttributedString *text = _innerText.mutableCopy;
    _placeHolderView.hidden = text.length > 0;
    if ([self _detectText:text]) {
        _delectedText = text;
    } else {
        _delectedText = nil;
    }
    _state.showingHighlight = NO;
    [self willChangeValueForKey:@"textLayout"];
    [_containerView setLayout:nil withFadeDuration:0];
    [self _updateParagraphContainerViewsReusingLayouts:YES];
    [self didChangeValueForKey:@"textLayout"];
}

/// Update selection view immediately.
/// This method should be called after "layout update" finished.
- (void)_updateSelectionView {
    _selectionView.frame = _containerView.frame;
    _selectionView.caretBlinks = NO;
    _selectionView.caretVisible = NO;
    _selectionView.selectionRects = nil;
    [[KKTextEffectWindow sharedWindow] hideSelectionDot:_selectionView];
    if (_paragraphContexts.count == 0) return;
    
    NSMutableArray *allRects = [NSMutableArray new];
    BOOL containsDot = NO;
    
    KKTextRange *selectedRange = _selectedTextRange;
    if (_state.trackingTouch && _trackingRange) {
        selectedRange = _trackingRange;
    }
    
    if (_markedTextRange) {
        NSArray *rects = [self _selectionRectsWithoutStartAndEndForTextRange:_markedTextRange];
        if (rects) [allRects addObjectsFromArray:rects];
        if (selectedRange.asRange.length > 0) {
            rects = [self _selectionRectsWithOnlyStartAndEndForTextRange:selectedRange];
            if (rects) [allRects addObjectsFromArray:rects];
            containsDot = rects.count > 0;
        } else {
            CGRect rect = [self _caretRectForTextPosition:selectedRange.end];
            _selectionView.caretRect = rect;
            _selectionView.caretVisible = YES;
            _selectionView.caretBlinks = YES;
        }
    } else {
        if (selectedRange.asRange.length == 0) { // only caret
            if (self.isFirstResponder || _state.trackingPreSelect) {
                CGRect rect = [self _caretRectForTextPosition:selectedRange.end];
                _selectionView.caretRect = rect;
                _selectionView.caretVisible = YES;
                if (!_state.trackingCaret && !_state.trackingPreSelect) {
                    _selectionView.caretBlinks = YES;
                }
            }
        } else { // range selected
            if ((self.isFirstResponder && !_state.deleteConfirm) ||
                (!self.isFirstResponder && _state.selectedWithoutEdit)) {
                NSArray *rects = [self _selectionRectsForTextRange:selectedRange];
                if (rects) [allRects addObjectsFromArray:rects];
                containsDot = rects.count > 0;
            } else if ((!self.isFirstResponder && _state.trackingPreSelect) ||
                       (self.isFirstResponder && _state.deleteConfirm)){
                NSArray *rects = [self _selectionRectsWithoutStartAndEndForTextRange:selectedRange];
                if (rects) [allRects addObjectsFromArray:rects];
            }
        }
    }
    _selectionView.selectionRects = allRects;
    if (!_state.firstShowDot && containsDot) {
        _state.firstShowDot = YES;
        /*
         The dot position may be wrong at the first time displayed.
         I can't find the reason. Here's a workaround.
         */
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[KKTextEffectWindow sharedWindow] showSelectionDot:_selectionView];
        });
    }
    [[KKTextEffectWindow sharedWindow] showSelectionDot:_selectionView];
    
    if (containsDot) {
        [self _startSelectionDotFixTimer];
    } else {
        [self _endSelectionDotFixTimer];
    }
}

/// Update inner contains's size.
- (void)_updateInnerContainerSize {
    CGSize size = [self _getVisibleSize];
    if (_innerContainer.isVerticalForm) size.width = CGFLOAT_MAX;
    else size.height = CGFLOAT_MAX;
    _innerContainer.size = size;
}

- (NSAttributedString *)_paragraphDisplayText {
    NSMutableAttributedString *text = (_delectedText ? _delectedText : _innerText).mutableCopy;
    if (_state.showingHighlight && _highlight && _highlightRange.location != NSNotFound) {
        NSRange range = KKTextViewMakeSafeRange(_highlightRange, text.length);
        if (range.length > 0) {
            [_highlight.attributes enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
                [text kk_setAttribute:key value:value range:range];
            }];
        }
    }
    return text;
}

- (NSArray<NSValue *> *)_paragraphContentRanges {
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSString *string = _innerText.string;
    NSUInteger length = string.length;
    if (_verticalForm || _exclusionPaths.count > 0) {
        [ranges addObject:[NSValue valueWithRange:NSMakeRange(0, length)]];
        return ranges;
    }

    NSUInteger location = 0;
    while (location < length) {
        NSUInteger start = location;
        while (location < length && !KKTextIsLinebreakChar([string characterAtIndex:location])) {
            location++;
        }
        [ranges addObject:[NSValue valueWithRange:NSMakeRange(start, location - start)]];
        if (location < length) {
            unichar c = [string characterAtIndex:location];
            location++;
            if (c == '\r' && location < length && [string characterAtIndex:location] == '\n') {
                location++;
            }
        }
    }
    if (length == 0 || KKTextLinebreakTailLength(string) > 0) {
        [ranges addObject:[NSValue valueWithRange:NSMakeRange(length, 0)]];
    }
    return ranges;
}

- (CGSize)_paragraphLayoutContainerSize {
    CGSize size = [self _getVisibleSize];
    if (_verticalForm) size.width = CGFLOAT_MAX;
    else size.height = CGFLOAT_MAX;
    return size;
}

- (KKTextContainer *)_paragraphContainerWithSize:(CGSize)size {
    KKTextContainer *container = _innerContainer.copy;
    container.size = size;
    if (!_verticalForm && _exclusionPaths.count == 0) {
        container.insets = UIEdgeInsetsMake(0, _textContainerInset.left, 0, _textContainerInset.right);
        container.exclusionPaths = nil;
    }
    container.verticalForm = _verticalForm;
    container.linePositionModifier = _linePositionModifier;
    return container;
}

- (void)_applyHiddenLayoutAttributesToText:(NSMutableAttributedString *)text {
    if (text.length == 0) return;
    NSRange range = NSMakeRange(0, text.length);
    [text kk_removeDiscontinuousAttributesInRange:range];
    [text removeAttribute:KKTextBorderAttributeName range:range];
    [text removeAttribute:KKTextBackgroundBorderAttributeName range:range];
    UIColor *clearColor = UIColor.clearColor;
    [text kk_setAttribute:NSForegroundColorAttributeName value:clearColor range:range];
    [text kk_setAttribute:(id)kCTForegroundColorAttributeName value:(id)clearColor.CGColor range:range];
}

- (NSMutableAttributedString *)_hiddenLayoutTextWithAttributedString:(NSAttributedString *)text {
    NSMutableAttributedString *hiddenText = text.mutableCopy ?: [NSMutableAttributedString new];
    [self _applyHiddenLayoutAttributesToText:hiddenText];
    return hiddenText;
}

- (_KKTextViewParagraphContext *)_paragraphContextWithRange:(NSRange)range displayText:(NSAttributedString *)displayText {
    _KKTextViewParagraphContext *context = [_KKTextViewParagraphContext new];
    context.range = KKTextViewMakeSafeRange(range, _innerText.length);
    if (context.range.length > 0) {
        context.text = [[displayText attributedSubstringFromRange:context.range] mutableCopy];
    } else {
        context.text = [NSMutableAttributedString new];
    }

    NSUInteger lineBreakLocation = NSMaxRange(context.range);
    NSUInteger lineBreakLength = 0;
    if (!_verticalForm && _exclusionPaths.count == 0 && lineBreakLocation < _innerText.length) {
        unichar c = [_innerText.string characterAtIndex:lineBreakLocation];
        if (KKTextIsLinebreakChar(c)) {
            lineBreakLength = 1;
            if (c == '\r' &&
                lineBreakLocation + 1 < _innerText.length &&
                [_innerText.string characterAtIndex:lineBreakLocation + 1] == '\n') {
                lineBreakLength = 2;
            }
        }
    }
    context.lineBreakRange = NSMakeRange(lineBreakLocation, lineBreakLength);
    context.layoutTailText = [NSMutableAttributedString new];
    return context;
}

- (NSDictionary *)_paragraphDefaultTypingAttributes {
    NSMutableDictionary *attributes = [_typingAttributesHolder.kk_attributes mutableCopy];
    if (!attributes) attributes = [NSMutableDictionary dictionary];
    if (!attributes[NSFontAttributeName] && !attributes[(id)kCTFontAttributeName]) {
        UIFont *font = _font ?: [self _defaultFont];
        attributes[NSFontAttributeName] = font;
        attributes[(id)kCTFontAttributeName] = font;
    }
    if (!attributes[NSForegroundColorAttributeName] && !attributes[(id)kCTForegroundColorAttributeName]) {
        UIColor *color = _textColor ?: UIColor.blackColor;
        attributes[NSForegroundColorAttributeName] = color;
        attributes[(id)kCTForegroundColorAttributeName] = (id)color.CGColor;
    }
    return attributes;
}

- (NSDictionary *)_paragraphSentinelAttributesForContext:(_KKTextViewParagraphContext *)context {
    NSMutableDictionary *attributes = nil;
    if (context.text.length > 0) {
        attributes = [[context.text kk_attributesAtIndex:context.text.length - 1] mutableCopy];
    } else {
        attributes = [_typingAttributesHolder.kk_attributes mutableCopy];
    }
    if (!attributes) attributes = [[self _paragraphDefaultTypingAttributes] mutableCopy];
    [attributes removeObjectsForKeys:[NSMutableAttributedString kk_allDiscontinuousAttributeKeys]];
    [attributes removeObjectForKey:KKTextBorderAttributeName];
    [attributes removeObjectForKey:KKTextBackgroundBorderAttributeName];
    UIColor *clearColor = UIColor.clearColor;
    attributes[NSForegroundColorAttributeName] = clearColor;
    attributes[(id)kCTForegroundColorAttributeName] = (id)clearColor.CGColor;
    return attributes;
}

- (NSDictionary *)_paragraphProbeAttributesForContext:(_KKTextViewParagraphContext *)context displayText:(NSAttributedString *)displayText {
    NSMutableDictionary *attributes = nil;
    if (context.text.length > 0) {
        attributes = [[context.text kk_attributesAtIndex:0] mutableCopy];
    } else if (context.range.location < displayText.length) {
        attributes = [[displayText kk_attributesAtIndex:context.range.location] mutableCopy];
    } else {
        attributes = [_typingAttributesHolder.kk_attributes mutableCopy];
    }
    if (!attributes) attributes = [[self _paragraphDefaultTypingAttributes] mutableCopy];
    [attributes removeObjectsForKeys:[NSMutableAttributedString kk_allDiscontinuousAttributeKeys]];
    [attributes removeObjectForKey:KKTextBorderAttributeName];
    [attributes removeObjectForKey:KKTextBackgroundBorderAttributeName];
    UIColor *clearColor = UIColor.clearColor;
    attributes[NSForegroundColorAttributeName] = clearColor;
    attributes[(id)kCTForegroundColorAttributeName] = (id)clearColor.CGColor;
    return attributes;
}

- (NSMutableAttributedString *)_paragraphLayoutProbeTextForNextContext:(_KKTextViewParagraphContext *)nextContext displayText:(NSAttributedString *)displayText {
    if (!nextContext) return [NSMutableAttributedString new];
    NSDictionary *attributes = [self _paragraphProbeAttributesForContext:nextContext displayText:displayText];
    return [[NSMutableAttributedString alloc] initWithString:@"\u200B" attributes:attributes];
}

- (NSMutableAttributedString *)_paragraphLayoutTailTextForContext:(_KKTextViewParagraphContext *)context nextContext:(_KKTextViewParagraphContext *)nextContext displayText:(NSAttributedString *)displayText {
    NSMutableAttributedString *tailText = [NSMutableAttributedString new];
    if (context.lineBreakRange.length > 0) {
        NSAttributedString *lineBreakSource = [displayText attributedSubstringFromRange:context.lineBreakRange];
        [tailText appendAttributedString:[self _hiddenLayoutTextWithAttributedString:lineBreakSource]];
        [tailText appendAttributedString:[self _paragraphLayoutProbeTextForNextContext:nextContext displayText:displayText]];
    } else {
        NSDictionary *attributes = [self _paragraphSentinelAttributesForContext:context];
        NSAttributedString *sentinel = [[NSAttributedString alloc] initWithString:@"\r" attributes:attributes];
        [tailText appendAttributedString:sentinel];
    }
    return tailText;
}

- (NSMutableAttributedString *)_layoutTextForParagraphContext:(_KKTextViewParagraphContext *)context {
    NSMutableAttributedString *layoutText = context.text.mutableCopy ?: [NSMutableAttributedString new];
    [layoutText appendAttributedString:context.layoutTailText ?: [NSMutableAttributedString new]];
    return layoutText;
}

- (KKTextLayout *)_layoutForParagraphContext:(_KKTextViewParagraphContext *)context containerSize:(CGSize)containerSize {
    KKTextContainer *container = [self _paragraphContainerWithSize:containerSize];
    return [KKTextLayout layoutWithContainer:container text:[self _layoutTextForParagraphContext:context]];
}

- (void)_recordParagraphEditRange:(NSRange)range replacementLength:(NSUInteger)replacementLength {
    _pendingParagraphEditNewRange = NSMakeRange(range.location, replacementLength);
    _pendingParagraphEditDelta = (NSInteger)replacementLength - (NSInteger)range.length;
    _hasPendingParagraphEdit = YES;
}

- (void)_clearParagraphEditRecord {
    _pendingParagraphEditNewRange = NSMakeRange(0, 0);
    _pendingParagraphEditDelta = 0;
    _hasPendingParagraphEdit = NO;
}

- (NSUInteger)_oldParagraphLocationForCurrentRange:(NSRange)range {
    if (!_hasPendingParagraphEdit) return range.location;
    if (range.location >= NSMaxRange(_pendingParagraphEditNewRange)) {
        NSInteger oldLocation = (NSInteger)range.location - _pendingParagraphEditDelta;
        return oldLocation > 0 ? (NSUInteger)oldLocation : 0;
    }
    return range.location;
}

- (_KKTextViewParagraphContext *)_oldParagraphContextForCurrentContext:(_KKTextViewParagraphContext *)context oldContexts:(NSArray<_KKTextViewParagraphContext *> *)oldContexts index:(NSUInteger)index {
    if (_hasPendingParagraphEdit) {
        NSUInteger oldLocation = [self _oldParagraphLocationForCurrentRange:context.range];
        for (_KKTextViewParagraphContext *oldContext in oldContexts) {
            if (oldContext.range.location == oldLocation) return oldContext;
        }
    }
    return index < oldContexts.count ? oldContexts[index] : nil;
}

- (BOOL)_paragraphContext:(_KKTextViewParagraphContext *)context canReuseLayoutFromContext:(_KKTextViewParagraphContext *)oldContext containerSize:(CGSize)containerSize {
    if (!oldContext.layout) return NO;
    if (!CGSizeEqualToSize(oldContext.layoutContainerSize, containerSize)) return NO;
    if (![oldContext.text isEqualToAttributedString:context.text]) return NO;
    if (![oldContext.layoutTailText isEqualToAttributedString:context.layoutTailText]) return NO;
    return YES;
}

- (_KKTextViewParagraphContext *)_paragraphContextForLocation:(NSUInteger)location {
    if (_paragraphContexts.count == 0) return nil;
    location = MIN(location, _innerText.length);
    for (_KKTextViewParagraphContext *context in _paragraphContexts) {
        NSUInteger start = context.range.location;
        NSUInteger end = NSMaxRange(context.range);
        if (context.range.length == 0) {
            if (location == start) return context;
        } else if (start <= location && location <= end) {
            return context;
        }
    }
    return location <= _paragraphContexts.firstObject.range.location ? _paragraphContexts.firstObject : _paragraphContexts.lastObject;
}

- (_KKTextViewParagraphContext *)_paragraphContextForDocumentPoint:(CGPoint)point {
    if (_paragraphContexts.count == 0) return nil;
    for (_KKTextViewParagraphContext *context in _paragraphContexts) {
        if (CGRectContainsPoint(context.contentView.frame, point)) return context;
    }
    if (_verticalForm) {
        if (point.x <= CGRectGetMinX(_paragraphContexts.firstObject.contentView.frame)) return _paragraphContexts.firstObject;
    } else if (point.y <= CGRectGetMinY(_paragraphContexts.firstObject.contentView.frame)) {
        return _paragraphContexts.firstObject;
    }
    return _paragraphContexts.lastObject;
}

- (NSUInteger)_localLocationForGlobalLocation:(NSUInteger)location inParagraphContext:(_KKTextViewParagraphContext *)context {
    if (!context) return 0;
    if (location <= context.range.location) return 0;
    return MIN(location - context.range.location, context.text.length);
}

- (NSRange)_localRangeForGlobalRange:(NSRange)range inParagraphContext:(_KKTextViewParagraphContext *)context {
    if (!context) return NSMakeRange(NSNotFound, 0);
    range = KKTextViewMakeSafeRange(range, _innerText.length);
    NSUInteger paragraphStart = context.range.location;
    NSUInteger paragraphEnd = NSMaxRange(context.range);
    if (range.length == 0) {
        if (range.location < paragraphStart || range.location > paragraphEnd) return NSMakeRange(NSNotFound, 0);
        return NSMakeRange([self _localLocationForGlobalLocation:range.location inParagraphContext:context], 0);
    }

    NSUInteger start = MAX(range.location, paragraphStart);
    NSUInteger end = MIN(NSMaxRange(range), paragraphEnd);
    if (end <= start) return NSMakeRange(NSNotFound, 0);
    return NSMakeRange(start - paragraphStart, end - start);
}

- (NSRange)_globalRangeForLocalRange:(NSRange)localRange inParagraphContext:(_KKTextViewParagraphContext *)context {
    if (!context || localRange.location == NSNotFound) return NSMakeRange(NSNotFound, 0);
    localRange = KKTextViewMakeSafeRange(localRange, context.text.length);
    return NSMakeRange(context.range.location + localRange.location, localRange.length);
}

- (CGPoint)_localPointForDocumentPoint:(CGPoint)point inParagraphContext:(_KKTextViewParagraphContext *)context {
    CGRect frame = context.contentView.frame;
    return CGPointMake(point.x - frame.origin.x, point.y - frame.origin.y);
}

- (CGRect)_documentRectForLocalRect:(CGRect)rect inParagraphContext:(_KKTextViewParagraphContext *)context {
    if (CGRectIsNull(rect)) return rect;
    CGRect frame = context.contentView.frame;
    rect.origin.x += frame.origin.x;
    rect.origin.y += frame.origin.y;
    return rect;
}

- (BOOL)_paragraphContext:(_KKTextViewParagraphContext *)context canUseLineAtIndex:(NSUInteger)lineIndex {
    if (!context || lineIndex == NSNotFound || lineIndex >= context.layout.lines.count) return NO;
    KKTextLine *line = context.layout.lines[lineIndex];
    if (context.text.length == 0) return line.range.location == 0;
    return line.range.location < context.text.length;
}

- (NSUInteger)_lineIndexForParagraphContext:(_KKTextViewParagraphContext *)context localLocation:(NSUInteger)localLocation {
    if (!context.layout) return NSNotFound;
    localLocation = MIN(localLocation, context.text.length);
    KKTextPosition *position = [KKTextPosition positionWithOffset:localLocation];
    NSUInteger lineIndex = [context.layout lineIndexForPosition:position];
    if ([self _paragraphContext:context canUseLineAtIndex:lineIndex]) return lineIndex;
    if (localLocation > 0) {
        position = [KKTextPosition positionWithOffset:localLocation affinity:KKTextAffinityBackward];
        lineIndex = [context.layout lineIndexForPosition:position];
        if ([self _paragraphContext:context canUseLineAtIndex:lineIndex]) return lineIndex;
    }
    return NSNotFound;
}

- (NSUInteger)_lineIndexInParagraphContext:(_KKTextViewParagraphContext *)context fromLineIndex:(NSUInteger)lineIndex direction:(UITextLayoutDirection)direction {
    if (!context.layout || lineIndex == NSNotFound) return NSNotFound;
    NSInteger index = (NSInteger)lineIndex + (direction == UITextLayoutDirectionUp ? -1 : 1);
    NSInteger count = (NSInteger)context.layout.lines.count;
    while (0 <= index && index < count) {
        if ([self _paragraphContext:context canUseLineAtIndex:(NSUInteger)index]) return (NSUInteger)index;
        index += direction == UITextLayoutDirectionUp ? -1 : 1;
    }
    return NSNotFound;
}

- (NSUInteger)_edgeLineIndexForParagraphContext:(_KKTextViewParagraphContext *)context direction:(UITextLayoutDirection)direction {
    if (!context.layout || context.layout.lines.count == 0) return NSNotFound;
    NSInteger count = (NSInteger)context.layout.lines.count;
    NSInteger index = direction == UITextLayoutDirectionUp ? count - 1 : 0;
    while (0 <= index && index < count) {
        if ([self _paragraphContext:context canUseLineAtIndex:(NSUInteger)index]) return (NSUInteger)index;
        index += direction == UITextLayoutDirectionUp ? -1 : 1;
    }
    return NSNotFound;
}

- (NSUInteger)_textLocationInParagraphContext:(_KKTextViewParagraphContext *)context lineIndex:(NSUInteger)lineIndex targetX:(CGFloat)targetX {
    if (![self _paragraphContext:context canUseLineAtIndex:lineIndex]) return NSNotFound;
    KKTextLine *line = context.layout.lines[lineIndex];
    CGFloat localX = targetX - context.contentView.frame.origin.x;
    NSUInteger localLocation = [context.layout textPositionForPoint:CGPointMake(localX, line.position.y) lineIndex:lineIndex];
    if (localLocation == NSNotFound) {
        localX = MIN(MAX(localX, line.left), line.right);
        localLocation = [context.layout textPositionForPoint:CGPointMake(localX, line.position.y) lineIndex:lineIndex];
    }
    if (localLocation == NSNotFound) return NSNotFound;
    localLocation = MIN(localLocation, context.text.length);
    return MIN(context.range.location + localLocation, _innerText.length);
}

- (NSUInteger)_caretAttributeIndexForText:(NSAttributedString *)text location:(NSUInteger)location {
    if (text.length == 0) return NSNotFound;
    location = MIN(location, text.length);
    if (location == 0) return 0;
    if (location < text.length && KKTextIsLinebreakChar([text.string characterAtIndex:location - 1])) {
        return location;
    }
    return MIN(location - 1, text.length - 1);
}

- (void)_caretFontMetricsForFont:(id)font ascent:(CGFloat *)ascent descent:(CGFloat *)descent {
    if (!font) font = _font;

    CGFloat fontAscent = _font.ascender;
    CGFloat fontDescent = -_font.descender;
    if ([font isKindOfClass:UIFont.class]) {
        UIFont *uiFont = font;
        fontAscent = uiFont.ascender;
        fontDescent = -uiFont.descender;
    } else if (font && CFGetTypeID((__bridge CFTypeRef)font) == CTFontGetTypeID()) {
        CTFontRef ctFont = (__bridge CTFontRef)font;
        fontAscent = CTFontGetAscent(ctFont);
        fontDescent = CTFontGetDescent(ctFont);
    }
    if (ascent) *ascent = ceil(MAX(fontAscent, 0));
    if (descent) *descent = ceil(MAX(fontDescent, 0));
}

- (void)_caretFontMetricsForParagraphContext:(_KKTextViewParagraphContext *)context location:(NSUInteger)location ascent:(CGFloat *)ascent descent:(CGFloat *)descent {
    id font = nil;
    if (context.text.length > 0) {
        NSUInteger localLocation = location <= context.range.location ? 0 : MIN(location - context.range.location, context.text.length);
        NSUInteger index = [self _caretAttributeIndexForText:context.text location:localLocation];
        if (index != NSNotFound) {
            font = [context.text attribute:NSFontAttributeName atIndex:index effectiveRange:NULL];
            if (!font) font = [context.text attribute:(id)kCTFontAttributeName atIndex:index effectiveRange:NULL];
        }
    }
    if (!font) font = _typingAttributesHolder.kk_attributes[NSFontAttributeName];
    if (!font) font = _typingAttributesHolder.kk_attributes[(id)kCTFontAttributeName];
    [self _caretFontMetricsForFont:font ascent:ascent descent:descent];
}

- (CGRect)_caretRectByCenteringRect:(CGRect)rect withHeight:(CGFloat)height {
    if (CGRectIsNull(rect) || height <= 0) return rect;
    rect.origin.y = CGRectGetMidY(rect) - height * 0.5;
    rect.size.height = height;
    return rect;
}

- (CGRect)_localCaretRectForParagraphContext:(_KKTextViewParagraphContext *)context location:(NSUInteger)location {
    if (!context.layout) return CGRectNull;
    NSUInteger localLocation = location <= context.range.location ? 0 : MIN(location - context.range.location, context.text.length);
    CGFloat caretAscent = 0;
    CGFloat caretDescent = 0;
    [self _caretFontMetricsForParagraphContext:context location:location ascent:&caretAscent descent:&caretDescent];
    CGFloat caretHeight = caretAscent + caretDescent;
    KKTextPosition *position = [KKTextPosition positionWithOffset:localLocation];
    CGRect rect = [context.layout caretRectForPosition:position];
    if (CGRectIsNull(rect)) {
        rect = CGRectMake(_textContainerInset.left, 0, 0, caretHeight);
    } else if (!_verticalForm && caretHeight > 0) {
        rect = [self _caretRectByCenteringRect:rect withHeight:caretHeight];
    }
    if (_verticalForm) {
        rect.size.height = MAX(rect.size.height, 2);
    } else {
        rect.size.width = MAX(rect.size.width, 2);
    }
    return rect;
}

- (CGFloat)_minimumParagraphHeightForContext:(_KKTextViewParagraphContext *)context {
    CGFloat ascent = 0;
    CGFloat descent = 0;
    [self _caretFontMetricsForParagraphContext:context location:context.range.location ascent:&ascent descent:&descent];
    return MAX(ceil(ascent + descent), 1);
}

- (CGFloat)_paragraphFirstVisibleLineTopForContext:(_KKTextViewParagraphContext *)context {
    if (!context.layout) return 0;
    for (NSUInteger idx = 0; idx < context.layout.lines.count; idx++) {
        if (![self _paragraphContext:context canUseLineAtIndex:idx]) continue;
        KKTextLine *line = context.layout.lines[idx];
        return line.top;
    }
    return 0;
}

- (CGFloat)_paragraphVisibleTextHeightForContext:(_KKTextViewParagraphContext *)context {
    CGFloat height = [self _minimumParagraphHeightForContext:context];
    if (!context.layout) return height;
    for (NSUInteger idx = 0; idx < context.layout.lines.count; idx++) {
        if (![self _paragraphContext:context canUseLineAtIndex:idx]) continue;
        KKTextLine *line = context.layout.lines[idx];
        height = MAX(height, ceil(line.bottom));
    }
    return height;
}

- (CGSize)_paragraphDrawSizeForContext:(_KKTextViewParagraphContext *)context boundsSize:(CGSize)boundsSize {
    if (_verticalForm || _exclusionPaths.count > 0) {
        CGSize size = context.layout.textBoundingSize;
        CGSize visibleSize = [self _getVisibleSize];
        if (_verticalForm) {
            size.height = visibleSize.height;
            size.width = MAX(size.width, visibleSize.width);
        } else {
            size.width = visibleSize.width;
            size.height = MAX(size.height, visibleSize.height);
        }
        return size;
    }

    CGSize size = boundsSize;
    size.height = [self _paragraphVisibleTextHeightForContext:context];
    CGRect startCaretRect = [self _localCaretRectForParagraphContext:context location:context.range.location];
    if (!CGRectIsNull(startCaretRect)) {
        size.height = MAX(size.height, ceil(CGRectGetMaxY(startCaretRect)));
    }
    return size;
}

- (NSUInteger)_paragraphAttributeIndexForContext:(_KKTextViewParagraphContext *)context preferEnd:(BOOL)preferEnd {
    if (_innerText.length == 0) return NSNotFound;
    if (context.range.length > 0) {
        return preferEnd ? NSMaxRange(context.range) - 1 : context.range.location;
    }
    if (context.range.location < _innerText.length) return context.range.location;
    return _innerText.length - 1;
}

- (CGFloat)_paragraphSpacingAfterContext:(_KKTextViewParagraphContext *)context nextContext:(_KKTextViewParagraphContext *)nextContext {
    CGFloat spacing = 0;
    NSUInteger endIndex = [self _paragraphAttributeIndexForContext:context preferEnd:YES];
    if (endIndex != NSNotFound) {
        spacing += MAX([_innerText kk_paragraphSpacingAtIndex:endIndex], 0);
    }

    NSUInteger nextStartIndex = [self _paragraphAttributeIndexForContext:nextContext preferEnd:NO];
    if (nextStartIndex != NSNotFound) {
        spacing += MAX([_innerText kk_paragraphSpacingBeforeAtIndex:nextStartIndex], 0);
    }
    return spacing;
}

- (CGFloat)_paragraphLineBreakAdvanceForContext:(_KKTextViewParagraphContext *)context {
    if (context.lineBreakRange.length == 0 || !context.layout) return 0;
    NSUInteger localLocation = context.text.length + MAX(context.lineBreakRange.length, 1);
    KKTextPosition *position = [KKTextPosition positionWithOffset:localLocation affinity:KKTextAffinityBackward];
    CGRect rect = [context.layout caretRectForPosition:position];
    return CGRectIsNull(rect) ? 0 : ceil(CGRectGetMinY(rect));
}

- (CGFloat)_paragraphAdvanceToNextContext:(_KKTextViewParagraphContext *)context nextContext:(_KKTextViewParagraphContext *)nextContext {
    if (!nextContext || !context.layout || context.lineBreakRange.length == 0) return 0;
    NSUInteger probeLocation = context.text.length + context.lineBreakRange.length;
    KKTextPosition *position = [KKTextPosition positionWithOffset:probeLocation];
    CGRect rect = [context.layout caretRectForPosition:position];
    if (CGRectIsNull(rect)) {
        position = [KKTextPosition positionWithOffset:probeLocation affinity:KKTextAffinityBackward];
        rect = [context.layout caretRectForPosition:position];
    }
    if (CGRectIsNull(rect)) return 0;
    CGFloat nextTop = [self _paragraphFirstVisibleLineTopForContext:nextContext];
    return MAX(ceil(CGRectGetMinY(rect) - nextTop), 0);
}

- (CGFloat)_paragraphHeightForContext:(_KKTextViewParagraphContext *)context nextContext:(_KKTextViewParagraphContext *)nextContext boundsSize:(CGSize)boundsSize {
    CGFloat height = [self _paragraphDrawSizeForContext:context boundsSize:boundsSize].height;
    if (nextContext) {
        CGFloat advance = [self _paragraphAdvanceToNextContext:context nextContext:nextContext];
        if (advance > 0) {
            height = MAX(height, advance);
        } else {
            height = MAX(height, [self _paragraphLineBreakAdvanceForContext:context]);
            height += [self _paragraphSpacingAfterContext:context nextContext:nextContext];
        }
    }
    return MAX(height, [self _minimumParagraphHeightForContext:context]);
}

- (BOOL)_selectionRange:(NSRange)range containsEmptyParagraphContext:(_KKTextViewParagraphContext *)context {
    if (!context || context.text.length > 0 || range.length == 0) return NO;
    NSUInteger selectionStart = range.location;
    NSUInteger selectionEnd = NSMaxRange(range);
    if (context.lineBreakRange.length > 0) {
        return NSIntersectionRange(range, context.lineBreakRange).length > 0;
    }
    if (context.range.location == 0 || selectionStart >= context.range.location || selectionEnd < context.range.location) {
        return NO;
    }
    unichar previous = [_innerText.string characterAtIndex:context.range.location - 1];
    return KKTextIsLinebreakChar(previous);
}

- (BOOL)_selectionRange:(NSRange)range containsLineBreakForParagraphContext:(_KKTextViewParagraphContext *)context {
    if (!context || context.lineBreakRange.length == 0 || range.length == 0) return NO;
    return NSIntersectionRange(range, context.lineBreakRange).length > 0;
}

- (CGRect)_paragraphTailSelectionLineBoundsForContext:(_KKTextViewParagraphContext *)context {
    if (!context.layout) return CGRectNull;

    NSUInteger lineIndex = [self _lineIndexForParagraphContext:context localLocation:context.text.length];
    if (lineIndex == NSNotFound) {
        lineIndex = [self _edgeLineIndexForParagraphContext:context direction:UITextLayoutDirectionDown];
    }
    if (lineIndex == NSNotFound) return CGRectNull;

    KKTextLine *line = context.layout.lines[lineIndex];
    return line.bounds;
}

- (NSArray<KKTextSelectionRect *> *)_selectionRectsForParagraphTailInContext:(_KKTextViewParagraphContext *)context {
    if (!context.contentView) return @[];
    CGRect caretRect = [self _localCaretRectForParagraphContext:context location:NSMaxRange(context.range)];
    if (CGRectIsNull(caretRect)) {
        caretRect = CGRectMake(_textContainerInset.left, 0, 0, [self _minimumParagraphHeightForContext:context]);
    }
    CGRect lineBounds = [self _paragraphTailSelectionLineBoundsForContext:context];
    if (CGRectIsNull(lineBounds)) {
        lineBounds = CGRectMake(_textContainerInset.left, 0, 0, [self _minimumParagraphHeightForContext:context]);
    }

    NSMutableArray<KKTextSelectionRect *> *rects = [NSMutableArray arrayWithCapacity:2];
    CGFloat left = _textContainerInset.left;
    CGFloat right = _textContainerInset.right;
    CGFloat maxX = MAX(context.contentView.bounds.size.width - right, left);
    CGFloat minY = MAX(CGRectGetMinY(lineBounds), 0);
    CGFloat lineMaxY = MIN(CGRectGetMaxY(lineBounds), context.contentView.bounds.size.height);
    if (lineMaxY <= minY) {
        lineMaxY = MIN(minY + [self _minimumParagraphHeightForContext:context], context.contentView.bounds.size.height);
    }
    CGFloat caretX = MIN(MAX(CGRectGetMinX(caretRect), left), maxX);

    if (maxX > caretX && lineMaxY > minY) {
        KKTextSelectionRect *lineRect = [KKTextSelectionRect new];
        lineRect.rect = [self _documentRectForLocalRect:CGRectMake(caretX, minY, maxX - caretX, lineMaxY - minY) inParagraphContext:context];
        lineRect.isVertical = NO;
        [rects addObject:lineRect];
    }

    if (context.contentView.bounds.size.height > lineMaxY && maxX > left) {
        KKTextSelectionRect *tailRect = [KKTextSelectionRect new];
        tailRect.rect = [self _documentRectForLocalRect:CGRectMake(left, lineMaxY, maxX - left, context.contentView.bounds.size.height - lineMaxY) inParagraphContext:context];
        tailRect.isVertical = NO;
        [rects addObject:tailRect];
    }
    return rects;
}

- (NSArray<KKTextSelectionRect *> *)_selectionRectsForRange:(NSRange)range mode:(_KKTextViewSelectionRectMode)mode {
    range = KKTextViewMakeSafeRange(range, _innerText.length);
    if (range.length == 0) return @[];

    NSMutableArray<KKTextSelectionRect *> *rects = [NSMutableArray array];
    for (_KKTextViewParagraphContext *context in _paragraphContexts) {
        NSRange localRange = [self _localRangeForGlobalRange:range inParagraphContext:context];
        BOOL containsLineBreak = [self _selectionRange:range containsLineBreakForParagraphContext:context];
        if (localRange.location == NSNotFound || localRange.length == 0) {
            if (mode != _KKTextViewSelectionRectModeOnlyStartAndEnd) {
                if ([self _selectionRange:range containsEmptyParagraphContext:context] || containsLineBreak) {
                    [rects addObjectsFromArray:[self _selectionRectsForParagraphTailInContext:context]];
                }
            }
            continue;
        }

        KKTextRange *textRange = [KKTextRange rangeWithRange:localRange];
        NSArray<KKTextSelectionRect *> *localRects = nil;
        if (mode == _KKTextViewSelectionRectModeWithoutStartAndEnd) {
            localRects = [context.layout selectionRectsWithoutStartAndEndForRange:textRange];
        } else if (mode == _KKTextViewSelectionRectModeOnlyStartAndEnd) {
            localRects = [context.layout selectionRectsWithOnlyStartAndEndForRange:textRange];
        } else {
            localRects = [context.layout selectionRectsForRange:textRange];
        }
        for (KKTextSelectionRect *localRect in localRects) {
            KKTextSelectionRect *rect = localRect.copy;
            rect.rect = [self _documentRectForLocalRect:rect.rect inParagraphContext:context];
            [rects addObject:rect];
        }
        if (mode != _KKTextViewSelectionRectModeOnlyStartAndEnd && containsLineBreak) {
            [rects addObjectsFromArray:[self _selectionRectsForParagraphTailInContext:context]];
        }
    }
    return rects;
}

- (NSArray<KKTextSelectionRect *> *)_selectionRectsForTextRange:(KKTextRange *)range {
    return [self _selectionRectsForRange:range.asRange mode:_KKTextViewSelectionRectModeAll];
}

- (NSArray<KKTextSelectionRect *> *)_selectionRectsWithoutStartAndEndForTextRange:(KKTextRange *)range {
    return [self _selectionRectsForRange:range.asRange mode:_KKTextViewSelectionRectModeWithoutStartAndEnd];
}

- (NSArray<KKTextSelectionRect *> *)_selectionRectsWithOnlyStartAndEndForTextRange:(KKTextRange *)range {
    return [self _selectionRectsForRange:range.asRange mode:_KKTextViewSelectionRectModeOnlyStartAndEnd];
}

- (CGRect)_rectForTextRange:(KKTextRange *)range {
    if (!range) return CGRectNull;
    if (range.asRange.length == 0) return [self _caretRectForTextPosition:range.end];
    CGRect rect = CGRectNull;
    for (KKTextSelectionRect *selectionRect in [self _selectionRectsForTextRange:range]) {
        if (CGRectIsEmpty(selectionRect.rect) || CGRectIsNull(selectionRect.rect)) continue;
        rect = CGRectIsNull(rect) ? selectionRect.rect : CGRectUnion(rect, selectionRect.rect);
    }
    return rect;
}

- (CGRect)_firstRectForTextRange:(KKTextRange *)range {
    if (!range) return CGRectNull;
    _KKTextViewParagraphContext *context = [self _paragraphContextForLocation:range.start.offset];
    NSRange localRange = [self _localRangeForGlobalRange:range.asRange inParagraphContext:context];
    if (!context.layout || localRange.location == NSNotFound) return CGRectNull;
    CGRect rect = [context.layout firstRectForRange:[KKTextRange rangeWithRange:localRange]];
    return [self _documentRectForLocalRect:rect inParagraphContext:context];
}

- (CGRect)_caretRectForTextPosition:(KKTextPosition *)position {
    position = [self _correctedTextPosition:position];
    if (!position) return CGRectNull;
    _KKTextViewParagraphContext *context = [self _paragraphContextForLocation:position.offset];
    CGRect rect = [self _localCaretRectForParagraphContext:context location:position.offset];
    return [self _documentRectForLocalRect:rect inParagraphContext:context];
}

- (KKTextPosition *)_closestPositionForDocumentPoint:(CGPoint)point {
    _KKTextViewParagraphContext *context = [self _paragraphContextForDocumentPoint:point];
    if (!context.layout) return nil;
    CGPoint localPoint = [self _localPointForDocumentPoint:point inParagraphContext:context];
    KKTextPosition *position = [context.layout closestPositionToPoint:localPoint];
    if (!position) return nil;
    position = [KKTextPosition positionWithOffset:context.range.location + MIN(position.offset, context.text.length) affinity:position.affinity];
    return [self _correctedTextPosition:position];
}

- (KKTextPosition *)_positionForDocumentPoint:(CGPoint)point oldPosition:(KKTextPosition *)oldPosition otherPosition:(KKTextPosition *)otherPosition {
    _KKTextViewParagraphContext *context = [self _paragraphContextForDocumentPoint:point];
    if (!context.layout) return nil;
    CGPoint localPoint = [self _localPointForDocumentPoint:point inParagraphContext:context];
    KKTextPosition *localOld = oldPosition ? [KKTextPosition positionWithOffset:[self _localLocationForGlobalLocation:oldPosition.offset inParagraphContext:context] affinity:oldPosition.affinity] : nil;
    KKTextPosition *localOther = otherPosition ? [KKTextPosition positionWithOffset:[self _localLocationForGlobalLocation:otherPosition.offset inParagraphContext:context] affinity:otherPosition.affinity] : nil;
    KKTextPosition *position = [context.layout positionForPoint:localPoint oldPosition:localOld otherPosition:localOther];
    if (!position) return nil;
    position = [KKTextPosition positionWithOffset:context.range.location + MIN(position.offset, context.text.length) affinity:position.affinity];
    return [self _correctedTextPosition:position];
}

- (KKTextRange *)_textRangeAtDocumentPoint:(CGPoint)point closest:(BOOL)closest {
    _KKTextViewParagraphContext *context = [self _paragraphContextForDocumentPoint:point];
    if (!context.layout) return nil;
    CGPoint localPoint = [self _localPointForDocumentPoint:point inParagraphContext:context];
    KKTextRange *range = closest ? [context.layout closestTextRangeAtPoint:localPoint] : [context.layout textRangeAtPoint:localPoint];
    if (!range) return nil;
    NSRange globalRange = [self _globalRangeForLocalRange:range.asRange inParagraphContext:context];
    return [self _correctedTextRange:[KKTextRange rangeWithRange:globalRange affinity:range.end.affinity]];
}

- (KKTextRange *)_textRangeByExtendingTextPosition:(KKTextPosition *)position {
    position = [self _correctedTextPosition:position];
    if (!position) return nil;
    _KKTextViewParagraphContext *context = [self _paragraphContextForLocation:position.offset];
    if (!context.layout) return nil;
    KKTextPosition *localPosition = [KKTextPosition positionWithOffset:[self _localLocationForGlobalLocation:position.offset inParagraphContext:context] affinity:position.affinity];
    KKTextRange *range = [context.layout textRangeByExtendingPosition:localPosition];
    NSRange globalRange = [self _globalRangeForLocalRange:range.asRange inParagraphContext:context];
    return [self _correctedTextRange:[KKTextRange rangeWithRange:globalRange affinity:range.end.affinity]];
}

- (KKTextRange *)_textRangeByExtendingTextPosition:(KKTextPosition *)position inDirection:(UITextLayoutDirection)direction offset:(NSInteger)offset {
    position = [self _correctedTextPosition:position];
    if (!position) return nil;
    if (offset == 0) return [self _textRangeByExtendingTextPosition:position];

    BOOL verticalMove = _verticalForm ? (direction == UITextLayoutDirectionLeft || direction == UITextLayoutDirectionRight) : (direction == UITextLayoutDirectionUp || direction == UITextLayoutDirectionDown);
    if (!verticalMove) {
        NSInteger newLocation = (NSInteger)position.offset;
        BOOL forward = _verticalForm ? (direction == UITextLayoutDirectionLeft || direction == UITextLayoutDirectionDown) : (direction == UITextLayoutDirectionDown || direction == UITextLayoutDirectionRight);
        newLocation += forward ? offset : -offset;
        newLocation = MAX(0, MIN((NSInteger)_innerText.length, newLocation));
        return [self _textRangeByExtendingTextPosition:[KKTextPosition positionWithOffset:(NSUInteger)newLocation]];
    }

    _KKTextViewParagraphContext *context = [self _paragraphContextForLocation:position.offset];
    NSUInteger localLocation = [self _localLocationForGlobalLocation:position.offset inParagraphContext:context];
    NSUInteger lineIndex = [self _lineIndexForParagraphContext:context localLocation:localLocation];
    if (lineIndex != NSNotFound) {
        NSUInteger targetLineIndex = [self _lineIndexInParagraphContext:context fromLineIndex:lineIndex direction:direction];
        if (targetLineIndex != NSNotFound) {
            CGFloat targetX = CGRectGetMidX([self _caretRectForTextPosition:position]);
            NSUInteger location = [self _textLocationInParagraphContext:context lineIndex:targetLineIndex targetX:targetX];
            if (location != NSNotFound) {
                return [self _textRangeByExtendingTextPosition:[KKTextPosition positionWithOffset:location]];
            }
        }
    }

    NSUInteger contextIndex = [_paragraphContexts indexOfObjectIdenticalTo:context];
    if (contextIndex == NSNotFound) return nil;
    if (direction == UITextLayoutDirectionUp) {
        if (contextIndex == 0) return [KKTextRange rangeWithRange:NSMakeRange(0, 0)];
        context = _paragraphContexts[contextIndex - 1];
        lineIndex = [self _edgeLineIndexForParagraphContext:context direction:UITextLayoutDirectionUp];
    } else {
        if (contextIndex + 1 >= _paragraphContexts.count) return [KKTextRange rangeWithRange:NSMakeRange(_innerText.length, 0)];
        context = _paragraphContexts[contextIndex + 1];
        lineIndex = [self _edgeLineIndexForParagraphContext:context direction:UITextLayoutDirectionDown];
    }
    CGFloat targetX = CGRectGetMidX([self _caretRectForTextPosition:position]);
    NSUInteger location = [self _textLocationInParagraphContext:context lineIndex:lineIndex targetX:targetX];
    if (location == NSNotFound) return nil;
    return [self _textRangeByExtendingTextPosition:[KKTextPosition positionWithOffset:location]];
}

- (void)_updateParagraphContainerViewsReusingLayouts:(BOOL)reuseLayouts fadeDuration:(NSTimeInterval)fadeDuration {
    NSArray<_KKTextViewParagraphContext *> *oldContexts = _paragraphContexts.copy;
    NSAttributedString *displayText = [self _paragraphDisplayText];
    NSArray<NSValue *> *ranges = [self _paragraphContentRanges];
    NSMutableArray<_KKTextViewParagraphContext *> *contexts = [NSMutableArray arrayWithCapacity:ranges.count];
    NSMutableSet<KKTextContainerView *> *activeViews = [NSMutableSet set];
    NSMutableSet<_KKTextViewParagraphContext *> *reusedOldContexts = [NSMutableSet set];
    CGSize containerSize = [self _paragraphLayoutContainerSize];
    CGSize visibleSize = [self _getVisibleSize];
    CGFloat width = visibleSize.width;
    CGFloat fallbackY = _textContainerInset.top;

    for (NSUInteger idx = 0; idx < ranges.count; idx++) {
        _KKTextViewParagraphContext *context = [self _paragraphContextWithRange:ranges[idx].rangeValue displayText:displayText];
        context.layoutContainerSize = containerSize;
        [contexts addObject:context];
    }

    for (NSUInteger idx = 0; idx < contexts.count; idx++) {
        _KKTextViewParagraphContext *context = contexts[idx];
        _KKTextViewParagraphContext *nextContext = idx + 1 < contexts.count ? contexts[idx + 1] : nil;
        context.layoutTailText = [self _paragraphLayoutTailTextForContext:context nextContext:nextContext displayText:displayText];
        _KKTextViewParagraphContext *oldContext = [self _oldParagraphContextForCurrentContext:context oldContexts:oldContexts index:idx];
        if (oldContext && [reusedOldContexts containsObject:oldContext]) oldContext = nil;
        if (reuseLayouts &&
            [self _paragraphContext:context canReuseLayoutFromContext:oldContext containerSize:containerSize]) {
            context.layout = oldContext.layout;
            context.contentView = oldContext.contentView;
            [reusedOldContexts addObject:oldContext];
        } else {
            context.layout = [self _layoutForParagraphContext:context containerSize:containerSize];
        }

        if (!context.contentView) {
            context.contentView = [KKTextContainerView new];
            context.contentView.hostView = self;
            context.contentView.debugOption = _containerView.debugOption;
            [_containerView addSubview:context.contentView];
        }
        context.contentView.textVerticalAlignment = KKTextVerticalAlignmentTop;
        [context.contentView setLayout:context.layout withFadeDuration:fadeDuration];
        [activeViews addObject:context.contentView];
    }

    CGSize contentSize = visibleSize;
    if (_verticalForm || _exclusionPaths.count > 0) {
        _KKTextViewParagraphContext *context = contexts.firstObject;
        CGSize drawSize = [self _paragraphDrawSizeForContext:context boundsSize:visibleSize];
        context.contentView.frame = (CGRect){CGPointZero, drawSize};
        contentSize = drawSize;
    } else {
        for (NSUInteger idx = 0; idx < contexts.count; idx++) {
            _KKTextViewParagraphContext *context = contexts[idx];
            _KKTextViewParagraphContext *nextContext = idx + 1 < contexts.count ? contexts[idx + 1] : nil;
            CGFloat height = [self _paragraphHeightForContext:context nextContext:nextContext boundsSize:CGSizeMake(width, 0)];
            context.contentView.frame = (CGRect){CGPointMake(0, fallbackY), CGSizeMake(width, height)};
            fallbackY += height;
        }
        contentSize = CGSizeMake(width, MAX(fallbackY + _textContainerInset.bottom, visibleSize.height));
    }

    for (_KKTextViewParagraphContext *oldContext in oldContexts) {
        if (oldContext.contentView && ![activeViews containsObject:oldContext.contentView]) {
            [oldContext.contentView removeFromSuperview];
        }
    }

    _paragraphContexts = contexts;
    _containerView.frame = (CGRect){.size = contentSize};
    _selectionView.frame = _containerView.frame;
    self.contentSize = contentSize;
    [self _clearParagraphEditRecord];
}

- (void)_updateParagraphContainerViewsReusingLayouts:(BOOL)reuseLayouts {
    [self _updateParagraphContainerViewsReusingLayouts:reuseLayouts fadeDuration:0];
}

/// Update placeholder before runloop sleep/end.
- (void)_commitPlaceholderUpdate {
#if !TARGET_INTERFACE_BUILDER
    _state.placeholderNeedUpdate = YES;
    [[KKTextTransaction transactionWithTarget:self selector:@selector(_updatePlaceholderIfNeeded)] commit];
#else
    [self _updatePlaceholder];
#endif
}

/// Update placeholder if needed.
- (void)_updatePlaceholderIfNeeded {
    if (_state.placeholderNeedUpdate) {
        _state.placeholderNeedUpdate = NO;
        [self _updatePlaceholder];
    }
}

/// Update placeholder immediately.
- (void)_updatePlaceholder {
    CGRect frame = CGRectZero;
    _placeHolderView.image = nil;
    _placeHolderView.frame = frame;
    if (_placeholderAttributedText.length > 0) {
        KKTextContainer *container = _innerContainer.copy;
        container.size = self.bounds.size;
        container.truncationType = KKTextTruncationTypeEnd;
        container.truncationToken = nil;
        KKTextLayout *layout = [KKTextLayout layoutWithContainer:container text:_placeholderAttributedText];
        CGSize size = [layout textBoundingSize];
        BOOL needDraw = size.width > 1 && size.height > 1;
        if (needDraw) {
            UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
            format.opaque = NO;
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
            UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
                [layout drawInContext:rendererContext.CGContext size:size debug:self.debugOption];
            }];
            _placeHolderView.image = image;
            frame.size = image.size;
            if (container.isVerticalForm) {
                frame.origin.x = self.bounds.size.width - image.size.width;
            } else {
                frame.origin = CGPointZero;
            }
            _placeHolderView.frame = frame;
        }
    }
}

/// Update the `_selectedTextRange` to a single position by `_trackingPoint`.
- (void)_updateTextRangeByTrackingCaret {
    if (!_state.trackingTouch) return;
    
    KKTextPosition *newPos = [self _closestPositionForDocumentPoint:_trackingPoint];
    if (newPos) {
        newPos = [self _correctedTextPosition:newPos];
        if (_markedTextRange) {
            if ([newPos compare:_markedTextRange.start] == NSOrderedAscending) {
                newPos = _markedTextRange.start;
            } else if ([newPos compare:_markedTextRange.end] == NSOrderedDescending) {
                newPos = _markedTextRange.end;
            }
        }
        KKTextRange *newRange = [KKTextRange rangeWithRange:NSMakeRange(newPos.offset, 0) affinity:newPos.affinity];
        _trackingRange = newRange;
    }
}

/// Update the `_selectedTextRange` to a new range by `_trackingPoint` and `_state.trackingGrabber`.
- (void)_updateTextRangeByTrackingGrabber {
    if (!_state.trackingTouch || !_state.trackingGrabber) return;
    
    BOOL isStart = _state.trackingGrabber == kStart;
    CGPoint magPoint = _trackingPoint;
    magPoint.y += kMagnifierRangedTrackFix;
    KKTextPosition *position = [self _positionForDocumentPoint:magPoint
                                                   oldPosition:(isStart ? _selectedTextRange.start : _selectedTextRange.end)
                                                 otherPosition:(isStart ? _selectedTextRange.end : _selectedTextRange.start)];
    if (position) {
        position = [self _correctedTextPosition:position];
        if ((NSUInteger)position.offset > _innerText.length) {
            position = [KKTextPosition positionWithOffset:_innerText.length];
        }
        KKTextRange *newRange = [KKTextRange rangeWithStart:(isStart ? position : _selectedTextRange.start)
                                                        end:(isStart ? _selectedTextRange.end : position)];
        _trackingRange = newRange;
    }
}

/// Update the `_selectedTextRange` to a new range/position by `_trackingPoint`.
- (void)_updateTextRangeByTrackingPreSelect {
    if (!_state.trackingTouch) return;
    KKTextRange *newRange = [self _getClosestTokenRangeAtPoint:_trackingPoint];
    _trackingRange = newRange;
}

/// Show or update `_magnifierCaret` based on `_trackingPoint`, and hide `_magnifierRange`.
- (void)_showMagnifierCaret {
    if (KKTextIsAppExtension()) return;
    
    if (_state.showingMagnifierRanged) {
        _state.showingMagnifierRanged = NO;
        [[KKTextEffectWindow sharedWindow] hideMagnifier:_magnifierRanged];
    }
    
    _magnifierCaret.hostPopoverCenter = _trackingPoint;
    _magnifierCaret.hostCaptureCenter = _trackingPoint;
    if (!_state.showingMagnifierCaret) {
        _state.showingMagnifierCaret = YES;
        [[KKTextEffectWindow sharedWindow] showMagnifier:_magnifierCaret];
    } else {
        [[KKTextEffectWindow sharedWindow] moveMagnifier:_magnifierCaret];
    }
}

/// Show or update `_magnifierRanged` based on `_trackingPoint`, and hide `_magnifierCaret`.
- (void)_showMagnifierRanged {
    if (KKTextIsAppExtension()) return;
    
    if (_verticalForm) { // hack for vertical form...
        [self _showMagnifierCaret];
        return;
    }
    
    if (_state.showingMagnifierCaret) {
        _state.showingMagnifierCaret = NO;
        [[KKTextEffectWindow sharedWindow] hideMagnifier:_magnifierCaret];
    }
    
    CGPoint magPoint = _trackingPoint;
    if (_verticalForm) {
        magPoint.x += kMagnifierRangedTrackFix;
    } else {
        magPoint.y += kMagnifierRangedTrackFix;
    }
    
    KKTextRange *selectedRange = _selectedTextRange;
    if (_state.trackingTouch && _trackingRange) {
        selectedRange = _trackingRange;
    }
    
    KKTextPosition *position;
    if (_markedTextRange) {
        position = selectedRange.end;
    } else {
        position = [self _positionForDocumentPoint:magPoint
                                       oldPosition:(_state.trackingGrabber == kStart ? selectedRange.start : selectedRange.end)
                                     otherPosition:(_state.trackingGrabber == kStart ? selectedRange.end : selectedRange.start)];
    }
    if (!position) return;

    _KKTextViewParagraphContext *paragraphContext = [self _paragraphContextForLocation:position.offset];
    KKTextPosition *localPosition = [KKTextPosition positionWithOffset:[self _localLocationForGlobalLocation:position.offset inParagraphContext:paragraphContext] affinity:position.affinity];
    NSUInteger lineIndex = [paragraphContext.layout lineIndexForPosition:localPosition];
    if ([self _paragraphContext:paragraphContext canUseLineAtIndex:lineIndex]) {
        KKTextLine *line = paragraphContext.layout.lines[lineIndex];
        CGRect lineRect = [self _documentRectForLocalRect:line.bounds inParagraphContext:paragraphContext];
        if (_verticalForm) {
            magPoint.x = KKTEXT_CLAMP(magPoint.x, CGRectGetMinX(lineRect), CGRectGetMaxX(lineRect));
        } else {
            magPoint.y = KKTEXT_CLAMP(magPoint.y, CGRectGetMinY(lineRect), CGRectGetMaxY(lineRect));
        }
        CGPoint linePoint = [paragraphContext.layout linePositionForPosition:localPosition];
        linePoint = [self _documentRectForLocalRect:(CGRect){linePoint, CGSizeZero} inParagraphContext:paragraphContext].origin;
        
        CGPoint popoverPoint = linePoint;
        if (_verticalForm) {
            popoverPoint.x = linePoint.x + _magnifierRangedOffset;
        } else {
            popoverPoint.y = linePoint.y + _magnifierRangedOffset;
        }
        
        CGPoint capturePoint;
        if (_verticalForm) {
            capturePoint.x = linePoint.x + kMagnifierRangedCaptureOffset;
            capturePoint.y = linePoint.y;
        } else {
            capturePoint.x = linePoint.x;
            capturePoint.y = linePoint.y + kMagnifierRangedCaptureOffset;
        }
        
        _magnifierRanged.hostPopoverCenter = popoverPoint;
        _magnifierRanged.hostCaptureCenter = capturePoint;
        if (!_state.showingMagnifierRanged) {
            _state.showingMagnifierRanged = YES;
            [[KKTextEffectWindow sharedWindow] showMagnifier:_magnifierRanged];
        } else {
            [[KKTextEffectWindow sharedWindow] moveMagnifier:_magnifierRanged];
        }
    }
}

/// Update the showing magnifier.
- (void)_updateMagnifier {
    if (KKTextIsAppExtension()) return;
    
    if (_state.showingMagnifierCaret) {
        [[KKTextEffectWindow sharedWindow] moveMagnifier:_magnifierCaret];
    }
    if (_state.showingMagnifierRanged) {
        [[KKTextEffectWindow sharedWindow] moveMagnifier:_magnifierRanged];
    }
}

/// Hide the `_magnifierCaret` and `_magnifierRanged`.
- (void)_hideMagnifier {
    if (KKTextIsAppExtension()) return;
    
    if (_state.showingMagnifierCaret || _state.showingMagnifierRanged) {
        // disable touch began temporary to ignore caret animation overlap
        _state.ignoreTouchBegan = YES;
        __weak typeof(self) _self = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(_self) self = _self;
            if (self) self->_state.ignoreTouchBegan = NO;
        });
    }
    
    if (_state.showingMagnifierCaret) {
        _state.showingMagnifierCaret = NO;
        [[KKTextEffectWindow sharedWindow] hideMagnifier:_magnifierCaret];
    }
    if (_state.showingMagnifierRanged) {
        _state.showingMagnifierRanged = NO;
        [[KKTextEffectWindow sharedWindow] hideMagnifier:_magnifierRanged];
    }
}

/// Show and update the UIMenuController.
- (void)_showMenu {
    CGRect rect;
    if (_selectionView.caretVisible) {
        rect = _selectionView.caretView.frame;
    } else if (_selectionView.selectionRects.count > 0) {
        KKTextSelectionRect *sRect = _selectionView.selectionRects.firstObject;
        rect = sRect.rect;
        for (NSUInteger i = 1; i < _selectionView.selectionRects.count; i++) {
            sRect = _selectionView.selectionRects[i];
            rect = CGRectUnion(rect, sRect.rect);
        }
        
        CGRect inter = CGRectIntersection(rect, self.bounds);
        if (!CGRectIsNull(inter) && inter.size.height > 1) {
            rect = inter; //clip to bounds
        } else {
            if (CGRectGetMinY(rect) < CGRectGetMinY(self.bounds)) {
                rect.size.height = 1;
                rect.origin.y = CGRectGetMinY(self.bounds);
            } else {
                rect.size.height = 1;
                rect.origin.y = CGRectGetMaxY(self.bounds);
            }
        }
        
        KKTextKeyboardManager *mgr = [KKTextKeyboardManager defaultManager];
        if (mgr.keyboardVisible) {
            CGRect kbRect = [mgr convertRect:mgr.keyboardFrame toView:self];
            CGRect kbInter = CGRectIntersection(rect, kbRect);
            if (!CGRectIsNull(kbInter) && kbInter.size.height > 1 && kbInter.size.width > 1) {
                // self is covered by keyboard
                if (CGRectGetMinY(kbInter) > CGRectGetMinY(rect)) { // keyboard at bottom
                    rect.size.height -= kbInter.size.height;
                } else if (CGRectGetMaxY(kbInter) < CGRectGetMaxY(rect)) { // keyboard at top
                    rect.origin.y += kbInter.size.height;
                    rect.size.height -= kbInter.size.height;
                }
            }
        }
    } else {
        rect = _selectionView.bounds;
    }
    
    if (!self.isFirstResponder) {
        if (!_containerView.isFirstResponder) {
            [_containerView becomeFirstResponder];
        }
    }
    
    if (self.isFirstResponder || _containerView.isFirstResponder) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIMenuController *menu = [UIMenuController sharedMenuController];
            [menu setTargetRect:CGRectStandardize(rect) inView:_selectionView];
            [menu update];
            if (!_state.showingMenu || !menu.menuVisible) {
                _state.showingMenu = YES;
                [menu setMenuVisible:YES animated:YES];
            }
        });
    }
}

/// Hide the UIMenuController.
- (void)_hideMenu {
    if (_state.showingMenu) {
        _state.showingMenu = NO;
        UIMenuController *menu = [UIMenuController sharedMenuController];
        [menu setMenuVisible:NO animated:YES];
    }
    if (_containerView.isFirstResponder) {
        _state.ignoreFirstResponder = YES;
        [_containerView resignFirstResponder]; // it will call [self becomeFirstResponder], ignore it temporary.
        _state.ignoreFirstResponder = NO;
    }
}

/// Show highlight layout based on `_highlight` and `_highlightRange`.
- (void)_showHighlightAnimated:(BOOL)animated {
    NSTimeInterval fadeDuration = animated ? kHighlightFadeDuration : 0;
    if (!_highlight) return;
    if (!_state.showingHighlight) {
        _state.showingHighlight = YES;
        [self _updateParagraphContainerViewsReusingLayouts:NO fadeDuration:fadeDuration];
    }
}

/// Restore paragraph layouts instead of highlight layouts.
- (void)_hideHighlightAnimated:(BOOL)animated {
    NSTimeInterval fadeDuration = animated ? kHighlightFadeDuration : 0;
    if (_state.showingHighlight) {
        _state.showingHighlight = NO;
        [self _updateParagraphContainerViewsReusingLayouts:NO fadeDuration:fadeDuration];
    }
}

/// Restore paragraph layouts and destroy the highlight state.
- (void)_removeHighlightAnimated:(BOOL)animated {
    [self _hideHighlightAnimated:animated];
    _highlight = nil;
}

/// Scroll current selected range to visible.
- (void)_scrollSelectedRangeToVisible {
    [self _scrollRangeToVisible:_selectedTextRange];
}

/// Scroll range to visible, take account into keyboard and insets.
- (void)_scrollRangeToVisible:(KKTextRange *)range {
    if (!range) return;
    CGRect rect = [self _rectForTextRange:range];
    if (CGRectIsNull(rect)) return;
    rect = [_containerView convertRect:rect toView:self];
    
    if (rect.size.width < 1) rect.size.width = 1;
    if (rect.size.height < 1) rect.size.height = 1;
    CGFloat extend = 3;
    
    BOOL insetModified = NO;
    KKTextKeyboardManager *mgr = [KKTextKeyboardManager defaultManager];
    
    if (mgr.keyboardVisible && self.window && self.superview && self.isFirstResponder && !_verticalForm) {
        CGRect bounds = self.bounds;
        bounds.origin = CGPointZero;
        CGRect kbRect = [mgr convertRect:mgr.keyboardFrame toView:self];
        kbRect.origin.y -= _extraAccessoryViewHeight;
        kbRect.size.height += _extraAccessoryViewHeight;
        
        kbRect.origin.x -= self.contentOffset.x;
        kbRect.origin.y -= self.contentOffset.y;
        CGRect inter = CGRectIntersection(bounds, kbRect);
        if (!CGRectIsNull(inter) && inter.size.height > 1 && inter.size.width > extend) { // self is covered by keyboard
            if (CGRectGetMinY(inter) > CGRectGetMinY(bounds)) { // keyboard below self.top
                
                UIEdgeInsets originalContentInset = self.contentInset;
                UIEdgeInsets originalScrollIndicatorInsets = self.scrollIndicatorInsets;
                if (_insetModifiedByKeyboard) {
                    originalContentInset = _originalContentInset;
                    originalScrollIndicatorInsets = _originalScrollIndicatorInsets;
                }
                
                if (originalContentInset.bottom < inter.size.height + extend) {
                    insetModified = YES;
                    if (!_insetModifiedByKeyboard) {
                        _insetModifiedByKeyboard = YES;
                        _originalContentInset = self.contentInset;
                        _originalScrollIndicatorInsets = self.scrollIndicatorInsets;
                    }
                    UIEdgeInsets newInset = originalContentInset;
                    UIEdgeInsets newIndicatorInsets = originalScrollIndicatorInsets;
                    newInset.bottom = inter.size.height + extend;
                    newIndicatorInsets.bottom = newInset.bottom;
                    UIViewAnimationOptions curve;
                    if (kiOS7Later) {
                        curve = 7 << 16;
                    } else {
                        curve = UIViewAnimationOptionCurveEaseInOut;
                    }
                    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | curve animations:^{
                        [super setContentInset:newInset];
                        [super setScrollIndicatorInsets:newIndicatorInsets];
                        [self scrollRectToVisible:CGRectInset(rect, -extend, -extend) animated:NO];
                    } completion:NULL];
                }
            }
        }
    }
    if (!insetModified) {
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationCurveEaseOut animations:^{
            [self _restoreInsetsAnimated:NO];
            [self scrollRectToVisible:CGRectInset(rect, -extend, -extend) animated:NO];
        } completion:NULL];
    }
}

/// Restore contents insets if modified by keyboard.
- (void)_restoreInsetsAnimated:(BOOL)animated {
    if (_insetModifiedByKeyboard) {
        _insetModifiedByKeyboard = NO;
        if (animated) {
            [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationCurveEaseOut  animations:^{
                [super setContentInset:_originalContentInset];
                [super setScrollIndicatorInsets:_originalScrollIndicatorInsets];
            } completion:NULL];
        } else {
            [super setContentInset:_originalContentInset];
            [super setScrollIndicatorInsets:_originalScrollIndicatorInsets];
        }
    }
}

/// Keyboard frame changed, scroll the caret to visible range, or modify the content insets.
- (void)_keyboardChanged {
    if (!self.isFirstResponder) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([KKTextKeyboardManager defaultManager].keyboardVisible) {
            [self _scrollRangeToVisible:_selectedTextRange];
        } else {
            [self _restoreInsetsAnimated:YES];
        }
        [self _updateMagnifier];
        if (_state.showingMenu) {
            [self _showMenu];
        }
    });
}

/// Start long press timer, used for 'highlight' range text action.
- (void)_startLongPressTimer {
    [_longPressTimer invalidate];
    _longPressTimer = [NSTimer timerWithTimeInterval:kLongPressMinimumDuration
                                              target:[KKTextWeakProxy proxyWithTarget:self]
                                            selector:@selector(_trackDidLongPress)
                                            userInfo:nil
                                             repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:_longPressTimer forMode:NSRunLoopCommonModes];
}

/// Invalidate the long press timer.
- (void)_endLongPressTimer {
    [_longPressTimer invalidate];
    _longPressTimer = nil;
}

/// Long press detected.
- (void)_trackDidLongPress {
    [self _endLongPressTimer];
    
    BOOL dealLongPressAction = NO;
    if (_state.showingHighlight) {
        [self _hideMenu];
        
        if (_highlight.longPressAction) {
            dealLongPressAction = YES;
            CGRect rect = [self _rectForTextRange:[KKTextRange rangeWithRange:_highlightRange]];
            _highlight.longPressAction(self, _innerText, _highlightRange, rect);
            [self _endTouchTracking];
        } else {
            BOOL shouldHighlight = YES;
            if ([self.delegate respondsToSelector:@selector(textView:shouldLongPressHighlight:inRange:)]) {
                shouldHighlight = [self.delegate textView:self shouldLongPressHighlight:_highlight inRange:_highlightRange];
            }
            if (shouldHighlight && [self.delegate respondsToSelector:@selector(textView:didLongPressHighlight:inRange:rect:)]) {
                dealLongPressAction = YES;
                CGRect rect = [self _rectForTextRange:[KKTextRange rangeWithRange:_highlightRange]];
                [self.delegate textView:self didLongPressHighlight:_highlight inRange:_highlightRange rect:rect];
                [self _endTouchTracking];
            }
        }
    }
    
    if (!dealLongPressAction){
        [self _removeHighlightAnimated:NO];
        if (_state.trackingTouch) {
            if (_state.trackingGrabber) {
                self.panGestureRecognizer.enabled = NO;
                [self _hideMenu];
                [self _showMagnifierRanged];
            } else if (self.isFirstResponder){
                self.panGestureRecognizer.enabled = NO;
                _selectionView.caretBlinks = NO;
                _state.trackingCaret = YES;
                KKTextPosition *newPos = [self _closestPositionForDocumentPoint:_trackingPoint];
                newPos = [self _correctedTextPosition:newPos];
                if (newPos) {
                    if (_markedTextRange) {
                        if ([newPos compare:_markedTextRange.start] != NSOrderedDescending) {
                            newPos = _markedTextRange.start;
                        } else if ([newPos compare:_markedTextRange.end] != NSOrderedAscending) {
                            newPos = _markedTextRange.end;
                        }
                    }
                    _trackingRange = [KKTextRange rangeWithRange:NSMakeRange(newPos.offset, 0) affinity:newPos.affinity];
                    [self _updateSelectionView];
                }
                [self _hideMenu];
                
                if (_markedTextRange) {
                    [self _showMagnifierRanged];
                } else {
                    [self _showMagnifierCaret];
                }
            } else if (self.selectable) {
                self.panGestureRecognizer.enabled = NO;
                _state.trackingPreSelect = YES;
                _state.selectedWithoutEdit = NO;
                [self _updateTextRangeByTrackingPreSelect];
                [self _updateSelectionView];
                [self _showMagnifierCaret];
            }
        }
    }
}

/// Start auto scroll timer, used for auto scroll tick.
- (void)_startAutoScrollTimer {
    if (!_autoScrollTimer) {
        [_autoScrollTimer invalidate];
        _autoScrollTimer = [NSTimer timerWithTimeInterval:kAutoScrollMinimumDuration
                                                   target:[KKTextWeakProxy proxyWithTarget:self]
                                                 selector:@selector(_trackDidTickAutoScroll)
                                                 userInfo:nil
                                                  repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:_autoScrollTimer forMode:NSRunLoopCommonModes];
    }
}

/// Invalidate the auto scroll, and restore the text view state.
- (void)_endAutoScrollTimer {
    if (_state.autoScrollTicked) [self flashScrollIndicators];
    [_autoScrollTimer invalidate];
    _autoScrollTimer = nil;
    _autoScrollOffset = 0;
    _autoScrollAcceleration = 0;
    _state.autoScrollTicked = NO;
    
    if (_magnifierCaret.captureDisabled) {
        _magnifierCaret.captureDisabled = NO;
        if (_state.showingMagnifierCaret) {
            [self _showMagnifierCaret];
        }
    }
    if (_magnifierRanged.captureDisabled) {
        _magnifierRanged.captureDisabled = NO;
        if (_state.showingMagnifierRanged) {
            [self _showMagnifierRanged];
        }
    }
}

/// Auto scroll ticked by timer.
- (void)_trackDidTickAutoScroll {
    if (_autoScrollOffset != 0) {
        _magnifierCaret.captureDisabled = YES;
        _magnifierRanged.captureDisabled = YES;
        
        CGPoint offset = self.contentOffset;
        if (_verticalForm) {
            offset.x += _autoScrollOffset;
            
            if (_autoScrollAcceleration > 0) {
                offset.x += ((_autoScrollOffset > 0 ? 1 : -1) * _autoScrollAcceleration * _autoScrollAcceleration * 0.5);
            }
            _autoScrollAcceleration++;
            offset.x = round(offset.x);
            if (_autoScrollOffset < 0) {
                if (offset.x < -self.contentInset.left) offset.x = -self.contentInset.left;
            } else {
                CGFloat maxOffsetX = self.contentSize.width - self.bounds.size.width + self.contentInset.right;
                if (offset.x > maxOffsetX) offset.x = maxOffsetX;
            }
            if (offset.x < -self.contentInset.left) offset.x = -self.contentInset.left;
        } else {
            offset.y += _autoScrollOffset;
            if (_autoScrollAcceleration > 0) {
                offset.y += ((_autoScrollOffset > 0 ? 1 : -1) * _autoScrollAcceleration * _autoScrollAcceleration * 0.5);
            }
            _autoScrollAcceleration++;
            offset.y = round(offset.y);
            if (_autoScrollOffset < 0) {
                if (offset.y < -self.contentInset.top) offset.y = -self.contentInset.top;
            } else {
                CGFloat maxOffsetY = self.contentSize.height - self.bounds.size.height + self.contentInset.bottom;
                if (offset.y > maxOffsetY) offset.y = maxOffsetY;
            }
            if (offset.y < -self.contentInset.top) offset.y = -self.contentInset.top;
        }
        
        BOOL shouldScroll;
        if (_verticalForm) {
            shouldScroll = fabs(offset.x -self.contentOffset.x) > 0.5;
        } else {
            shouldScroll = fabs(offset.y -self.contentOffset.y) > 0.5;
        }
        
        if (shouldScroll) {
            _state.autoScrollTicked = YES;
            _trackingPoint.x += offset.x - self.contentOffset.x;
            _trackingPoint.y += offset.y - self.contentOffset.y;
            [UIView animateWithDuration:kAutoScrollMinimumDuration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveLinear animations:^{
                [self setContentOffset:offset];
            } completion:^(BOOL finished) {
                if (_state.trackingTouch) {
                    if (_state.trackingGrabber) {
                        [self _showMagnifierRanged];
                        [self _updateTextRangeByTrackingGrabber];
                    } else if (_state.trackingPreSelect) {
                        [self _showMagnifierCaret];
                        [self _updateTextRangeByTrackingPreSelect];
                    } else if (_state.trackingCaret) {
                        if (_markedTextRange) {
                            [self _showMagnifierRanged];
                        } else {
                            [self _showMagnifierCaret];
                        }
                        [self _updateTextRangeByTrackingCaret];
                    }
                    [self _updateSelectionView];
                }
            }];
        } else {
            [self _endAutoScrollTimer];
        }
    } else {
        [self _endAutoScrollTimer];
    }
}

/// End current touch tracking (if is tracking now), and update the state.
- (void)_endTouchTracking {
    if (!_state.trackingTouch) return;
    
    _state.trackingTouch = NO;
    _state.trackingGrabber = NO;
    _state.trackingCaret = NO;
    _state.trackingPreSelect = NO;
    _state.touchMoved = NO;
    _state.deleteConfirm = NO;
    _state.clearsOnInsertionOnce = NO;
    _trackingRange = nil;
    _selectionView.caretBlinks = YES;
    
    [self _removeHighlightAnimated:YES];
    [self _hideMagnifier];
    [self _endLongPressTimer];
    [self _endAutoScrollTimer];
    [self _updateSelectionView];
    
    self.panGestureRecognizer.enabled = self.scrollEnabled;
}

/// Start a timer to fix the selection dot.
- (void)_startSelectionDotFixTimer {
    [_selectionDotFixTimer invalidate];
    _longPressTimer = [NSTimer timerWithTimeInterval:1/15.0
                                              target:[KKTextWeakProxy proxyWithTarget:self]
                                            selector:@selector(_fixSelectionDot)
                                            userInfo:nil
                                             repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:_longPressTimer forMode:NSRunLoopCommonModes];
}

/// End the timer.
- (void)_endSelectionDotFixTimer {
    [_selectionDotFixTimer invalidate];
    _selectionDotFixTimer = nil;
}

/// If it shows selection grabber and this view was moved by super view,
/// update the selection dot in window.
- (void)_fixSelectionDot {
    if (KKTextIsAppExtension()) return;
    CGPoint origin = [self kk_convertPoint:CGPointZero toViewOrWindow:[KKTextEffectWindow sharedWindow]];
    if (!CGPointEqualToPoint(origin, _previousOriginInWindow)) {
        _previousOriginInWindow = origin;
        [[KKTextEffectWindow sharedWindow] hideSelectionDot:_selectionView];
        [[KKTextEffectWindow sharedWindow] showSelectionDot:_selectionView];
    }
}

/// Try to get the character range/position with word granularity from the tokenizer.
- (KKTextRange *)_getClosestTokenRangeAtPosition:(KKTextPosition *)position {
    position = [self _correctedTextPosition:position];
    if (!position) return nil;
    KKTextRange *range = nil;
    if (_tokenizer) {
        range = (id)[_tokenizer rangeEnclosingPosition:position withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionForward];
        if (range.asRange.length == 0) {
            range = (id)[_tokenizer rangeEnclosingPosition:position withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionBackward];
        }
    }
    
    if (!range || range.asRange.length == 0) {
        range = [self _textRangeByExtendingTextPosition:position inDirection:UITextLayoutDirectionRight offset:1];
        range = [self _correctedTextRange:range];
        if (range.asRange.length == 0) {
            range = [self _textRangeByExtendingTextPosition:position inDirection:UITextLayoutDirectionLeft offset:1];
            range = [self _correctedTextRange:range];
        }
    } else {
        KKTextRange *extStart = [self _textRangeByExtendingTextPosition:range.start];
        KKTextRange *extEnd = [self _textRangeByExtendingTextPosition:range.end];
        if (extStart && extEnd) {
            NSArray *arr = [@[extStart.start, extStart.end, extEnd.start, extEnd.end] sortedArrayUsingSelector:@selector(compare:)];
            range = [KKTextRange rangeWithStart:arr.firstObject end:arr.lastObject];
        }
    }
    
    range = [self _correctedTextRange:range];
    if (range.asRange.length == 0) {
        range = [KKTextRange rangeWithRange:NSMakeRange(0, _innerText.length)];
    }
    
    return [self _correctedTextRange:range];
}

/// Try to get the character range/position with word granularity from the tokenizer.
- (KKTextRange *)_getClosestTokenRangeAtPoint:(CGPoint)point {
    KKTextRange *touchRange = [self _textRangeAtDocumentPoint:point closest:YES];
    touchRange = [self _correctedTextRange:touchRange];
    
    if (_tokenizer && touchRange) {
        KKTextRange *encEnd = (id)[_tokenizer rangeEnclosingPosition:touchRange.end withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionBackward];
        KKTextRange *encStart = (id)[_tokenizer rangeEnclosingPosition:touchRange.start withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionForward];
        if (encEnd && encStart) {
            NSArray *arr = [@[encEnd.start, encEnd.end, encStart.start, encStart.end] sortedArrayUsingSelector:@selector(compare:)];
            touchRange = [KKTextRange rangeWithStart:arr.firstObject end:arr.lastObject];
        }
    }
    
    if (touchRange) {
        KKTextRange *extStart = [self _textRangeByExtendingTextPosition:touchRange.start];
        KKTextRange *extEnd = [self _textRangeByExtendingTextPosition:touchRange.end];
        if (extStart && extEnd) {
            NSArray *arr = [@[extStart.start, extStart.end, extEnd.start, extEnd.end] sortedArrayUsingSelector:@selector(compare:)];
            touchRange = [KKTextRange rangeWithStart:arr.firstObject end:arr.lastObject];
        }
    }
    
    if (!touchRange) touchRange = [KKTextRange defaultRange];
    
    if (_innerText.length && touchRange.asRange.length == 0) {
        touchRange = [KKTextRange rangeWithRange:NSMakeRange(0, _innerText.length)];
    }
    
    return touchRange;
}

/// Try to get the highlight property. If exist, the range will be returnd by the range pointer.
/// If the delegate ignore the highlight, returns nil.
- (KKTextHighlight *)_getHighlightAtPoint:(CGPoint)point range:(NSRangePointer)range {
    if (!_highlightable) return nil;
    KKTextRange *textRange = [self _textRangeAtDocumentPoint:point closest:NO];
    textRange = [self _correctedTextRange:textRange];
    if (!textRange) return nil;
    NSUInteger startIndex = textRange.start.offset;
    if (startIndex == _innerText.length) {
        if (startIndex == 0) return nil;
        else startIndex--;
    }
    NSRange highlightRange = {0};
    NSAttributedString *text = _delectedText ? _delectedText : _innerText;
    KKTextHighlight *highlight = [text attribute:KKTextHighlightAttributeName
                                         atIndex:startIndex
                           longestEffectiveRange:&highlightRange
                                         inRange:NSMakeRange(0, _innerText.length)];
    
    if (!highlight) return nil;
    
    BOOL shouldTap = YES, shouldLongPress = YES;
    if (!highlight.tapAction && !highlight.longPressAction) {
        if ([self.delegate respondsToSelector:@selector(textView:shouldTapHighlight:inRange:)]) {
            shouldTap = [self.delegate textView:self shouldTapHighlight:highlight inRange:highlightRange];
        }
        if ([self.delegate respondsToSelector:@selector(textView:shouldLongPressHighlight:inRange:)]) {
            shouldLongPress = [self.delegate textView:self shouldLongPressHighlight:highlight inRange:highlightRange];
        }
    }
    if (!shouldTap && !shouldLongPress) return nil;
    if (range) *range = highlightRange;
    return highlight;
}

/// Return the ranged magnifier popover offset from the baseline, base on `_trackingPoint`.
- (CGFloat)_getMagnifierRangedOffset {
    CGPoint magPoint = _trackingPoint;
    if (_verticalForm) {
        magPoint.x += kMagnifierRangedTrackFix;
    } else {
        magPoint.y += kMagnifierRangedTrackFix;
    }
    KKTextPosition *position = [self _closestPositionForDocumentPoint:magPoint];
    _KKTextViewParagraphContext *paragraphContext = [self _paragraphContextForLocation:position.offset];
    KKTextPosition *localPosition = [KKTextPosition positionWithOffset:[self _localLocationForGlobalLocation:position.offset inParagraphContext:paragraphContext] affinity:position.affinity];
    NSUInteger lineIndex = [paragraphContext.layout lineIndexForPosition:localPosition];
    if ([self _paragraphContext:paragraphContext canUseLineAtIndex:lineIndex]) {
        KKTextLine *line = paragraphContext.layout.lines[lineIndex];
        CGRect lineBounds = [self _documentRectForLocalRect:line.bounds inParagraphContext:paragraphContext];
        CGPoint linePosition = [self _documentRectForLocalRect:(CGRect){line.position, CGSizeZero} inParagraphContext:paragraphContext].origin;
        if (_verticalForm) {
            magPoint.x = KKTEXT_CLAMP(magPoint.x, CGRectGetMinX(lineBounds), CGRectGetMaxX(lineBounds));
            return magPoint.x - linePosition.x + kMagnifierRangedPopoverOffset;
        } else {
            magPoint.y = KKTEXT_CLAMP(magPoint.y, CGRectGetMinY(lineBounds), CGRectGetMaxY(lineBounds));
            return magPoint.y - linePosition.y + kMagnifierRangedPopoverOffset;
        }
    } else {
        return 0;
    }
}

/// Return a KKTextMoveDirection from `_touchBeganPoint` to `_trackingPoint`.
- (unsigned int)_getMoveDirection {
    CGFloat moveH = _trackingPoint.x - _touchBeganPoint.x;
    CGFloat moveV = _trackingPoint.y - _touchBeganPoint.y;
    if (fabs(moveH) > fabs(moveV)) {
        if (fabs(moveH) > kLongPressAllowableMovement) {
            return moveH > 0 ? kRight : kLeft;
        }
    } else {
        if (fabs(moveV) > kLongPressAllowableMovement) {
            return moveV > 0 ? kBottom : kTop;
        }
    }
    return 0;
}

/// Get the auto scroll offset in one tick time.
- (CGFloat)_getAutoscrollOffset {
    if (!_state.trackingTouch) return 0;
    
    CGRect bounds = self.bounds;
    bounds.origin = CGPointZero;
    KKTextKeyboardManager *mgr = [KKTextKeyboardManager defaultManager];
    if (mgr.keyboardVisible && self.window && self.superview && self.isFirstResponder && !_verticalForm) {
        CGRect kbRect = [mgr convertRect:mgr.keyboardFrame toView:self];
        kbRect.origin.y -= _extraAccessoryViewHeight;
        kbRect.size.height += _extraAccessoryViewHeight;
        
        kbRect.origin.x -= self.contentOffset.x;
        kbRect.origin.y -= self.contentOffset.y;
        CGRect inter = CGRectIntersection(bounds, kbRect);
        if (!CGRectIsNull(inter) && inter.size.height > 1 && inter.size.width > 1) {
            if (CGRectGetMinY(inter) > CGRectGetMinY(bounds)) {
                bounds.size.height -= inter.size.height;
            }
        }
    }
    
    CGPoint point = _trackingPoint;
    point.x -= self.contentOffset.x;
    point.y -= self.contentOffset.y;
    
    CGFloat maxOfs = 32; // a good value ~
    CGFloat ofs = 0;
    if (_verticalForm) {
        if (point.x < self.contentInset.left) {
            ofs = (point.x - self.contentInset.left - 5) * 0.5;
            if (ofs < -maxOfs) ofs = -maxOfs;
        } else if (point.x > bounds.size.width) {
            ofs = ((point.x - bounds.size.width) + 5) * 0.5;
            if (ofs > maxOfs) ofs = maxOfs;
        }
    } else {
        if (point.y < self.contentInset.top) {
            ofs = (point.y - self.contentInset.top - 5) * 0.5;
            if (ofs < -maxOfs) ofs = -maxOfs;
        } else if (point.y > bounds.size.height) {
            ofs = ((point.y - bounds.size.height) + 5) * 0.5;
            if (ofs > maxOfs) ofs = maxOfs;
        }
    }
    return ofs;
}

/// Visible size based on bounds and insets
- (CGSize)_getVisibleSize {
    CGSize visibleSize = self.bounds.size;
    visibleSize.width -= self.contentInset.left - self.contentInset.right;
    visibleSize.height -= self.contentInset.top - self.contentInset.bottom;
    if (visibleSize.width < 0) visibleSize.width = 0;
    if (visibleSize.height < 0) visibleSize.height = 0;
    return visibleSize;
}

/// Returns whether the text view can paste data from pastboard.
- (BOOL)_isPasteboardContainsValidValue {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    if (pasteboard.string.length > 0) {
        return YES;
    }
    if (pasteboard.kk_AttributedString.length > 0) {
        if (_allowsPasteAttributedString) {
            return YES;
        }
    }
    if (pasteboard.image || pasteboard.kk_ImageData.length > 0) {
        if (_allowsPasteImage) {
            return YES;
        }
    }
    return NO;
}

/// Save current selected attributed text to pasteboard.
- (void)_copySelectedTextToPasteboard {
    if (_allowsCopyAttributedString) {
        NSAttributedString *text = [_innerText attributedSubstringFromRange:_selectedTextRange.asRange];
        if (text.length) {
            [UIPasteboard generalPasteboard].kk_AttributedString = text;
        }
    } else {
        NSString *string = [_innerText kk_plainTextForRange:_selectedTextRange.asRange];
        if (string.length) {
            [UIPasteboard generalPasteboard].string = string;
        }
    }
}

/// Update the text view state when pasteboard changed.
- (void)_pasteboardChanged {
    if (_state.showingMenu) {
        UIMenuController *menu = [UIMenuController sharedMenuController];
        [menu update];
    }
}

/// Whether the position is valid (not out of bounds).
- (BOOL)_isTextPositionValid:(KKTextPosition *)position {
    if (!position) return NO;
    if (position.offset < 0) return NO;
    if (position.offset > _innerText.length) return NO;
    if (position.offset == 0 && position.affinity == KKTextAffinityBackward) return NO;
    if (position.offset == _innerText.length && position.affinity == KKTextAffinityBackward) return NO;
    return YES;
}

/// Whether the range is valid (not out of bounds).
- (BOOL)_isTextRangeValid:(KKTextRange *)range {
    if (![self _isTextPositionValid:range.start]) return NO;
    if (![self _isTextPositionValid:range.end]) return NO;
    return YES;
}

/// Correct the position if it out of bounds.
- (KKTextPosition *)_correctedTextPosition:(KKTextPosition *)position {
    if (!position) return nil;
    if ([self _isTextPositionValid:position]) return position;
    if (position.offset < 0) {
        return [KKTextPosition positionWithOffset:0];
    }
    if (position.offset > _innerText.length) {
        return [KKTextPosition positionWithOffset:_innerText.length];
    }
    if (position.offset == 0 && position.affinity == KKTextAffinityBackward) {
        return [KKTextPosition positionWithOffset:position.offset];
    }
    if (position.offset == _innerText.length && position.affinity == KKTextAffinityBackward) {
        return [KKTextPosition positionWithOffset:position.offset];
    }
    return position;
}

/// Correct the range if it out of bounds.
- (KKTextRange *)_correctedTextRange:(KKTextRange *)range {
    if (!range) return nil;
    if ([self _isTextRangeValid:range]) return range;
    KKTextPosition *start = [self _correctedTextPosition:range.start];
    KKTextPosition *end = [self _correctedTextPosition:range.end];
    return [KKTextRange rangeWithStart:start end:end];
}

/// Replace the range with the text, and change the `_selectTextRange`.
/// The caller should make sure the `range` and `text` are valid before call this method.
- (void)_replaceRange:(KKTextRange *)range withText:(NSString *)text notifyToDelegate:(BOOL)notify{
    if (NSEqualRanges(range.asRange, _selectedTextRange.asRange)) {
        if (notify) [_inputDelegate selectionWillChange:self];
        NSRange newRange = NSMakeRange(0, 0);
        newRange.location = _selectedTextRange.start.offset + text.length;
        _selectedTextRange = [KKTextRange rangeWithRange:newRange];
        if (notify) [_inputDelegate selectionDidChange:self];
    } else {
        if (range.asRange.length != text.length) {
            if (notify) [_inputDelegate selectionWillChange:self];
            NSRange unionRange = NSIntersectionRange(_selectedTextRange.asRange, range.asRange);
            if (unionRange.length == 0) {
                // no intersection
                if (range.end.offset <= _selectedTextRange.start.offset) {
                    NSInteger ofs = (NSInteger)text.length - (NSInteger)range.asRange.length;
                    NSRange newRange = _selectedTextRange.asRange;
                    newRange.location += ofs;
                    _selectedTextRange = [KKTextRange rangeWithRange:newRange];
                }
            } else if (unionRange.length == _selectedTextRange.asRange.length) {
                // target range contains selected range
                _selectedTextRange = [KKTextRange rangeWithRange:NSMakeRange(range.start.offset + text.length, 0)];
            } else if (range.start.offset >= _selectedTextRange.start.offset &&
                       range.end.offset <= _selectedTextRange.end.offset) {
                // target range inside selected range
                NSInteger ofs = (NSInteger)text.length - (NSInteger)range.asRange.length;
                NSRange newRange = _selectedTextRange.asRange;
                newRange.length += ofs;
                _selectedTextRange = [KKTextRange rangeWithRange:newRange];
            } else {
                // interleaving
                if (range.start.offset < _selectedTextRange.start.offset) {
                    NSRange newRange = _selectedTextRange.asRange;
                    newRange.location = range.start.offset + text.length;
                    newRange.length -= unionRange.length;
                    _selectedTextRange = [KKTextRange rangeWithRange:newRange];
                } else {
                    NSRange newRange = _selectedTextRange.asRange;
                    newRange.length -= unionRange.length;
                    _selectedTextRange = [KKTextRange rangeWithRange:newRange];
                }
            }
            _selectedTextRange = [self _correctedTextRange:_selectedTextRange];
            if (notify) [_inputDelegate selectionDidChange:self];
        }
    }
    if (notify) [_inputDelegate textWillChange:self];
    NSRange newRange = NSMakeRange(range.asRange.location, text.length);
    [self _recordParagraphEditRange:range.asRange replacementLength:text.length];
    [_innerText replaceCharactersInRange:range.asRange withString:text];
    [_innerText kk_removeDiscontinuousAttributesInRange:newRange];
    if (notify) [_inputDelegate textDidChange:self];
}

/// Save current typing attributes to the attributes holder.
- (void)_updateAttributesHolder {
    if (_innerText.length > 0) {
        NSUInteger index = _selectedTextRange.end.offset == 0 ? 0 : _selectedTextRange.end.offset - 1;
        NSDictionary *attributes = [_innerText kk_attributesAtIndex:index];
        if (!attributes) attributes = @{};
        _typingAttributesHolder.kk_attributes = attributes;
        [_typingAttributesHolder kk_removeDiscontinuousAttributesInRange:NSMakeRange(0, _typingAttributesHolder.length)];
        [_typingAttributesHolder removeAttribute:KKTextBorderAttributeName range:NSMakeRange(0, _typingAttributesHolder.length)];
        [_typingAttributesHolder removeAttribute:KKTextBackgroundBorderAttributeName range:NSMakeRange(0, _typingAttributesHolder.length)];
    }
}

/// Update outer properties from current inner data.
- (void)_updateOuterProperties {
    [self _updateAttributesHolder];
    NSParagraphStyle *style = _innerText.kk_paragraphStyle;
    if (!style) style = _typingAttributesHolder.kk_paragraphStyle;
    if (!style) style = [NSParagraphStyle defaultParagraphStyle];
    
    UIFont *font = _innerText.kk_font;
    if (!font) font = _typingAttributesHolder.kk_font;
    if (!font) font = [self _defaultFont];
    
    UIColor *color = _innerText.kk_color;
    if (!color) color = _typingAttributesHolder.kk_color;
    if (!color) color = [UIColor blackColor];
    
    [self _setText:[_innerText kk_plainTextForRange:NSMakeRange(0, _innerText.length)]];
    [self _setFont:font];
    [self _setTextColor:color];
    [self _setTextAlignment:style.alignment];
    [self _setSelectedRange:_selectedTextRange.asRange];
    [self _setTypingAttributes:_typingAttributesHolder.kk_attributes];
    [self _setAttributedText:_innerText];
}

/// Parse text with `textParser` and update the _selectedTextRange.
/// @return Whether changed (text or selection)
- (BOOL)_parseText {
    if (self.textParser) {
        KKTextRange *oldTextRange = _selectedTextRange;
        NSRange newRange = _selectedTextRange.asRange;
        
        [_inputDelegate textWillChange:self];
        BOOL textChanged = [self.textParser parseText:_innerText selectedRange:&newRange];
        [_inputDelegate textDidChange:self];
        
        KKTextRange *newTextRange = [KKTextRange rangeWithRange:newRange];
        newTextRange = [self _correctedTextRange:newTextRange];
        
        if (![oldTextRange isEqual:newTextRange]) {
            [_inputDelegate selectionWillChange:self];
            _selectedTextRange = newTextRange;
            [_inputDelegate selectionDidChange:self];
        }
        return textChanged;
    }
    return NO;
}

/// Returns whether the text should be detected by the data detector.
- (BOOL)_shouldDetectText {
    if (!_dataDetector) return NO;
    if (!_highlightable) return NO;
    if (_linkTextAttributes.count == 0 && _highlightTextAttributes.count == 0) return NO;
    if (self.isFirstResponder || _containerView.isFirstResponder) return NO;
    return YES;
}

/// Detect the data in text and add highlight to the data range.
/// @return Whether detected.
- (BOOL)_detectText:(NSMutableAttributedString *)text {
    if (![self _shouldDetectText]) return NO;
    if (text.length == 0) return NO;
    __block BOOL detected = NO;
    [_dataDetector enumerateMatchesInString:text.string options:kNilOptions range:NSMakeRange(0, text.length) usingBlock: ^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        switch (result.resultType) {
            case NSTextCheckingTypeDate:
            case NSTextCheckingTypeAddress:
            case NSTextCheckingTypeLink:
            case NSTextCheckingTypePhoneNumber: {
                detected = YES;
                if (_highlightTextAttributes.count) {
                    KKTextHighlight *highlight = [KKTextHighlight highlightWithAttributes:_highlightTextAttributes];
                    [text kk_setTextHighlight:highlight range:result.range];
                }
                if (_linkTextAttributes.count) {
                    [_linkTextAttributes enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                        [text kk_setAttribute:key value:obj range:result.range];
                    }];
                }
            } break;
            default:
                break;
        }
    }];
    return detected;
}

/// Returns the `root` view controller (returns nil if not found).
- (UIViewController *)_getRootViewController {
    UIViewController *ctrl = nil;
    UIApplication *app = KKTextSharedApplication();
    if (!ctrl) ctrl = app.keyWindow.rootViewController;
    if (!ctrl) ctrl = [app.windows.firstObject rootViewController];
    if (!ctrl) ctrl = self.kk_viewController;
    if (!ctrl) return nil;
    
    while (!ctrl.view.window && ctrl.presentedViewController) {
        ctrl = ctrl.presentedViewController;
    }
    if (!ctrl.view.window) return nil;
    return ctrl;
}

/// Clear the undo and redo stack, and capture current state to undo stack.
- (void)_resetUndoAndRedoStack {
    [_undoStack removeAllObjects];
    [_redoStack removeAllObjects];
    _KKTextViewUndoObject *object = [_KKTextViewUndoObject objectWithText:_innerText.copy range:_selectedTextRange.asRange];
    _lastTypeRange = _selectedTextRange.asRange;
    [_undoStack addObject:object];
}

/// Clear the redo stack.
- (void)_resetRedoStack {
    [_redoStack removeAllObjects];
}

/// Capture current state to undo stack.
- (void)_saveToUndoStack {
    if (!_allowsUndoAndRedo) return;
    _KKTextViewUndoObject *lastObject = _undoStack.lastObject;
    if ([lastObject.text isEqualToAttributedString:self.attributedText]) return;
    
    _KKTextViewUndoObject *object = [_KKTextViewUndoObject objectWithText:_innerText.copy range:_selectedTextRange.asRange];
    _lastTypeRange = _selectedTextRange.asRange;
    [_undoStack addObject:object];
    while (_undoStack.count > _maximumUndoLevel) {
        [_undoStack removeObjectAtIndex:0];
    }
}

/// Capture current state to redo stack.
- (void)_saveToRedoStack {
    if (!_allowsUndoAndRedo) return;
    _KKTextViewUndoObject *lastObject = _redoStack.lastObject;
    if ([lastObject.text isEqualToAttributedString:self.attributedText]) return;
    
    _KKTextViewUndoObject *object = [_KKTextViewUndoObject objectWithText:_innerText.copy range:_selectedTextRange.asRange];
    [_redoStack addObject:object];
    while (_redoStack.count > _maximumUndoLevel) {
        [_redoStack removeObjectAtIndex:0];
    }
}

- (BOOL)_canUndo {
    if (_undoStack.count == 0) return NO;
    _KKTextViewUndoObject *object = _undoStack.lastObject;
    if ([object.text isEqualToAttributedString:_innerText]) return NO;
    return YES;
}

- (BOOL)_canRedo {
    if (_redoStack.count == 0) return NO;
    _KKTextViewUndoObject *object = _undoStack.lastObject;
    if ([object.text isEqualToAttributedString:_innerText]) return NO;
    return YES;
}

- (void)_undo {
    if (![self _canUndo]) return;
    [self _saveToRedoStack];
    _KKTextViewUndoObject *object = _undoStack.lastObject;
    [_undoStack removeLastObject];
    
    _state.insideUndoBlock = YES;
    self.attributedText = object.text;
    self.selectedRange = object.selectedRange;
    _state.insideUndoBlock = NO;
}

- (void)_redo {
    if (![self _canRedo]) return;
    [self _saveToUndoStack];
    _KKTextViewUndoObject *object = _redoStack.lastObject;
    [_redoStack removeLastObject];
    
    _state.insideUndoBlock = YES;
    self.attributedText = object.text;
    self.selectedRange = object.selectedRange;
    _state.insideUndoBlock = NO;
}

- (void)_restoreFirstResponderAfterUndoAlert {
    if (_state.firstResponderBeforeUndoAlert) {
        [self performSelector:@selector(becomeFirstResponder) withObject:nil afterDelay:0];
    }
}

/// Show undo alert if it can undo or redo.
#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
- (void)_showUndoRedoAlert NS_EXTENSION_UNAVAILABLE_IOS(""){
    _state.firstResponderBeforeUndoAlert = self.isFirstResponder;
    __weak typeof(self) _self = self;
    NSArray *strings = [self _localizedUndoStrings];
    BOOL canUndo = [self _canUndo];
    BOOL canRedo = [self _canRedo];
    
    UIViewController *ctrl = [self _getRootViewController];
    
    if (canUndo && canRedo) {
        if (kiOS8Later) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:strings[4] message:@"" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:strings[3] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [_self _undo];
                [_self _restoreFirstResponderAfterUndoAlert];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:strings[2] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [_self _redo];
                [_self _restoreFirstResponderAfterUndoAlert];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:strings[0] style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                [_self _restoreFirstResponderAfterUndoAlert];
            }]];
            [ctrl presentViewController:alert animated:YES completion:nil];
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:strings[4] message:@"" delegate:self cancelButtonTitle:strings[0] otherButtonTitles:strings[3], strings[2], nil];
            [alert show];
#pragma clang diagnostic pop
        }
    } else if (canUndo) {
        if (kiOS8Later) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:strings[4] message:@"" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:strings[3] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [_self _undo];
                [_self _restoreFirstResponderAfterUndoAlert];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:strings[0] style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                [_self _restoreFirstResponderAfterUndoAlert];
            }]];
            [ctrl presentViewController:alert animated:YES completion:nil];
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:strings[4] message:@"" delegate:self cancelButtonTitle:strings[0] otherButtonTitles:strings[3], nil];
            [alert show];
#pragma clang diagnostic pop
        }
    } else if (canRedo) {
        if (kiOS8Later) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:strings[2] message:@"" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:strings[1] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [_self _redo];
                [_self _restoreFirstResponderAfterUndoAlert];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:strings[0] style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                [_self _restoreFirstResponderAfterUndoAlert];
            }]];
            [ctrl presentViewController:alert animated:YES completion:nil];
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:strings[2] message:@"" delegate:self cancelButtonTitle:strings[0] otherButtonTitles:strings[1], nil];
            [alert show];
#pragma clang diagnostic pop
        }
    }
}
#endif

/// Get the localized undo alert strings based on app's main bundle.
- (NSArray *)_localizedUndoStrings {
    static NSArray *strings = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *dic = @{
            @"ar" : @[ @"إلغاء", @"إعادة", @"إعادة الكتابة", @"تراجع", @"تراجع عن الكتابة" ],
            @"ca" : @[ @"Cancel·lar", @"Refer", @"Refer l’escriptura", @"Desfer", @"Desfer l’escriptura" ],
            @"cs" : @[ @"Zrušit", @"Opakovat akci", @"Opakovat akci Psát", @"Odvolat akci", @"Odvolat akci Psát" ],
            @"da" : @[ @"Annuller", @"Gentag", @"Gentag Indtastning", @"Fortryd", @"Fortryd Indtastning" ],
            @"de" : @[ @"Abbrechen", @"Wiederholen", @"Eingabe wiederholen", @"Widerrufen", @"Eingabe widerrufen" ],
            @"el" : @[ @"Ακύρωση", @"Επανάληψη", @"Επανάληψη πληκτρολόγησης", @"Αναίρεση", @"Αναίρεση πληκτρολόγησης" ],
            @"en" : @[ @"Cancel", @"Redo", @"Redo Typing", @"Undo", @"Undo Typing" ],
            @"es" : @[ @"Cancelar", @"Rehacer", @"Rehacer escritura", @"Deshacer", @"Deshacer escritura" ],
            @"es_MX" : @[ @"Cancelar", @"Rehacer", @"Rehacer escritura", @"Deshacer", @"Deshacer escritura" ],
            @"fi" : @[ @"Kumoa", @"Tee sittenkin", @"Kirjoita sittenkin", @"Peru", @"Peru kirjoitus" ],
            @"fr" : @[ @"Annuler", @"Rétablir", @"Rétablir la saisie", @"Annuler", @"Annuler la saisie" ],
            @"he" : @[ @"ביטול", @"חזור על הפעולה האחרונה", @"חזור על הקלדה", @"בטל", @"בטל הקלדה" ],
            @"hr" : @[ @"Odustani", @"Ponovi", @"Ponovno upiši", @"Poništi", @"Poništi upisivanje" ],
            @"hu" : @[ @"Mégsem", @"Ismétlés", @"Gépelés ismétlése", @"Visszavonás", @"Gépelés visszavonása" ],
            @"id" : @[ @"Batalkan", @"Ulang", @"Ulang Pengetikan", @"Kembalikan", @"Batalkan Pengetikan" ],
            @"it" : @[ @"Annulla", @"Ripristina originale", @"Ripristina Inserimento", @"Annulla", @"Annulla Inserimento" ],
            @"ja" : @[ @"キャンセル", @"やり直す", @"やり直す - 入力", @"取り消す", @"取り消す - 入力" ],
            @"ko" : @[ @"취소", @"실행 복귀", @"입력 복귀", @"실행 취소", @"입력 실행 취소" ],
            @"ms" : @[ @"Batal", @"Buat semula", @"Ulang Penaipan", @"Buat asal", @"Buat asal Penaipan" ],
            @"nb" : @[ @"Avbryt", @"Utfør likevel", @"Utfør skriving likevel", @"Angre", @"Angre skriving" ],
            @"nl" : @[ @"Annuleer", @"Opnieuw", @"Opnieuw typen", @"Herstel", @"Herstel typen" ],
            @"pl" : @[ @"Anuluj", @"Przywróć", @"Przywróć Wpisz", @"Cofnij", @"Cofnij Wpisz" ],
            @"pt" : @[ @"Cancelar", @"Refazer", @"Refazer Digitação", @"Desfazer", @"Desfazer Digitação" ],
            @"pt_PT" : @[ @"Cancelar", @"Refazer", @"Refazer digitar", @"Desfazer", @"Desfazer digitar" ],
            @"ro" : @[ @"Renunță", @"Refă", @"Refă tastare", @"Anulează", @"Anulează tastare" ],
            @"ru" : @[ @"Отменить", @"Повторить", @"Повторить набор на клавиатуре", @"Отменить", @"Отменить набор на клавиатуре" ],
            @"sk" : @[ @"Zrušiť", @"Obnoviť", @"Obnoviť písanie", @"Odvolať", @"Odvolať písanie" ],
            @"sv" : @[ @"Avbryt", @"Gör om", @"Gör om skriven text", @"Ångra", @"Ångra skriven text" ],
            @"th" : @[ @"ยกเลิก", @"ทำกลับมาใหม่", @"ป้อนกลับมาใหม่", @"เลิกทำ", @"เลิกป้อน" ],
            @"tr" : @[ @"Vazgeç", @"Yinele", @"Yazmayı Yinele", @"Geri Al", @"Yazmayı Geri Al" ],
            @"uk" : @[ @"Скасувати", @"Повторити", @"Повторити введення", @"Відмінити", @"Відмінити введення" ],
            @"vi" : @[ @"Hủy", @"Làm lại", @"Làm lại thao tác Nhập", @"Hoàn tác", @"Hoàn tác thao tác Nhập" ],
            @"zh" : @[ @"取消", @"重做", @"重做键入", @"撤销", @"撤销键入" ],
            @"zh_CN" : @[ @"取消", @"重做", @"重做键入", @"撤销", @"撤销键入" ],
            @"zh_HK" : @[ @"取消", @"重做", @"重做輸入", @"還原", @"還原輸入" ],
            @"zh_TW" : @[ @"取消", @"重做", @"重做輸入", @"還原", @"還原輸入" ]
        };
        NSString *preferred = [[NSBundle mainBundle] preferredLocalizations].firstObject;
        if (preferred.length == 0) preferred = @"English";
        NSString *canonical = [NSLocale canonicalLocaleIdentifierFromString:preferred];
        if (canonical.length == 0) canonical = @"en";
        strings = dic[canonical];
        if (!strings  && ([canonical rangeOfString:@"_"].location != NSNotFound)) {
            NSString *prefix = [canonical componentsSeparatedByString:@"_"].firstObject;
            if (prefix.length) strings = dic[prefix];
        }
        if (!strings) strings = dic[@"en"];
    });
    return strings;
}

/// Returns the default font for text view (same as CoreText).
- (UIFont *)_defaultFont {
    return [UIFont systemFontOfSize:12];
}

/// Returns the default tint color for text view (used for caret and select range background).
- (UIColor *)_defaultTintColor {
    return [UIColor colorWithRed:69/255.0 green:111/255.0 blue:238/255.0 alpha:1];
}

/// Returns the default placeholder color for text view (same as UITextField).
- (UIColor *)_defaultPlaceholderColor {
    return [UIColor colorWithRed:0 green:0 blue:25/255.0 alpha:44/255.0];
}

#pragma mark - Private Setter

- (void)_setText:(NSString *)text {
    if (_text == text || [_text isEqualToString:text]) return;
    [self willChangeValueForKey:@"text"];
    _text = text.copy;
    if (!_text) _text = @"";
    [self didChangeValueForKey:@"text"];
    self.accessibilityLabel = _text;
}

- (void)_setFont:(UIFont *)font {
    if (_font == font || [_font isEqual:font]) return;
    [self willChangeValueForKey:@"font"];
    _font = font;
    [self didChangeValueForKey:@"font"];
}

- (void)_setTextColor:(UIColor *)textColor {
    if (_textColor == textColor) return;
    if (_textColor && textColor) {
        if (CFGetTypeID(_textColor.CGColor) == CFGetTypeID(textColor.CGColor) &&
            CFGetTypeID(_textColor.CGColor) == CGColorGetTypeID()) {
            if ([_textColor isEqual:textColor]) {
                return;
            }
        }
    }
    [self willChangeValueForKey:@"textColor"];
    _textColor = textColor;
    [self didChangeValueForKey:@"textColor"];
}

- (void)_setTextAlignment:(NSTextAlignment)textAlignment {
    if (_textAlignment == textAlignment) return;
    [self willChangeValueForKey:@"textAlignment"];
    _textAlignment = textAlignment;
    [self didChangeValueForKey:@"textAlignment"];
}

- (void)_setDataDetectorTypes:(UIDataDetectorTypes)dataDetectorTypes {
    if (_dataDetectorTypes == dataDetectorTypes) return;
    [self willChangeValueForKey:@"dataDetectorTypes"];
    _dataDetectorTypes = dataDetectorTypes;
    [self didChangeValueForKey:@"dataDetectorTypes"];
}

- (void)_setLinkTextAttributes:(NSDictionary *)linkTextAttributes {
    if (_linkTextAttributes == linkTextAttributes || [_linkTextAttributes isEqual:linkTextAttributes]) return;
    [self willChangeValueForKey:@"linkTextAttributes"];
    _linkTextAttributes = linkTextAttributes.copy;
    [self didChangeValueForKey:@"linkTextAttributes"];
}

- (void)_setHighlightTextAttributes:(NSDictionary *)highlightTextAttributes {
    if (_highlightTextAttributes == highlightTextAttributes || [_highlightTextAttributes isEqual:highlightTextAttributes]) return;
    [self willChangeValueForKey:@"highlightTextAttributes"];
    _highlightTextAttributes = highlightTextAttributes.copy;
    [self didChangeValueForKey:@"highlightTextAttributes"];
}
- (void)_setTextParser:(id<KKTextParser>)textParser {
    if (_textParser == textParser || [_textParser isEqual:textParser]) return;
    [self willChangeValueForKey:@"textParser"];
    _textParser = textParser;
    [self didChangeValueForKey:@"textParser"];
}

- (void)_setAttributedText:(NSAttributedString *)attributedText {
    if (_attributedText == attributedText || [_attributedText isEqual:attributedText]) return;
    [self willChangeValueForKey:@"attributedText"];
    _attributedText = attributedText.copy;
    if (!_attributedText) _attributedText = [NSAttributedString new];
    [self didChangeValueForKey:@"attributedText"];
}

- (void)_setTextContainerInset:(UIEdgeInsets)textContainerInset {
    if (UIEdgeInsetsEqualToEdgeInsets(_textContainerInset, textContainerInset)) return;
    [self willChangeValueForKey:@"textContainerInset"];
    _textContainerInset = textContainerInset;
    [self didChangeValueForKey:@"textContainerInset"];
}

- (void)_setExclusionPaths:(NSArray *)exclusionPaths {
    if (_exclusionPaths == exclusionPaths || [_exclusionPaths isEqual:exclusionPaths]) return;
    [self willChangeValueForKey:@"exclusionPaths"];
    _exclusionPaths = exclusionPaths.copy;
    [self didChangeValueForKey:@"exclusionPaths"];
}

- (void)_setVerticalForm:(BOOL)verticalForm {
    if (_verticalForm == verticalForm) return;
    [self willChangeValueForKey:@"verticalForm"];
    _verticalForm = verticalForm;
    [self didChangeValueForKey:@"verticalForm"];
}

- (void)_setLinePositionModifier:(id<KKTextLinePositionModifier>)linePositionModifier {
    if (_linePositionModifier == linePositionModifier) return;
    [self willChangeValueForKey:@"linePositionModifier"];
    _linePositionModifier = [(NSObject *)linePositionModifier copy];
    [self didChangeValueForKey:@"linePositionModifier"];
}

- (void)_setSelectedRange:(NSRange)selectedRange {
    if (NSEqualRanges(_selectedRange, selectedRange)) return;
    [self willChangeValueForKey:@"selectedRange"];
    _selectedRange = selectedRange;
    [self didChangeValueForKey:@"selectedRange"];
    if ([self.delegate respondsToSelector:@selector(textViewDidChangeSelection:)]) {
        [self.delegate textViewDidChangeSelection:self];
    }
}

- (void)_setTypingAttributes:(NSDictionary *)typingAttributes {
    if (_typingAttributes == typingAttributes || [_typingAttributes isEqual:typingAttributes]) return;
    [self willChangeValueForKey:@"typingAttributes"];
    _typingAttributes = typingAttributes.copy;
    [self didChangeValueForKey:@"typingAttributes"];
}

#pragma mark - Private Init

- (void)_initTextView {
    self.delaysContentTouches = NO;
    self.canCancelContentTouches = YES;
    self.multipleTouchEnabled = NO;
    self.clipsToBounds = YES;
    [super setDelegate:self];
    
    _text = @"";
    _attributedText = [NSAttributedString new];
    
    // UITextInputTraits
    _autocapitalizationType = UITextAutocapitalizationTypeSentences;
    _autocorrectionType = UITextAutocorrectionTypeDefault;
    _spellCheckingType = UITextSpellCheckingTypeDefault;
    _keyboardType = UIKeyboardTypeDefault;
    _keyboardAppearance = UIKeyboardAppearanceDefault;
    _returnKeyType = UIReturnKeyDefault;
    _enablesReturnKeyAutomatically = NO;
    _secureTextEntry = NO;
    
    // UITextInput
    _selectedTextRange = [KKTextRange defaultRange];
    _markedTextRange = nil;
    _markedTextStyle = nil;
    _tokenizer = [[UITextInputStringTokenizer alloc] initWithTextInput:self];
    
    _editable = YES;
    _selectable = YES;
    _highlightable = YES;
    _allowsCopyAttributedString = YES;
    _textAlignment = NSTextAlignmentNatural;
    
    _innerText = [NSMutableAttributedString new];
    _paragraphContexts = [NSMutableArray new];
    _innerContainer = [KKTextContainer new];
    _innerContainer.insets = kDefaultInset;
    _textContainerInset = kDefaultInset;
    _typingAttributesHolder = [[NSMutableAttributedString alloc] initWithString:@" "];
    _linkTextAttributes = @{NSForegroundColorAttributeName : [self _defaultTintColor],
                            (id)kCTForegroundColorAttributeName : (id)[self _defaultTintColor].CGColor};
    
    KKTextHighlight *highlight = [KKTextHighlight new];
    KKTextBorder * border = [KKTextBorder new];
    border.insets = UIEdgeInsetsMake(-2, -2, -2, -2);
    border.fillColor = [UIColor colorWithWhite:0.1 alpha:0.2];
    border.cornerRadius = 3;
    [highlight setBorder:border];
    _highlightTextAttributes = highlight.attributes.copy;
    
    _placeHolderView = [UIImageView new];
    _placeHolderView.userInteractionEnabled = NO;
    _placeHolderView.hidden = YES;
    
    _containerView = [KKTextContainerView new];
    _containerView.hostView = self;
    
    _selectionView = [KKTextSelectionView new];
    _selectionView.userInteractionEnabled = NO;
    _selectionView.hostView = self;
    _selectionView.color = [self _defaultTintColor];
    
    _magnifierCaret = [KKTextMagnifier magnifierWithType:KKTextMagnifierTypeCaret];
    _magnifierCaret.hostView = _containerView;
    _magnifierRanged = [KKTextMagnifier magnifierWithType:KKTextMagnifierTypeRanged];
    _magnifierRanged.hostView = _containerView;
    
    [self addSubview:_placeHolderView];
    [self addSubview:_containerView];
    [self addSubview:_selectionView];
    
    _undoStack = [NSMutableArray new];
    _redoStack = [NSMutableArray new];
    _allowsUndoAndRedo = YES;
    _maximumUndoLevel = kDefaultUndoLevelMax;
    
    self.debugOption = [KKTextDebugOption sharedDebugOption];
    [KKTextDebugOption addDebugTarget:self];
    
    [self _updateInnerContainerSize];
    [self _update];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_pasteboardChanged) name:UIPasteboardChangedNotification object:nil];
    [[KKTextKeyboardManager defaultManager] addObserver:self];
    
    self.isAccessibilityElement = YES;
}

#pragma mark - Public

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    [self _initTextView];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIPasteboardChangedNotification object:nil];
    [[KKTextKeyboardManager defaultManager] removeObserver:self];
    
    [[KKTextEffectWindow sharedWindow] hideSelectionDot:_selectionView];
    [[KKTextEffectWindow sharedWindow] hideMagnifier:_magnifierCaret];
    [[KKTextEffectWindow sharedWindow] hideMagnifier:_magnifierRanged];
    
    [KKTextDebugOption removeDebugTarget:self];
    
    [_longPressTimer invalidate];
    [_autoScrollTimer invalidate];
    [_selectionDotFixTimer invalidate];
}

- (void)scrollRangeToVisible:(NSRange)range {
    KKTextRange *textRange = [KKTextRange rangeWithRange:range];
    textRange = [self _correctedTextRange:textRange];
    [self _scrollRangeToVisible:textRange];
}

#pragma mark - Property

- (void)setText:(NSString *)text {
    if (_text == text || [_text isEqualToString:text]) return;
    [self _setText:text];
    
    _state.selectedWithoutEdit = NO;
    _state.deleteConfirm = NO;
    [self _endTouchTracking];
    [self _hideMenu];
    [self _resetUndoAndRedoStack];
    [self replaceRange:[KKTextRange rangeWithRange:NSMakeRange(0, _innerText.length)] withText:text];
}

- (void)setFont:(UIFont *)font {
    if (_font == font || [_font isEqual:font]) return;
    [self _setFont:font];
    
    _state.typingAttributesOnce = NO;
    _typingAttributesHolder.kk_font = font;
    _innerText.kk_font = font;
    [self _resetUndoAndRedoStack];
    [self _commitUpdate];
}

- (void)setTextColor:(UIColor *)textColor {
    if (_textColor == textColor || [_textColor isEqual:textColor]) return;
    [self _setTextColor:textColor];
    
    _state.typingAttributesOnce = NO;
    _typingAttributesHolder.kk_color = textColor;
    _innerText.kk_color = textColor;
    [self _resetUndoAndRedoStack];
    [self _commitUpdate];
}

- (void)setTextAlignment:(NSTextAlignment)textAlignment {
    if (_textAlignment == textAlignment) return;
    [self _setTextAlignment:textAlignment];
    
    _typingAttributesHolder.kk_alignment = textAlignment;
    _innerText.kk_alignment = textAlignment;
    [self _resetUndoAndRedoStack];
    [self _commitUpdate];
}

- (void)setDataDetectorTypes:(UIDataDetectorTypes)dataDetectorTypes {
    if (_dataDetectorTypes == dataDetectorTypes) return;
    [self _setDataDetectorTypes:dataDetectorTypes];
    NSTextCheckingType type = KKTextNSTextCheckingTypeFromUIDataDetectorType(dataDetectorTypes);
    _dataDetector = type ? [NSDataDetector dataDetectorWithTypes:type error:NULL] : nil;
    [self _resetUndoAndRedoStack];
    [self _commitUpdate];
}

- (void)setLinkTextAttributes:(NSDictionary *)linkTextAttributes {
    if (_linkTextAttributes == linkTextAttributes || [_linkTextAttributes isEqual:linkTextAttributes]) return;
    [self _setLinkTextAttributes:linkTextAttributes];
    if (_dataDetector) {
        [self _commitUpdate];
    }
}

- (void)setHighlightTextAttributes:(NSDictionary *)highlightTextAttributes {
    if (_highlightTextAttributes == highlightTextAttributes || [_highlightTextAttributes isEqual:highlightTextAttributes]) return;
    [self _setHighlightTextAttributes:highlightTextAttributes];
    if (_dataDetector) {
        [self _commitUpdate];
    }
}

- (void)setTextParser:(id<KKTextParser>)textParser {
    if (_textParser == textParser || [_textParser isEqual:textParser]) return;
    [self _setTextParser:textParser];
    if (textParser && _text.length) {
        [self replaceRange:[KKTextRange rangeWithRange:NSMakeRange(0, _text.length)] withText:_text];
    }
    [self _resetUndoAndRedoStack];
    [self _commitUpdate];
}

- (void)setTypingAttributes:(NSDictionary *)typingAttributes {
    [self _setTypingAttributes:typingAttributes];
    _state.typingAttributesOnce = YES;
    [typingAttributes enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [_typingAttributesHolder kk_setAttribute:key value:obj];
    }];
    [self _commitUpdate];
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    if (_attributedText == attributedText) return;
    [self _setAttributedText:attributedText];
    _state.typingAttributesOnce = NO;
    
    NSMutableAttributedString *text = attributedText.mutableCopy;
    if (text.length == 0) {
        [self replaceRange:[KKTextRange rangeWithRange:NSMakeRange(0, _innerText.length)] withText:@""];
        return;
    }
    if ([self.delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]) {
        BOOL should = [self.delegate textView:self shouldChangeTextInRange:NSMakeRange(0, _innerText.length) replacementText:text.string];
        if (!should) return;
    }
    
    _state.selectedWithoutEdit = NO;
    _state.deleteConfirm = NO;
    [self _endTouchTracking];
    [self _hideMenu];
    
    [_inputDelegate selectionWillChange:self];
    [_inputDelegate textWillChange:self];
     _innerText = text;
    [self _parseText];
    _selectedTextRange = [KKTextRange rangeWithRange:NSMakeRange(0, _innerText.length)];
    [_inputDelegate textDidChange:self];
    [_inputDelegate selectionDidChange:self];
    
    [self _setAttributedText:text];
    if (_innerText.length > 0) {
        _typingAttributesHolder.kk_attributes = [_innerText kk_attributesAtIndex:_innerText.length - 1];
    }
    
    [self _updateOuterProperties];
    [self _updateLayout];
    [self _updateSelectionView];
    
    if (self.isFirstResponder) {
        [self _scrollRangeToVisible:_selectedTextRange];
    }
    
    if ([self.delegate respondsToSelector:@selector(textViewDidChange:)]) {
        [self.delegate textViewDidChange:self];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:KKTextViewTextDidChangeNotification object:self];
    
    if (!_state.insideUndoBlock) {
        [self _resetUndoAndRedoStack];
    }
}

- (void)setTextVerticalAlignment:(KKTextVerticalAlignment)textVerticalAlignment {
    if (_textVerticalAlignment == textVerticalAlignment) return;
    [self willChangeValueForKey:@"textVerticalAlignment"];
    _textVerticalAlignment = textVerticalAlignment;
    [self didChangeValueForKey:@"textVerticalAlignment"];
    _containerView.textVerticalAlignment = textVerticalAlignment;
    [self _commitUpdate];
}

- (void)setTextContainerInset:(UIEdgeInsets)textContainerInset {
    if (UIEdgeInsetsEqualToEdgeInsets(_textContainerInset, textContainerInset)) return;
    [self _setTextContainerInset:textContainerInset];
    _innerContainer.insets = textContainerInset;
    [self _commitUpdate];
}

- (void)setExclusionPaths:(NSArray *)exclusionPaths {
    if (_exclusionPaths == exclusionPaths || [_exclusionPaths isEqual:exclusionPaths]) return;
    [self _setExclusionPaths:exclusionPaths];
    _innerContainer.exclusionPaths = exclusionPaths;
    if (_innerContainer.isVerticalForm) {
        CGAffineTransform trans = CGAffineTransformMakeTranslation(_innerContainer.size.width - self.bounds.size.width, 0);
        [_innerContainer.exclusionPaths enumerateObjectsUsingBlock:^(UIBezierPath *path, NSUInteger idx, BOOL *stop) {
            [path applyTransform:trans];
        }];
    }
    [self _commitUpdate];
}

- (void)setVerticalForm:(BOOL)verticalForm {
    if (_verticalForm == verticalForm) return;
    [self _setVerticalForm:verticalForm];
    _innerContainer.verticalForm = verticalForm;
    _selectionView.verticalForm = verticalForm;
    
    [self _updateInnerContainerSize];
    
    if (verticalForm) {
        if (UIEdgeInsetsEqualToEdgeInsets(_innerContainer.insets, kDefaultInset)) {
            _innerContainer.insets = kDefaultVerticalInset;
            [self _setTextContainerInset:kDefaultVerticalInset];
        }
    } else {
        if (UIEdgeInsetsEqualToEdgeInsets(_innerContainer.insets, kDefaultVerticalInset)) {
            _innerContainer.insets = kDefaultInset;
            [self _setTextContainerInset:kDefaultInset];
        }
    }
    
    _innerContainer.exclusionPaths = _exclusionPaths;
    if (verticalForm) {
        CGAffineTransform trans = CGAffineTransformMakeTranslation(_innerContainer.size.width - self.bounds.size.width, 0);
        [_innerContainer.exclusionPaths enumerateObjectsUsingBlock:^(UIBezierPath *path, NSUInteger idx, BOOL *stop) {
            [path applyTransform:trans];
        }];
    }
    
    [self _keyboardChanged];
    [self _commitUpdate];
}

- (void)setLinePositionModifier:(id<KKTextLinePositionModifier>)linePositionModifier {
    if (_linePositionModifier == linePositionModifier) return;
    [self _setLinePositionModifier:linePositionModifier];
    _innerContainer.linePositionModifier = linePositionModifier;
    [self _commitUpdate];
}

- (void)setSelectedRange:(NSRange)selectedRange {
    if (NSEqualRanges(_selectedRange, selectedRange)) return;
    if (_markedTextRange) return;
    _state.typingAttributesOnce = NO;
    
    KKTextRange *range = [KKTextRange rangeWithRange:selectedRange];
    range = [self _correctedTextRange:range];
    [self _endTouchTracking];
    _selectedTextRange = range;
    [self _updateSelectionView];
    
    [self _setSelectedRange:range.asRange];
    
    if (!_state.insideUndoBlock) {
        [self _resetUndoAndRedoStack];
    }
}

- (void)setHighlightable:(BOOL)highlightable {
    if (_highlightable == highlightable) return;
    [self willChangeValueForKey:@"highlightable"];
    _highlightable = highlightable;
    [self didChangeValueForKey:@"highlightable"];
    [self _commitUpdate];
}

- (void)setEditable:(BOOL)editable {
    if (_editable == editable) return;
    [self willChangeValueForKey:@"editable"];
    _editable = editable;
    [self didChangeValueForKey:@"editable"];
    if (!editable) {
        [self resignFirstResponder];
    }
}

- (void)setSelectable:(BOOL)selectable {
    if (_selectable == selectable) return;
    [self willChangeValueForKey:@"selectable"];
    _selectable = selectable;
    [self didChangeValueForKey:@"selectable"];
    if (!selectable) {
        if (self.isFirstResponder) {
            [self resignFirstResponder];
        } else {
            _state.selectedWithoutEdit = NO;
            [self _endTouchTracking];
            [self _hideMenu];
            [self _updateSelectionView];
        }
    }
}

- (void)setClearsOnInsertion:(BOOL)clearsOnInsertion {
    if (_clearsOnInsertion == clearsOnInsertion) return;
    _clearsOnInsertion = clearsOnInsertion;
    if (clearsOnInsertion) {
        if (self.isFirstResponder) {
            self.selectedRange = NSMakeRange(0, _attributedText.length);
        } else {
            _state.clearsOnInsertionOnce = YES;
        }
    }
}

- (void)setDebugOption:(KKTextDebugOption *)debugOption {
    _containerView.debugOption = debugOption;
    for (_KKTextViewParagraphContext *context in _paragraphContexts) {
        context.contentView.debugOption = debugOption;
    }
}

- (KKTextDebugOption *)debugOption {
    return _containerView.debugOption;
}

- (KKTextLayout *)textLayout {
    [self _updateIfNeeded];
    return nil;
}

- (void)setPlaceholderText:(NSString *)placeholderText {
    if (_placeholderAttributedText.length > 0) {
        if (placeholderText.length > 0) {
            [((NSMutableAttributedString *)_placeholderAttributedText) replaceCharactersInRange:NSMakeRange(0, _placeholderAttributedText.length) withString:placeholderText];
        } else {
            [((NSMutableAttributedString *)_placeholderAttributedText) replaceCharactersInRange:NSMakeRange(0, _placeholderAttributedText.length) withString:@""];
        }
        ((NSMutableAttributedString *)_placeholderAttributedText).kk_font = _placeholderFont;
        ((NSMutableAttributedString *)_placeholderAttributedText).kk_color = _placeholderTextColor;
    } else {
        if (placeholderText.length > 0) {
            NSMutableAttributedString *atr = [[NSMutableAttributedString alloc] initWithString:placeholderText];
            if (!_placeholderFont) _placeholderFont = _font;
            if (!_placeholderFont) _placeholderFont = [self _defaultFont];
            if (!_placeholderTextColor) _placeholderTextColor = [self _defaultPlaceholderColor];
            atr.kk_font = _placeholderFont;
            atr.kk_color = _placeholderTextColor;
            _placeholderAttributedText = atr;
        }
    }
    _placeholderText = [_placeholderAttributedText kk_plainTextForRange:NSMakeRange(0, _placeholderAttributedText.length)];
    [self _commitPlaceholderUpdate];
}

- (void)setPlaceholderFont:(UIFont *)placeholderFont {
    _placeholderFont = placeholderFont;
    ((NSMutableAttributedString *)_placeholderAttributedText).kk_font = _placeholderFont;
    [self _commitPlaceholderUpdate];
}

- (void)setPlaceholderTextColor:(UIColor *)placeholderTextColor {
    _placeholderTextColor = placeholderTextColor;
    ((NSMutableAttributedString *)_placeholderAttributedText).kk_color = _placeholderTextColor;
    [self _commitPlaceholderUpdate];
}

- (void)setPlaceholderAttributedText:(NSAttributedString *)placeholderAttributedText {
    _placeholderAttributedText = placeholderAttributedText.mutableCopy;
    _placeholderText = [_placeholderAttributedText kk_plainTextForRange:NSMakeRange(0, _placeholderAttributedText.length)];
    _placeholderFont = _placeholderAttributedText.kk_font;
    _placeholderTextColor = _placeholderAttributedText.kk_color;
    [self _commitPlaceholderUpdate];
}

#pragma mark - Override For Protect

- (void)setMultipleTouchEnabled:(BOOL)multipleTouchEnabled {
    [super setMultipleTouchEnabled:NO]; // must not enabled
}

- (void)setContentInset:(UIEdgeInsets)contentInset {
    UIEdgeInsets oldInsets = self.contentInset;
    if (_insetModifiedByKeyboard) {
        _originalContentInset = contentInset;
    } else {
        [super setContentInset:contentInset];
        BOOL changed = !UIEdgeInsetsEqualToEdgeInsets(oldInsets, contentInset);
        if (changed) {
            [self _updateInnerContainerSize];
            [self _commitUpdate];
            [self _commitPlaceholderUpdate];
        }
    }
}

- (void)setScrollIndicatorInsets:(UIEdgeInsets)scrollIndicatorInsets {
    if (_insetModifiedByKeyboard) {
        _originalScrollIndicatorInsets = scrollIndicatorInsets;
    } else {
        [super setScrollIndicatorInsets:scrollIndicatorInsets];
    }
}

- (void)setFrame:(CGRect)frame {
    CGSize oldSize = self.bounds.size;
    [super setFrame:frame];
    CGSize newSize = self.bounds.size;
    BOOL changed = _innerContainer.isVerticalForm ? (oldSize.height != newSize.height) : (oldSize.width != newSize.width);
    if (changed) {
        [self _updateInnerContainerSize];
        [self _commitUpdate];
    }
    if (!CGSizeEqualToSize(oldSize, newSize)) {
        [self _commitPlaceholderUpdate];
    }
}

- (void)setBounds:(CGRect)bounds {
    CGSize oldSize = self.bounds.size;
    [super setBounds:bounds];
    CGSize newSize = self.bounds.size;
    BOOL changed = _innerContainer.isVerticalForm ? (oldSize.height != newSize.height) : (oldSize.width != newSize.width);
    if (changed) {
        [self _updateInnerContainerSize];
        [self _commitUpdate];
    }
    if (!CGSizeEqualToSize(oldSize, newSize)) {
        [self _commitPlaceholderUpdate];
    }
}

- (void)tintColorDidChange {
    if ([self respondsToSelector:@selector(tintColor)]) {
        UIColor *color = self.tintColor;
        NSMutableDictionary *attrs = _highlightTextAttributes.mutableCopy;
        NSMutableDictionary *linkAttrs = _linkTextAttributes.mutableCopy;
        if (!linkAttrs) linkAttrs = @{}.mutableCopy;
        if (!color) {
            [attrs removeObjectForKey:NSForegroundColorAttributeName];
            [attrs removeObjectForKey:(id)kCTForegroundColorAttributeName];
            [linkAttrs setObject:[self _defaultTintColor] forKey:NSForegroundColorAttributeName];
            [linkAttrs setObject:(id)[self _defaultTintColor].CGColor forKey:(id)kCTForegroundColorAttributeName];
        } else {
            [attrs setObject:color forKey:NSForegroundColorAttributeName];
            [attrs setObject:(id)color.CGColor forKey:(id)kCTForegroundColorAttributeName];
            [linkAttrs setObject:color forKey:NSForegroundColorAttributeName];
            [linkAttrs setObject:(id)color.CGColor forKey:(id)kCTForegroundColorAttributeName];
        }
        self.highlightTextAttributes = attrs;
        _selectionView.color = color ? color : [self _defaultTintColor];
        _linkTextAttributes = linkAttrs;
        [self _commitUpdate];
    }
}

- (CGSize)sizeThatFits:(CGSize)size {
    if (!_verticalForm && size.width <= 0) size.width = KKTextContainerMaxSize.width;
    if (_verticalForm && size.height <= 0) size.height = KKTextContainerMaxSize.height;
    
    if ((!_verticalForm && size.width == self.bounds.size.width) ||
        (_verticalForm && size.height == self.bounds.size.height)) {
        [self _updateIfNeeded];
        if (!_verticalForm) {
            if (_containerView.bounds.size.height <= size.height) {
                return _containerView.bounds.size;
            }
        } else {
            if (_containerView.bounds.size.width <= size.width) {
                return _containerView.bounds.size;
            }
        }
    }
    
    if (!_verticalForm) {
        size.height = KKTextContainerMaxSize.height;
    } else {
        size.width = KKTextContainerMaxSize.width;
    }
    
    KKTextContainer *container = [_innerContainer copy];
    container.size = size;
    
    KKTextLayout *layout = [KKTextLayout layoutWithContainer:container text:_innerText];
    return layout.textBoundingSize;
}

#pragma mark - Override UIResponder

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [self _updateIfNeeded];
    UITouch *touch = touches.anyObject;
    CGPoint point = [touch locationInView:_containerView];
    
    _touchBeganTime = _trackingTime = touch.timestamp;
    _touchBeganPoint = _trackingPoint = point;
    _trackingRange = _selectedTextRange;
    
    _state.trackingGrabber = NO;
    _state.trackingCaret = NO;
    _state.trackingPreSelect = NO;
    _state.trackingTouch = YES;
    _state.swallowTouch = YES;
    _state.touchMoved = NO;
    
    if (!self.isFirstResponder && !_state.selectedWithoutEdit && self.highlightable) {
        _highlight = [self _getHighlightAtPoint:point range:&_highlightRange];
    }
    
    if ((!self.selectable && !_highlight) || _state.ignoreTouchBegan) {
        _state.swallowTouch = NO;
        _state.trackingTouch = NO;
    }
    
    if (_state.trackingTouch) {
        [self _startLongPressTimer];
        if (_highlight) {
            [self _showHighlightAnimated:NO];
        } else {
            if ([_selectionView isGrabberContainsPoint:point]) { // track grabber
                self.panGestureRecognizer.enabled = NO; // disable scroll view
                [self _hideMenu];
                _state.trackingGrabber = [_selectionView isStartGrabberContainsPoint:point] ? kStart : kEnd;
                _magnifierRangedOffset = [self _getMagnifierRangedOffset];
            } else {
                if (_selectedTextRange.asRange.length == 0 && self.isFirstResponder) {
                    if ([_selectionView isCaretContainsPoint:point]) { // track caret
                        _state.trackingCaret = YES;
                        self.panGestureRecognizer.enabled = NO; // disable scroll view
                    }
                }
            }
        }
        [self _updateSelectionView];
    }
    
    if (!_state.swallowTouch) [super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    [self _updateIfNeeded];
    UITouch *touch = touches.anyObject;
    CGPoint point = [touch locationInView:_containerView];
    
    _trackingTime = touch.timestamp;
    _trackingPoint = point;
    
    if (!_state.touchMoved) {
        _state.touchMoved = [self _getMoveDirection];
        if (_state.touchMoved) [self _endLongPressTimer];
    }
    _state.clearsOnInsertionOnce = NO;
    
    if (_state.trackingTouch) {
        BOOL showMagnifierCaret = NO;
        BOOL showMagnifierRanged = NO;
        
        if (_highlight) {
            
            KKTextHighlight *highlight = [self _getHighlightAtPoint:_trackingPoint range:NULL];
            if (highlight == _highlight) {
                [self _showHighlightAnimated:YES];
            } else {
                [self _hideHighlightAnimated:YES];
            }
            
        } else {
            _trackingRange = _selectedTextRange;
            if (_state.trackingGrabber) {
                self.panGestureRecognizer.enabled = NO;
                [self _hideMenu];
                [self _updateTextRangeByTrackingGrabber];
                showMagnifierRanged = YES;
            } else if (_state.trackingPreSelect) {
                self.panGestureRecognizer.enabled = NO;
                [self _updateTextRangeByTrackingPreSelect];
                showMagnifierCaret = YES;
            } else if (_state.trackingCaret || _markedTextRange || self.isFirstResponder) {
                if (_state.trackingCaret || _state.touchMoved) {
                    _state.trackingCaret = YES;
                    [self _hideMenu];
                    if (_verticalForm) {
                        if (_state.touchMoved == kTop || _state.touchMoved == kBottom) {
                            self.panGestureRecognizer.enabled = NO;
                        }
                    } else {
                        if (_state.touchMoved == kLeft || _state.touchMoved == kRight) {
                            self.panGestureRecognizer.enabled = NO;
                        }
                    }
                    [self _updateTextRangeByTrackingCaret];
                    if (_markedTextRange) {
                        showMagnifierRanged = YES;
                    } else {
                        showMagnifierCaret = YES;
                    }
                }
            }
        }
        [self _updateSelectionView];
        if (showMagnifierCaret) [self _showMagnifierCaret];
        if (showMagnifierRanged) [self _showMagnifierRanged];
    }
    
    CGFloat autoScrollOffset = [self _getAutoscrollOffset];
    if (_autoScrollOffset != autoScrollOffset) {
        if (fabs(autoScrollOffset) < fabs(_autoScrollOffset)) {
            _autoScrollAcceleration *= 0.5;
        }
        _autoScrollOffset = autoScrollOffset;
        if (_autoScrollOffset != 0 && _state.touchMoved) {
            [self _startAutoScrollTimer];
        }
    }
    
    if (!_state.swallowTouch) [super touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [self _updateIfNeeded];
    
    UITouch *touch = touches.anyObject;
    CGPoint point = [touch locationInView:_containerView];
    
    _trackingTime = touch.timestamp;
    _trackingPoint = point;
    
    if (!_state.touchMoved) {
        _state.touchMoved = [self _getMoveDirection];
    }
    if (_state.trackingTouch) {
        [self _hideMagnifier];
        
        if (_highlight) {
            if (_state.showingHighlight) {
                if (_highlight.tapAction) {
                    CGRect rect = [self _rectForTextRange:[KKTextRange rangeWithRange:_highlightRange]];
                    _highlight.tapAction(self, _innerText, _highlightRange, rect);
                } else {
                    BOOL shouldTap = YES;
                    if ([self.delegate respondsToSelector:@selector(textView:shouldTapHighlight:inRange:)]) {
                        shouldTap = [self.delegate textView:self shouldTapHighlight:_highlight inRange:_highlightRange];
                    }
                    if (shouldTap && [self.delegate respondsToSelector:@selector(textView:didTapHighlight:inRange:rect:)]) {
                        CGRect rect = [self _rectForTextRange:[KKTextRange rangeWithRange:_highlightRange]];
                        [self.delegate textView:self didTapHighlight:_highlight inRange:_highlightRange rect:rect];
                    }
                }
                [self _removeHighlightAnimated:YES];
            }
        } else {
            if (_state.trackingCaret) {
                if (_state.touchMoved) {
                    [self _updateTextRangeByTrackingCaret];
                    [self _showMenu];
                } else {
                    if (_state.showingMenu) [self _hideMenu];
                    else [self _showMenu];
                }
            } else if (_state.trackingGrabber) {
                [self _updateTextRangeByTrackingGrabber];
                [self _showMenu];
            } else if (_state.trackingPreSelect) {
                [self _updateTextRangeByTrackingPreSelect];
                if (_trackingRange.asRange.length > 0) {
                    _state.selectedWithoutEdit = YES;
                    [self _showMenu];
                } else {
                    [self performSelector:@selector(becomeFirstResponder) withObject:nil afterDelay:0];
                }
            } else if (_state.deleteConfirm || _markedTextRange) {
                [self _updateTextRangeByTrackingCaret];
                [self _hideMenu];
            } else {
                if (!_state.touchMoved) {
                    if (_state.selectedWithoutEdit) {
                        _state.selectedWithoutEdit = NO;
                        [self _hideMenu];
                    } else {
                        if (self.isFirstResponder) {
                            KKTextRange *_oldRange = _trackingRange;
                            [self _updateTextRangeByTrackingCaret];
                            if ([_oldRange isEqual:_trackingRange]) {
                                if (_state.showingMenu) [self _hideMenu];
                                else [self _showMenu];
                            } else {
                                [self _hideMenu];
                            }
                        } else {
                            [self _hideMenu];
                            if (_state.clearsOnInsertionOnce) {
                                _state.clearsOnInsertionOnce = NO;
                                _selectedTextRange = [KKTextRange rangeWithRange:NSMakeRange(0, _innerText.length)];
                                [self _setSelectedRange:_selectedTextRange.asRange];
                            } else {
                                [self _updateTextRangeByTrackingCaret];
                            }
                            [self performSelector:@selector(becomeFirstResponder) withObject:nil afterDelay:0];
                        }
                    }
                }
            }
        }
        
        if (_trackingRange && (![_trackingRange isEqual:_selectedTextRange] || _state.trackingPreSelect)) {
            if (![_trackingRange isEqual:_selectedTextRange]) {
                [_inputDelegate selectionWillChange:self];
                _selectedTextRange = _trackingRange;
                [_inputDelegate selectionDidChange:self];
                [self _updateAttributesHolder];
                [self _updateOuterProperties];
            }
            if (!_state.trackingGrabber && !_state.trackingPreSelect) {
                [self _scrollRangeToVisible:_selectedTextRange];
            }
        }
        
        [self _endTouchTracking];
    }
    
    if (!_state.swallowTouch) [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [self _endTouchTracking];
    [self _hideMenu];

    if (!_state.swallowTouch) [super touchesCancelled:touches withEvent:event];
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake && _allowsUndoAndRedo) {
        if (!KKTextIsAppExtension()) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
            [self performSelector:@selector(_showUndoRedoAlert)];
#pragma clang diagnostic pop
        }
    } else {
        [super motionEnded:motion withEvent:event];
    }
}

- (BOOL)canBecomeFirstResponder {
    if (!self.isSelectable) return NO;
    if (!self.isEditable) return NO;
    if (_state.ignoreFirstResponder) return NO;
    if ([self.delegate respondsToSelector:@selector(textViewShouldBeginEditing:)]) {
        if (![self.delegate textViewShouldBeginEditing:self]) return NO;
    }
    return YES;
}

- (BOOL)becomeFirstResponder {
    BOOL isFirstResponder = self.isFirstResponder;
    if (isFirstResponder) return YES;
    BOOL shouldDetectData = [self _shouldDetectText];
    BOOL become = [super becomeFirstResponder];
    if (!isFirstResponder && become) {
        [self _endTouchTracking];
        [self _hideMenu];
        
        _state.selectedWithoutEdit = NO;
        if (shouldDetectData != [self _shouldDetectText]) {
            [self _update];
        }
        [self _updateIfNeeded];
        [self _updateSelectionView];
        [self performSelector:@selector(_scrollSelectedRangeToVisible) withObject:nil afterDelay:0];
        if ([self.delegate respondsToSelector:@selector(textViewDidBeginEditing:)]) {
            [self.delegate textViewDidBeginEditing:self];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:KKTextViewTextDidBeginEditingNotification object:self];
    }
    return become;
}

- (BOOL)canResignFirstResponder {
    if (!self.isFirstResponder) return YES;
    if ([self.delegate respondsToSelector:@selector(textViewShouldEndEditing:)]) {
        if (![self.delegate textViewShouldEndEditing:self]) return NO;
    }
    return YES;
}

- (BOOL)resignFirstResponder {
    BOOL isFirstResponder = self.isFirstResponder;
    if (!isFirstResponder) return YES;
    BOOL resign = [super resignFirstResponder];
    if (resign) {
        if (_markedTextRange) {
            _markedTextRange = nil;
            [self _parseText];
            [self _setText:[_innerText kk_plainTextForRange:NSMakeRange(0, _innerText.length)]];
        }
        _state.selectedWithoutEdit = NO;
        if ([self _shouldDetectText]) {
            [self _update];
        }
        [self _endTouchTracking];
        [self _hideMenu];
        [self _updateIfNeeded];
        [self _updateSelectionView];
        [self _restoreInsetsAnimated:YES];
        if ([self.delegate respondsToSelector:@selector(textViewDidEndEditing:)]) {
            [self.delegate textViewDidEndEditing:self];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:KKTextViewTextDidEndEditingNotification object:self];
    }
    return resign;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    /*
     ------------------------------------------------------
     Default menu actions list:
     cut:                                   Cut
     copy:                                  Copy
     select:                                Select
     selectAll:                             Select All
     paste:                                 Paste
     delete:                                Delete
     _promptForReplace:                     Replace...
     _transliterateChinese:                 简⇄繁
     _showTextStyleOptions:                 𝐁𝐼𝐔
     _define:                               Define
     _addShortcut:                          Add...
     _accessibilitySpeak:                   Speak
     _accessibilitySpeakLanguageSelection:  Speak...
     _accessibilityPauseSpeaking:           Pause Speak
     makeTextWritingDirectionRightToLeft:   ⇋
     makeTextWritingDirectionLeftToRight:   ⇌
     
     ------------------------------------------------------
     Default attribute modifier list:
     toggleBoldface:
     toggleItalics:
     toggleUnderline:
     increaseSize:
     decreaseSize:
     */
    
    if (_selectedTextRange.asRange.length == 0) {
        if (action == @selector(select:) ||
            action == @selector(selectAll:)) {
            return _innerText.length > 0;
        }
        if (action == @selector(paste:)) {
            return [self _isPasteboardContainsValidValue];
        }
    } else {
        if (action == @selector(cut:)) {
            return self.isFirstResponder && self.editable;
        }
        if (action == @selector(copy:)) {
            return YES;
        }
        if (action == @selector(selectAll:)) {
            return _selectedTextRange.asRange.length < _innerText.length;
        }
        if (action == @selector(paste:)) {
            return self.isFirstResponder && self.editable && [self _isPasteboardContainsValidValue];
        }
        NSString *selString = NSStringFromSelector(action);
        if ([selString hasSuffix:@"define:"] && [selString hasPrefix:@"_"]) {
            return [self _getRootViewController] != nil;
        }
    }
    return NO;
}

- (void)reloadInputViews {
    [super reloadInputViews];
    if (_markedTextRange) {
        [self unmarkText];
    }
}

#pragma mark - Override NSObject(UIResponderStandardEditActions)

- (void)cut:(id)sender {
    [self _endTouchTracking];
    if (_selectedTextRange.asRange.length == 0) return;
    
    [self _copySelectedTextToPasteboard];
    [self _saveToUndoStack];
    [self _resetRedoStack];
    [self replaceRange:_selectedTextRange withText:@""];
}

- (void)copy:(id)sender {
    [self _endTouchTracking];
    [self _copySelectedTextToPasteboard];
}

- (void)paste:(id)sender {
    [self _endTouchTracking];
    UIPasteboard *p = [UIPasteboard generalPasteboard];
    NSAttributedString *atr = nil;
    
    if (_allowsPasteAttributedString) {
        atr = p.kk_AttributedString;
        if (atr.length == 0) atr = nil;
    }
    if (!atr && _allowsPasteImage) {
        UIImage *img = nil;
        
        Class cls = NSClassFromString(@"KKImage");
        if (cls) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
            if (p.kk_GIFData) {
                img = [(id)cls performSelector:@selector(imageWithData:scale:) withObject:p.kk_GIFData withObject:nil];
            }
            if (!img && p.kk_PNGData) {
                img = [(id)cls performSelector:@selector(imageWithData:scale:) withObject:p.kk_PNGData withObject:nil];
            }
            if (!img && p.kk_WEBPData) {
                img = [(id)cls performSelector:@selector(imageWithData:scale:) withObject:p.kk_WEBPData withObject:nil];
            }
#pragma clang diagnostic pop
        }
        
        if (!img) {
            img = p.image;
        }
        if (!img && p.kk_ImageData) {
            img = [UIImage imageWithData:p.kk_ImageData scale:KKTextScreenScale()];
        }
        if (img && img.size.width > 1 && img.size.height > 1) {
            id content = img;
            
            if (cls) {
                if ([img conformsToProtocol:NSProtocolFromString(@"KKAnimatedImage")]) {
                    NSNumber *frameCount = [img valueForKey:@"animatedImageFrameCount"];
                    if (frameCount.integerValue > 1) {
                        Class viewCls = NSClassFromString(@"KKAnimatedImageView");
                        UIImageView *imgView = [(id)viewCls new];
                        imgView.image = img;
                        imgView.frame = CGRectMake(0, 0, img.size.width, img.size.height);
                        if (imgView) {
                            content = imgView;
                        }
                    }
                }
            }
            
            if ([content isKindOfClass:[UIImage class]] && img.images.count > 1) {
                UIImageView *imgView = [UIImageView new];
                imgView.image = img;
                imgView.frame = CGRectMake(0, 0, img.size.width, img.size.height);
                if (imgView) {
                    content = imgView;
                }
            }
            
            NSMutableAttributedString *attText = [NSAttributedString kk_attachmentStringWithContent:content contentMode:UIViewContentModeScaleToFill width:img.size.width ascent:img.size.height descent:0];
            NSDictionary *attrs = _typingAttributesHolder.kk_attributes;
            if (attrs) [attText addAttributes:attrs range:NSMakeRange(0, attText.length)];
            atr = attText;
        }
    }
    
    if (atr) {
        NSUInteger endPosition = _selectedTextRange.start.offset + atr.length;
        NSMutableAttributedString *text = _innerText.mutableCopy;
        [text replaceCharactersInRange:_selectedTextRange.asRange withAttributedString:atr];
        self.attributedText = text;
        KKTextPosition *pos = [self _correctedTextPosition:[KKTextPosition positionWithOffset:endPosition]];
        KKTextRange *range = [self _textRangeByExtendingTextPosition:pos];
        range = [self _correctedTextRange:range];
        if (range) {
            self.selectedRange = NSMakeRange(range.end.offset, 0);
        }
    } else {
        NSString *string = p.string;
        if (string.length > 0) {
            [self _saveToUndoStack];
            [self _resetRedoStack];
            [self replaceRange:_selectedTextRange withText:string];
        }
    }
}

- (void)select:(id)sender {
    [self _endTouchTracking];
    
    if (_selectedTextRange.asRange.length > 0 || _innerText.length == 0) return;
    KKTextRange *newRange = [self _getClosestTokenRangeAtPosition:_selectedTextRange.start];
    if (newRange.asRange.length > 0) {
        [_inputDelegate selectionWillChange:self];
        _selectedTextRange = newRange;
        [_inputDelegate selectionDidChange:self];
    }
    
    [self _updateIfNeeded];
    [self _updateOuterProperties];
    [self _updateSelectionView];
    [self _hideMenu];
    [self _showMenu];
}

- (void)selectAll:(id)sender {
    _trackingRange = nil;
    [_inputDelegate selectionWillChange:self];
    _selectedTextRange = [KKTextRange rangeWithRange:NSMakeRange(0, _innerText.length)];
    [_inputDelegate selectionDidChange:self];
    
    [self _updateIfNeeded];
    [self _updateOuterProperties];
    [self _updateSelectionView];
    [self _hideMenu];
    [self _showMenu];
}

- (void)_define:(id)sender {
    [self _hideMenu];
    
    NSString *string = [_innerText kk_plainTextForRange:_selectedTextRange.asRange];
    if (string.length == 0) return;
    BOOL resign = [self resignFirstResponder];
    if (!resign) return;
    
    UIReferenceLibraryViewController* ref = [[UIReferenceLibraryViewController alloc] initWithTerm:string];
    ref.view.backgroundColor = [UIColor whiteColor];
    [[self _getRootViewController] presentViewController:ref animated:YES completion:^{}];
}


#pragma mark - Overrice NSObject(NSKeyValueObservingCustomization)

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key {
    static NSSet *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSSet setWithArray:@[
            @"text",
            @"font",
            @"textColor",
            @"textAlignment",
            @"dataDetectorTypes",
            @"linkTextAttributes",
            @"highlightTextAttributes",
            @"textParser",
            @"attributedText",
            @"textVerticalAlignment",
            @"textContainerInset",
            @"exclusionPaths",
            @"verticalForm",
            @"linePositionModifier",
            @"selectedRange",
            @"typingAttributes"
        ]];
    });
    if ([keys containsObject:key]) {
        return NO;
    }
    return [super automaticallyNotifiesObserversForKey:key];
}

#pragma mark - @protocol NSCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    [self _initTextView];
    self.attributedText = [aDecoder decodeObjectForKey:@"attributedText"];
    self.selectedRange = ((NSValue *)[aDecoder decodeObjectForKey:@"selectedRange"]).rangeValue;
    self.textVerticalAlignment = [aDecoder decodeIntegerForKey:@"textVerticalAlignment"];
    self.dataDetectorTypes = [aDecoder decodeIntegerForKey:@"dataDetectorTypes"];
    self.textContainerInset = ((NSValue *)[aDecoder decodeObjectForKey:@"textContainerInset"]).UIEdgeInsetsValue;
    self.exclusionPaths = [aDecoder decodeObjectForKey:@"exclusionPaths"];
    self.verticalForm = [aDecoder decodeBoolForKey:@"verticalForm"];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [super encodeWithCoder:aCoder];
    [aCoder encodeObject:self.attributedText forKey:@"attributedText"];
    [aCoder encodeObject:[NSValue valueWithRange:self.selectedRange] forKey:@"selectedRange"];
    [aCoder encodeInteger:self.textVerticalAlignment forKey:@"textVerticalAlignment"];
    [aCoder encodeInteger:self.dataDetectorTypes forKey:@"dataDetectorTypes"];
    [aCoder encodeUIEdgeInsets:self.textContainerInset forKey:@"textContainerInset"];
    [aCoder encodeObject:self.exclusionPaths forKey:@"exclusionPaths"];
    [aCoder encodeBool:self.verticalForm forKey:@"verticalForm"];
}

#pragma mark - @protocol UIScrollViewDelegate

- (id<KKTextViewDelegate>)delegate {
    return _outerDelegate;
}

- (void)setDelegate:(id<KKTextViewDelegate>)delegate {
    _outerDelegate = delegate;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [[KKTextEffectWindow sharedWindow] hideSelectionDot:_selectionView];
    
    if ([_outerDelegate respondsToSelector:_cmd]) {
        [_outerDelegate scrollViewDidScroll:scrollView];
    }
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    if ([_outerDelegate respondsToSelector:_cmd]) {
        [_outerDelegate scrollViewDidZoom:scrollView];
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if ([_outerDelegate respondsToSelector:_cmd]) {
        [_outerDelegate scrollViewWillBeginDragging:scrollView];
    }
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    if ([_outerDelegate respondsToSelector:_cmd]) {
        [_outerDelegate scrollViewWillEndDragging:scrollView withVelocity:velocity targetContentOffset:targetContentOffset];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) {
        [[KKTextEffectWindow sharedWindow] showSelectionDot:_selectionView];
    }
    
    if ([_outerDelegate respondsToSelector:_cmd]) {
        [_outerDelegate scrollViewDidEndDragging:scrollView willDecelerate:decelerate];
    }
}

- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView {
    if ([_outerDelegate respondsToSelector:_cmd]) {
        [_outerDelegate scrollViewWillBeginDecelerating:scrollView];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [[KKTextEffectWindow sharedWindow] showSelectionDot:_selectionView];
    
    if ([_outerDelegate respondsToSelector:_cmd]) {
        [_outerDelegate scrollViewDidEndDecelerating:scrollView];
    }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    if ([_outerDelegate respondsToSelector:_cmd]) {
        [_outerDelegate scrollViewDidEndScrollingAnimation:scrollView];
    }
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    if ([_outerDelegate respondsToSelector:_cmd]) {
        return [_outerDelegate viewForZoomingInScrollView:scrollView];
    } else {
        return nil;
    }
}

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view{
    if ([_outerDelegate respondsToSelector:_cmd]) {
        [_outerDelegate scrollViewWillBeginZooming:scrollView withView:view];
    }
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale {
    if ([_outerDelegate respondsToSelector:_cmd]) {
        [_outerDelegate scrollViewDidEndZooming:scrollView withView:view atScale:scale];
    }
}

- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollView {
    if ([_outerDelegate respondsToSelector:_cmd]) {
        return [_outerDelegate scrollViewShouldScrollToTop:scrollView];
    }
    return YES;
}

- (void)scrollViewDidScrollToTop:(UIScrollView *)scrollView {
    if ([_outerDelegate respondsToSelector:_cmd]) {
        [_outerDelegate scrollViewDidScrollToTop:scrollView];
    }
}

#pragma mark - @protocol KKTextKeyboardObserver

- (void)keyboardChangedWithTransition:(KKTextKeyboardTransition)transition {
    [self _keyboardChanged];
}

#pragma mark - @protocol UIALertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    NSString *title = [alertView buttonTitleAtIndex:buttonIndex];
    if (title.length == 0) return;
    NSArray *strings = [self _localizedUndoStrings];
    if ([title isEqualToString:strings[1]] || [title isEqualToString:strings[2]]) {
        [self _redo];
    } else if ([title isEqualToString:strings[3]] || [title isEqualToString:strings[4]]) {
        [self _undo];
    }
    [self _restoreFirstResponderAfterUndoAlert];
}

#pragma mark - @protocol UIKeyInput

- (BOOL)hasText {
    return _innerText.length > 0;
}

- (void)insertText:(NSString *)text {
    if (text.length == 0) return;
    if (!NSEqualRanges(_lastTypeRange, _selectedTextRange.asRange)) {
        [self _saveToUndoStack];
        [self _resetRedoStack];
    }
    [self replaceRange:_selectedTextRange withText:text];
}

- (void)deleteBackward {
    [self _updateIfNeeded];
    NSRange range = _selectedTextRange.asRange;
    if (range.location == 0 && range.length == 0) return;
    _state.typingAttributesOnce = NO;
    
    // test if there's 'TextBinding' before the caret
    if (!_state.deleteConfirm && range.length == 0 && range.location > 0) {
        NSRange effectiveRange;
        KKTextBinding *binding = [_innerText attribute:KKTextBindingAttributeName atIndex:range.location - 1 longestEffectiveRange:&effectiveRange inRange:NSMakeRange(0, _innerText.length)];
        if (binding && binding.deleteConfirm) {
            _state.deleteConfirm = YES;
            [_inputDelegate selectionWillChange:self];
            _selectedTextRange = [KKTextRange rangeWithRange:effectiveRange];
            _selectedTextRange = [self _correctedTextRange:_selectedTextRange];
            [_inputDelegate selectionDidChange:self];
            
            [self _updateOuterProperties];
            [self _updateSelectionView];
            return;
        }
    }
    
    _state.deleteConfirm = NO;
    if (range.length == 0) {
        KKTextRange *extendRange = [self _textRangeByExtendingTextPosition:_selectedTextRange.end inDirection:UITextLayoutDirectionLeft offset:1];
        if ([self _isTextRangeValid:extendRange]) {
            range = extendRange.asRange;
        }
    }
    if (!NSEqualRanges(_lastTypeRange, _selectedTextRange.asRange)) {
        [self _saveToUndoStack];
        [self _resetRedoStack];
    }
    [self replaceRange:[KKTextRange rangeWithRange:range] withText:@""];
}

#pragma mark - @protocol UITextInput

- (void)setInputDelegate:(id<UITextInputDelegate>)inputDelegate {
    _inputDelegate = inputDelegate;
}

- (void)setSelectedTextRange:(KKTextRange *)selectedTextRange {
    if (!selectedTextRange) return;
    selectedTextRange = [self _correctedTextRange:selectedTextRange];
    if ([selectedTextRange isEqual:_selectedTextRange]) return;
    [self _updateIfNeeded];
    [self _endTouchTracking];
    [self _hideMenu];
    _state.deleteConfirm = NO;
    _state.typingAttributesOnce = NO;
    
    [_inputDelegate selectionWillChange:self];
    _selectedTextRange = selectedTextRange;
    _lastTypeRange = _selectedTextRange.asRange;
    [_inputDelegate selectionDidChange:self];
    
    [self _updateOuterProperties];
    [self _updateSelectionView];
    
    if (self.isFirstResponder) {
        [self _scrollRangeToVisible:_selectedTextRange];
    }
}

- (void)setMarkedTextStyle:(NSDictionary *)markedTextStyle {
    _markedTextStyle = markedTextStyle.copy;
}

/*
 Replace current markedText with the new markedText
 @param markedText     New marked text.
 @param selectedRange  The range from the '_markedTextRange'
 */
- (void)setMarkedText:(NSString *)markedText selectedRange:(NSRange)selectedRange {
    [self _updateIfNeeded];
    [self _endTouchTracking];
    [self _hideMenu];
    
    if ([self.delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]) {
        NSRange range = _markedTextRange ? _markedTextRange.asRange : NSMakeRange(_selectedTextRange.end.offset, 0);
        BOOL should = [self.delegate textView:self shouldChangeTextInRange:range replacementText:markedText];
        if (!should) return;
    }
    
    
    if (!NSEqualRanges(_lastTypeRange, _selectedTextRange.asRange)) {
        [self _saveToUndoStack];
        [self _resetRedoStack];
    }
    
    BOOL needApplyHolderAttribute = NO;
    if (_innerText.length > 0 && _markedTextRange) {
        [self _updateAttributesHolder];
    } else {
        needApplyHolderAttribute = YES;
    }
    
    if (_selectedTextRange.asRange.length > 0) {
        [self replaceRange:_selectedTextRange withText:@""];
    }
    
    [_inputDelegate textWillChange:self];
    [_inputDelegate selectionWillChange:self];
    
    if (!markedText) markedText = @"";
    if (_markedTextRange == nil) {
        NSRange replaceRange = NSMakeRange(_selectedTextRange.end.offset, 0);
        [self _recordParagraphEditRange:replaceRange replacementLength:markedText.length];
        _markedTextRange = [KKTextRange rangeWithRange:NSMakeRange(_selectedTextRange.end.offset, markedText.length)];
        [_innerText replaceCharactersInRange:replaceRange withString:markedText];
        _selectedTextRange = [KKTextRange rangeWithRange:NSMakeRange(_selectedTextRange.start.offset + selectedRange.location, selectedRange.length)];
    } else {
        _markedTextRange = [self _correctedTextRange:_markedTextRange];
        [self _recordParagraphEditRange:_markedTextRange.asRange replacementLength:markedText.length];
        [_innerText replaceCharactersInRange:_markedTextRange.asRange withString:markedText];
        _markedTextRange = [KKTextRange rangeWithRange:NSMakeRange(_markedTextRange.start.offset, markedText.length)];
        _selectedTextRange = [KKTextRange rangeWithRange:NSMakeRange(_markedTextRange.start.offset + selectedRange.location, selectedRange.length)];
    }
    
    _selectedTextRange = [self _correctedTextRange:_selectedTextRange];
    _markedTextRange = [self _correctedTextRange:_markedTextRange];
    if (_markedTextRange.asRange.length == 0) {
        _markedTextRange = nil;
    } else {
        if (needApplyHolderAttribute) {
            [_innerText setAttributes:_typingAttributesHolder.kk_attributes range:_markedTextRange.asRange];
        }
        [_innerText kk_removeDiscontinuousAttributesInRange:_markedTextRange.asRange];
    }
    
    [_inputDelegate selectionDidChange:self];
    [_inputDelegate textDidChange:self];
    
    [self _updateOuterProperties];
    [self _updateLayout];
    [self _updateSelectionView];
    [self _scrollRangeToVisible:_selectedTextRange];
    
    if ([self.delegate respondsToSelector:@selector(textViewDidChange:)]) {
        [self.delegate textViewDidChange:self];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:KKTextViewTextDidChangeNotification object:self];
    
    _lastTypeRange = _selectedTextRange.asRange;
}

- (void)unmarkText {
    _markedTextRange = nil;
    [self _endTouchTracking];
    [self _hideMenu];
    if ([self _parseText]) _state.needUpdate = YES;
    
    [self _updateIfNeeded];
    [self _updateOuterProperties];
    [self _updateSelectionView];
    [self _scrollRangeToVisible:_selectedTextRange];
}

- (void)replaceRange:(KKTextRange *)range withText:(NSString *)text {
    if (!range) return;
    if (!text) text = @"";
    if (range.asRange.length == 0 && text.length == 0) return;
    range = [self _correctedTextRange:range];
    
    if ([self.delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]) {
        BOOL should = [self.delegate textView:self shouldChangeTextInRange:range.asRange replacementText:text];
        if (!should) return;
    }
    
    BOOL useInnerAttributes = NO;
    if (_innerText.length > 0) {
        if (range.start.offset == 0 && range.end.offset == _innerText.length) {
            if (text.length == 0) {
                NSMutableDictionary *attrs = [_innerText kk_attributesAtIndex:0].mutableCopy;
                [attrs removeObjectsForKeys:[NSMutableAttributedString kk_allDiscontinuousAttributeKeys]];
                _typingAttributesHolder.kk_attributes = attrs;
            }
        }
    } else { // no text
        useInnerAttributes = YES;
    }
    BOOL applyTypingAttributes = NO;
    if (_state.typingAttributesOnce) {
        _state.typingAttributesOnce = NO;
        if (!useInnerAttributes) {
            if (range.asRange.length == 0 && text.length > 0) {
                applyTypingAttributes = YES;
            }
        }
    }
    
    _state.selectedWithoutEdit = NO;
    _state.deleteConfirm = NO;
    [self _endTouchTracking];
    [self _hideMenu];
    
    [self _replaceRange:range withText:text notifyToDelegate:YES];
    if (useInnerAttributes) {
        [_innerText kk_setAttributes:_typingAttributesHolder.kk_attributes];
    } else if (applyTypingAttributes) {
        NSRange newRange = NSMakeRange(range.asRange.location, text.length);
        [_typingAttributesHolder.kk_attributes enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            [_innerText kk_setAttribute:key value:obj range:newRange];
        }];
    }
    [self _parseText];
    [self _updateOuterProperties];
    [self _update];
    
    if (self.isFirstResponder) {
        [self _scrollRangeToVisible:_selectedTextRange];
    }
    
    if ([self.delegate respondsToSelector:@selector(textViewDidChange:)]) {
        [self.delegate textViewDidChange:self];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:KKTextViewTextDidChangeNotification object:self];
    
    _lastTypeRange = _selectedTextRange.asRange;
}

- (void)setBaseWritingDirection:(UITextWritingDirection)writingDirection forRange:(KKTextRange *)range {
    if (!range) return;
    range = [self _correctedTextRange:range];
    [_innerText kk_setBaseWritingDirection:(NSWritingDirection)writingDirection range:range.asRange];
    [self _commitUpdate];
}

- (NSString *)textInRange:(KKTextRange *)range {
    range = [self _correctedTextRange:range];
    if (!range) return @"";
    return [_innerText.string substringWithRange:range.asRange];
}

- (UITextWritingDirection)baseWritingDirectionForPosition:(KKTextPosition *)position inDirection:(UITextStorageDirection)direction {
    [self _updateIfNeeded];
    position = [self _correctedTextPosition:position];
    if (!position) return UITextWritingDirectionNatural;
    if (_innerText.length == 0) return UITextWritingDirectionNatural;
    NSUInteger idx = position.offset;
    if (idx == _innerText.length) idx--;
    
    NSDictionary *attrs = [_innerText kk_attributesAtIndex:idx];
    CTParagraphStyleRef paraStyle = (__bridge CFTypeRef)(attrs[NSParagraphStyleAttributeName]);
    if (paraStyle) {
        CTWritingDirection baseWritingDirection;
        if (CTParagraphStyleGetValueForSpecifier(paraStyle, kCTParagraphStyleSpecifierBaseWritingDirection, sizeof(CTWritingDirection), &baseWritingDirection)) {
            return (UITextWritingDirection)baseWritingDirection;
        }
    }
    
    return UITextWritingDirectionNatural;
}

- (KKTextPosition *)beginningOfDocument {
    return [KKTextPosition positionWithOffset:0];
}

- (KKTextPosition *)endOfDocument {
    return [KKTextPosition positionWithOffset:_innerText.length];
}

- (KKTextPosition *)positionFromPosition:(KKTextPosition *)position offset:(NSInteger)offset {
    if (offset == 0) return position;
    
    NSUInteger location = position.offset;
    NSInteger newLocation = (NSInteger)location + offset;
    if (newLocation < 0 || newLocation > _innerText.length) return nil;
    
    if (newLocation != 0 && newLocation != _innerText.length) {
        // fix emoji
        [self _updateIfNeeded];
        KKTextRange *extendRange = [self _textRangeByExtendingTextPosition:[KKTextPosition positionWithOffset:newLocation]];
        if (extendRange.asRange.length > 0) {
            if (offset < 0) {
                newLocation = extendRange.start.offset;
            } else {
                newLocation = extendRange.end.offset;
            }
        }
    }
    
    KKTextPosition *p = [KKTextPosition positionWithOffset:newLocation];
    return [self _correctedTextPosition:p];
}

- (KKTextPosition *)positionFromPosition:(KKTextPosition *)position inDirection:(UITextLayoutDirection)direction offset:(NSInteger)offset {
    [self _updateIfNeeded];
    KKTextRange *range = [self _textRangeByExtendingTextPosition:position inDirection:direction offset:offset];
    
    BOOL forward;
    if (_innerContainer.isVerticalForm) {
        forward = direction == UITextLayoutDirectionLeft || direction == UITextLayoutDirectionDown;
    } else {
        forward = direction == UITextLayoutDirectionDown || direction == UITextLayoutDirectionRight;
    }
    if (!forward && offset < 0) {
        forward = -forward;
    }
    
    KKTextPosition *newPosition = forward ? range.end : range.start;
    if (newPosition.offset > _innerText.length) {
        newPosition = [KKTextPosition positionWithOffset:_innerText.length affinity:KKTextAffinityBackward];
    }
    
    return [self _correctedTextPosition:newPosition];
}

- (KKTextRange *)textRangeFromPosition:(KKTextPosition *)fromPosition toPosition:(KKTextPosition *)toPosition {
    return [KKTextRange rangeWithStart:fromPosition end:toPosition];
}

- (NSComparisonResult)comparePosition:(KKTextPosition *)position toPosition:(KKTextPosition *)other {
    return [position compare:other];
}

- (NSInteger)offsetFromPosition:(KKTextPosition *)from toPosition:(KKTextPosition *)toPosition {
    return toPosition.offset - from.offset;
}

- (KKTextPosition *)positionWithinRange:(KKTextRange *)range farthestInDirection:(UITextLayoutDirection)direction {
    NSRange nsRange = range.asRange;
    if (direction == UITextLayoutDirectionLeft | direction == UITextLayoutDirectionUp) {
        return [KKTextPosition positionWithOffset:nsRange.location];
    } else {
        return [KKTextPosition positionWithOffset:nsRange.location + nsRange.length affinity:KKTextAffinityBackward];
    }
}

- (KKTextRange *)characterRangeByExtendingPosition:(KKTextPosition *)position inDirection:(UITextLayoutDirection)direction {
    [self _updateIfNeeded];
    KKTextRange *range = [self _textRangeByExtendingTextPosition:position inDirection:direction offset:1];
    return [self _correctedTextRange:range];
}

- (KKTextPosition *)closestPositionToPoint:(CGPoint)point {
    [self _updateIfNeeded];
    KKTextPosition *position = [self _closestPositionForDocumentPoint:point];
    return [self _correctedTextPosition:position];
}

- (KKTextPosition *)closestPositionToPoint:(CGPoint)point withinRange:(KKTextRange *)range {
    KKTextPosition *pos = (id)[self closestPositionToPoint:point];
    if (!pos) return nil;
    
    range = [self _correctedTextRange:range];
    if ([pos compare:range.start] == NSOrderedAscending) {
        pos = range.start;
    } else if ([pos compare:range.end] == NSOrderedDescending) {
        pos = range.end;
    }
    return pos;
}

- (KKTextRange *)characterRangeAtPoint:(CGPoint)point {
    [self _updateIfNeeded];
    KKTextRange *r = [self _textRangeAtDocumentPoint:point closest:YES];
    return [self _correctedTextRange:r];
}

- (CGRect)firstRectForRange:(KKTextRange *)range {
    [self _updateIfNeeded];
    CGRect rect = [self _firstRectForTextRange:range];
    if (CGRectIsNull(rect)) rect = CGRectZero;
    return rect;
}

- (CGRect)caretRectForPosition:(KKTextPosition *)position {
    [self _updateIfNeeded];
    CGRect caretRect = [self _caretRectForTextPosition:position];
    if (!CGRectIsNull(caretRect)) {
        caretRect = CGRectStandardize(caretRect);
        if (_verticalForm) {
            if (caretRect.size.height == 0) {
                caretRect.size.height = 2;
                caretRect.origin.y -= 2 * 0.5;
            }
            if (caretRect.origin.y < 0) {
                caretRect.origin.y = 0;
            } else if (caretRect.origin.y + caretRect.size.height > self.bounds.size.height) {
                caretRect.origin.y = self.bounds.size.height - caretRect.size.height;
            }
        } else {
            if (caretRect.size.width == 0) {
                caretRect.size.width = 2;
                caretRect.origin.x -= 2 * 0.5;
            }
            if (caretRect.origin.x < 0) {
                caretRect.origin.x = 0;
            } else if (caretRect.origin.x + caretRect.size.width > self.bounds.size.width) {
                caretRect.origin.x = self.bounds.size.width - caretRect.size.width;
            }
        }
        return KKTextCGRectPixelRound(caretRect);
    }
    return CGRectZero;
}

- (NSArray *)selectionRectsForRange:(KKTextRange *)range {
    [self _updateIfNeeded];
    return [self _selectionRectsForTextRange:range];
}

#pragma mark - @protocol UITextInput optional

- (UITextStorageDirection)selectionAffinity {
    if (_selectedTextRange.end.affinity == KKTextAffinityForward) {
        return UITextStorageDirectionForward;
    } else {
        return UITextStorageDirectionBackward;
    }
}

- (void)setSelectionAffinity:(UITextStorageDirection)selectionAffinity {
    _selectedTextRange = [KKTextRange rangeWithRange:_selectedTextRange.asRange affinity:selectionAffinity == UITextStorageDirectionForward ? KKTextAffinityForward : KKTextAffinityBackward];
    [self _updateSelectionView];
}

- (NSDictionary *)textStylingAtPosition:(KKTextPosition *)position inDirection:(UITextStorageDirection)direction {
    if (!position) return nil;
    if (_innerText.length == 0) return _typingAttributesHolder.kk_attributes;
    NSDictionary *attrs = nil;
    if (0 <= position.offset  && position.offset <= _innerText.length) {
        NSUInteger ofs = position.offset;
        if (position.offset == _innerText.length ||
            direction == UITextStorageDirectionBackward) {
             ofs--;
        }
        attrs = [_innerText attributesAtIndex:ofs effectiveRange:NULL];
    }
    return attrs;
}

- (KKTextPosition *)positionWithinRange:(KKTextRange *)range atCharacterOffset:(NSInteger)offset {
    if (!range) return nil;
    if (offset < range.start.offset || offset > range.end.offset) return nil;
    if (offset == range.start.offset) return range.start;
    else if (offset == range.end.offset) return range.end;
    else return [KKTextPosition positionWithOffset:offset];
}

- (NSInteger)characterOffsetOfPosition:(KKTextPosition *)position withinRange:(KKTextRange *)range {
    return position ? position.offset : NSNotFound;
}

@end



@interface KKTextView(IBInspectableProperties)
@end

@implementation KKTextView(IBInspectableProperties)

- (BOOL)fontIsBold_:(UIFont *)font {
    if (![font respondsToSelector:@selector(fontDescriptor)]) return NO;
    return (font.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) > 0;
}

- (UIFont *)boldFont_:(UIFont *)font {
    if (![font respondsToSelector:@selector(fontDescriptor)]) return font;
    return [UIFont fontWithDescriptor:[font.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold] size:font.pointSize];
}

- (UIFont *)normalFont_:(UIFont *)font {
    if (![font respondsToSelector:@selector(fontDescriptor)]) return font;
    return [UIFont fontWithDescriptor:[font.fontDescriptor fontDescriptorWithSymbolicTraits:0] size:font.pointSize];
}

- (void)setFontName_:(NSString *)fontName {
    if (!fontName) return;
    UIFont *font = self.font;
    if (!font) font = [self _defaultFont];
    if ((fontName.length == 0 || [fontName.lowercaseString isEqualToString:@"system"]) && ![self fontIsBold_:font]) {
        font = [UIFont systemFontOfSize:font.pointSize];
    } else if ([fontName.lowercaseString isEqualToString:@"system bold"]) {
        font = [UIFont boldSystemFontOfSize:font.pointSize];
    } else {
        if ([self fontIsBold_:font] && ([fontName.lowercaseString rangeOfString:@"bold"].location == NSNotFound)) {
            font = [UIFont fontWithName:fontName size:font.pointSize];
            font = [self boldFont_:font];
        } else {
            font = [UIFont fontWithName:fontName size:font.pointSize];
        }
    }
    if (font) self.font = font;
}

- (void)setFontSize_:(CGFloat)fontSize {
    if (fontSize <= 0) return;
    UIFont *font = self.font;
    if (!font) font = [self _defaultFont];
    if (!font) font = [self _defaultFont];
    font = [font fontWithSize:fontSize];
    if (font) self.font = font;
}

- (void)setFontIsBold_:(BOOL)fontBold {
    UIFont *font = self.font;
    if (!font) font = [self _defaultFont];
    if ([self fontIsBold_:font] == fontBold) return;
    if (fontBold) {
        font = [self boldFont_:font];
    } else {
        font = [self normalFont_:font];
    }
    if (font) self.font = font;
}

- (void)setPlaceholderFontName_:(NSString *)fontName {
    if (!fontName) return;
    UIFont *font = self.placeholderFont;
    if (!font) font = [self _defaultFont];
    if ((fontName.length == 0 || [fontName.lowercaseString isEqualToString:@"system"]) && ![self fontIsBold_:font]) {
        font = [UIFont systemFontOfSize:font.pointSize];
    } else if ([fontName.lowercaseString isEqualToString:@"system bold"]) {
        font = [UIFont boldSystemFontOfSize:font.pointSize];
    } else {
        if ([self fontIsBold_:font] && ([fontName.lowercaseString rangeOfString:@"bold"].location == NSNotFound)) {
            font = [UIFont fontWithName:fontName size:font.pointSize];
            font = [self boldFont_:font];
        } else {
            font = [UIFont fontWithName:fontName size:font.pointSize];
        }
    }
    if (font) self.placeholderFont = font;
}

- (void)setPlaceholderFontSize_:(CGFloat)fontSize {
    if (fontSize <= 0) return;
    UIFont *font = self.placeholderFont;
    if (!font) font = [self _defaultFont];
    font = [font fontWithSize:fontSize];
    if (font) self.placeholderFont = font;
}

- (void)setPlaceholderFontIsBold_:(BOOL)fontBold {
    UIFont *font = self.placeholderFont;
    if (!font) font = [self _defaultFont];
    if ([self fontIsBold_:font] == fontBold) return;
    if (fontBold) {
        font = [self boldFont_:font];
    } else {
        font = [self normalFont_:font];
    }
    if (font) self.placeholderFont = font;
}

- (void)setInsetTop_:(CGFloat)textInsetTop {
    UIEdgeInsets insets = self.textContainerInset;
    insets.top = textInsetTop;
    self.textContainerInset = insets;
}

- (void)setInsetBottom_:(CGFloat)textInsetBottom {
    UIEdgeInsets insets = self.textContainerInset;
    insets.bottom = textInsetBottom;
    self.textContainerInset = insets;
}

- (void)setInsetLeft_:(CGFloat)textInsetLeft {
    UIEdgeInsets insets = self.textContainerInset;
    insets.left = textInsetLeft;
    self.textContainerInset = insets;
    
}

- (void)setInsetRight_:(CGFloat)textInsetRight {
    UIEdgeInsets insets = self.textContainerInset;
    insets.right = textInsetRight;
    self.textContainerInset = insets;
}

- (void)setDebugEnabled_:(BOOL)enabled {
    if (!enabled) {
        self.debugOption = nil;
    } else {
        KKTextDebugOption *debugOption = [KKTextDebugOption new];
        debugOption.baselineColor = [UIColor redColor];
        debugOption.CTFrameBorderColor = [UIColor redColor];
        debugOption.CTLineFillColor = [UIColor colorWithRed:0.000 green:0.463 blue:1.000 alpha:0.180];
        debugOption.CGGlyphBorderColor = [UIColor colorWithRed:1.000 green:0.524 blue:0.000 alpha:0.200];
        self.debugOption = debugOption;
    }
}

@end
