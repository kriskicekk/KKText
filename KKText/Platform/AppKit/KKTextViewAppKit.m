//
//  KKTextViewAppKit.m
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/10.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "KKTextView.h"

#if KKTEXT_MAC

#import "KKTextInput.h"
#import "KKTextUtilities.h"
#import "KKTextWeakProxy.h"
#import "NSAttributedString+KKText.h"

NSString *const KKTextViewTextDidBeginEditingNotification = @"KKTextViewTextDidBeginEditing";
NSString *const KKTextViewTextDidChangeNotification = @"KKTextViewTextDidChange";
NSString *const KKTextViewTextDidEndEditingNotification = @"KKTextViewTextDidEndEditing";

static NSPasteboardType const KKTextViewPasteboardTypeAttributedString = @"com.ibireme.NSAttributedString";
static NSRange KKTextViewMakeSafeRange(NSRange range, NSUInteger length) {
    if (range.location == NSNotFound) return NSMakeRange(length, 0);
    if (range.location > length) range.location = length;
    if (range.length > length - range.location) range.length = length - range.location;
    return range;
}

static const NSTimeInterval KKTextViewCaretBlinkInterval = 0.5;
static const NSUInteger KKTextViewDefaultMaximumUndoLevel = 20;

static inline void KKTextViewFlipContextVertically(CGContextRef context, CGSize size) {
    CGContextTranslateCTM(context, 0, size.height);
    CGContextScaleCTM(context, 1, -1);
}

@interface _KKTextViewUndoState : NSObject
@property (nonatomic, copy) NSAttributedString *text;
@property (nonatomic) NSRange selectedRange;
@end

@implementation _KKTextViewUndoState

+ (instancetype)stateWithText:(NSAttributedString *)text selectedRange:(NSRange)selectedRange {
    _KKTextViewUndoState *state = [self new];
    state.text = text ?: [NSAttributedString new];
    state.selectedRange = selectedRange;
    return state;
}

@end

@interface _KKTextViewDocumentView : NSView
@property (nullable, nonatomic, weak) KKTextView *textView;
@end

@interface KKTextView ()
@property (nullable, nonatomic, strong, readwrite) KKTextLayout *textLayout;
- (void)_drawDocumentViewInRect:(NSRect)dirtyRect;
@end

@implementation KKTextView {
    __weak id<KKTextViewDelegate> _delegate;
    NSMutableAttributedString *_innerText;
    NSMutableAttributedString *_placeholderInnerText;
    KKTextContainer *_innerContainer;
    KKTextLayout *_innerLayout;
    KKTextLayout *_placeholderLayout;
    NSMutableDictionary *_currentTypingAttributes;
    NSDictionary *_typingAttributes;
    NSString *_placeholderText;
    UIFont *_placeholderFont;
    NSAttributedString *_placeholderAttributedText;
    NSRange _selectedRange;
    NSRange _markedRange;
    NSUInteger _selectionAnchorLocation;
    _KKTextViewDocumentView *_textDocumentView;
    CGSize _documentSize;
    NSMutableArray<_KKTextViewUndoState *> *_undoStack;
    NSMutableArray<_KKTextViewUndoState *> *_redoStack;
    NSTimer *_caretBlinkTimer;
    BOOL _caretVisible;
    BOOL _caretActive;
    BOOL _trackingSelection;
    BOOL _editing;
    BOOL _insideUndoOrRedo;
}

@synthesize delegate = _delegate;

#pragma mark - Init

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    [self _initTextView];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (!self) return nil;
    [self _initTextView];
    return self;
}

- (void)dealloc {
    [_caretBlinkTimer invalidate];
}

- (BOOL)acceptsFirstResponder {
    return _editable || _selectable;
}

- (BOOL)becomeFirstResponder {
    if (_delegate && [_delegate respondsToSelector:@selector(textViewShouldBeginEditing:)] && ![_delegate textViewShouldBeginEditing:self]) {
        return NO;
    }
    [super becomeFirstResponder];
    if (!_editing) {
        _editing = YES;
        if (_delegate && [_delegate respondsToSelector:@selector(textViewDidBeginEditing:)]) {
            [_delegate textViewDidBeginEditing:self];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:KKTextViewTextDidBeginEditingNotification object:self];
    }
    [self _resetCaretBlink];
    return YES;
}

- (BOOL)resignFirstResponder {
    if (_delegate && [_delegate respondsToSelector:@selector(textViewShouldEndEditing:)] && ![_delegate textViewShouldEndEditing:self]) {
        return NO;
    }
    BOOL result = [super resignFirstResponder];
    if (result) {
        if (_editing) {
            [self unmarkText];
            _editing = NO;
            if (_delegate && [_delegate respondsToSelector:@selector(textViewDidEndEditing:)]) {
                [_delegate textViewDidEndEditing:self];
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:KKTextViewTextDidEndEditingNotification object:self];
        }
        _caretActive = NO;
        [self _stopCaretBlink];
    }
    return result;
}

- (void)_initTextView {
    self.wantsLayer = YES;
    self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
    self.borderType = NSNoBorder;
    self.drawsBackground = NO;
    self.hasVerticalScroller = YES;
    self.hasHorizontalScroller = YES;
    self.autohidesScrollers = YES;
    self.contentView.postsBoundsChangedNotifications = YES;

    _textDocumentView = [[_KKTextViewDocumentView alloc] initWithFrame:(NSRect){CGPointZero, self.bounds.size}];
    _textDocumentView.textView = self;
    _textDocumentView.wantsLayer = YES;
    _textDocumentView.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
    self.documentView = _textDocumentView;

    _font = [self _defaultFont];
    _textColor = NSColor.textColor;
    _placeholderTextColor = NSColor.placeholderTextColor;
    _textAlignment = NSTextAlignmentNatural;
    _textVerticalAlignment = KKTextVerticalAlignmentTop;
    _textContainerInset = NSEdgeInsetsZero;
    _selectedRange = NSMakeRange(0, 0);
    _markedRange = NSMakeRange(NSNotFound, 0);
    _selectionAnchorLocation = 0;
    _documentSize = CGSizeZero;
    _caretVisible = NO;
    _caretActive = NO;
    _editable = YES;
    _selectable = YES;
    _highlightable = YES;
    _allowsCopyAttributedString = YES;
    _allowsPasteAttributedString = YES;
    _allowsUndoAndRedo = YES;
    _maximumUndoLevel = KKTextViewDefaultMaximumUndoLevel;
    _undoStack = [NSMutableArray new];
    _redoStack = [NSMutableArray new];
    _innerText = [NSMutableAttributedString new];
    _placeholderInnerText = [NSMutableAttributedString new];
    _innerContainer = [KKTextContainer containerWithSize:self.bounds.size];
    _currentTypingAttributes = [[self _defaultTypingAttributes] mutableCopy];
    [self _updateLayout];
    [self _resetUndoAndRedoStack];
}

#pragma mark - Layout and Drawing

- (void)setFrame:(NSRect)frameRect {
    CGSize oldSize = self.bounds.size;
    [super setFrame:frameRect];
    if (!CGSizeEqualToSize(oldSize, self.bounds.size)) {
        [self _updateLayout];
    }
}

- (void)setBounds:(NSRect)bounds {
    CGSize oldSize = self.bounds.size;
    [super setBounds:bounds];
    if (!CGSizeEqualToSize(oldSize, self.bounds.size)) {
        [self _updateLayout];
    }
}

- (void)setNeedsDisplay:(BOOL)needsDisplay {
    [super setNeedsDisplay:needsDisplay];
    [_textDocumentView setNeedsDisplay:needsDisplay];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
}

- (void)_drawDocumentViewInRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    if (!context) return;
    CGSize drawSize = _textDocumentView.bounds.size;
    CGContextSaveGState(context); {
        KKTextViewFlipContextVertically(context, drawSize);
        KKTextLayout *layout = _innerText.length > 0 ? _innerLayout : _placeholderLayout;
        if (_innerText.length > 0 && _selectedRange.length > 0) {
            [self _drawSelectionInContext:context size:drawSize];
        }
        [layout drawInContext:context size:drawSize point:CGPointZero view:_textDocumentView layer:_textDocumentView.layer debug:_debugOption cancel:nil];
        if ([self _shouldShowCaret] && _caretVisible) {
            [self _drawCaretInContext:context size:drawSize];
        }
    } CGContextRestoreGState(context);
}

- (CGSize)_visibleSize {
    CGSize size = self.contentView.bounds.size;
    size.width = MAX(size.width, 0);
    size.height = MAX(size.height, 0);
    return size;
}

- (CGSize)_layoutContainerSize {
    CGSize size = [self _visibleSize];
    if (_verticalForm) {
        size.width = CGFLOAT_MAX;
    } else {
        size.height = CGFLOAT_MAX;
    }
    return size;
}

- (CGPoint)_contentOffset {
    return self.contentView.bounds.origin;
}

- (CGPoint)_maximumContentOffset {
    CGSize visibleSize = [self _visibleSize];
    return CGPointMake(MAX(_documentSize.width - visibleSize.width, 0),
                       MAX(_documentSize.height - visibleSize.height, 0));
}

- (CGPoint)_clampedContentOffset:(CGPoint)contentOffset {
    CGPoint maximumOffset = [self _maximumContentOffset];
    contentOffset.x = MIN(MAX(contentOffset.x, 0), maximumOffset.x);
    contentOffset.y = MIN(MAX(contentOffset.y, 0), maximumOffset.y);
    return contentOffset;
}

- (CGPoint)_layoutPointFromViewPoint:(CGPoint)point {
    return point;
}

- (CGRect)_viewRectFromLayoutRect:(CGRect)rect {
    return rect;
}

- (void)_scrollToContentOffset:(CGPoint)contentOffset {
    NSClipView *clipView = self.contentView;
    if (!clipView) return;
    contentOffset = [self _clampedContentOffset:contentOffset];
    [clipView scrollToPoint:contentOffset];
    [self reflectScrolledClipView:clipView];
}

- (void)_scrollDocumentRectToVisible:(CGRect)rect padding:(CGFloat)padding {
    if (CGRectIsNull(rect)) return;
    CGRect visibleRect = (CGRect){[self _contentOffset], [self _visibleSize]};
    CGRect visibleRectWithTolerance = CGRectInset(visibleRect, -1, -1);
    if (CGRectContainsRect(visibleRectWithTolerance, rect)) return;

    CGRect targetRect = CGRectInset(rect, -padding, -padding);
    CGPoint contentOffset = visibleRect.origin;

    if (CGRectGetMinX(targetRect) < CGRectGetMinX(visibleRect)) {
        contentOffset.x = CGRectGetMinX(targetRect);
    } else if (CGRectGetMaxX(targetRect) > CGRectGetMaxX(visibleRect)) {
        contentOffset.x = CGRectGetMaxX(targetRect) - visibleRect.size.width;
    }

    if (CGRectGetMinY(targetRect) < CGRectGetMinY(visibleRect)) {
        contentOffset.y = CGRectGetMinY(targetRect);
    } else if (CGRectGetMaxY(targetRect) > CGRectGetMaxY(visibleRect)) {
        contentOffset.y = CGRectGetMaxY(targetRect) - visibleRect.size.height;
    }

    [self _scrollToContentOffset:contentOffset];
}

- (void)_updateDocumentViewFrame {
    if (!_textDocumentView) return;
    CGPoint contentOffset = [self _contentOffset];
    NSRect frame = (NSRect){CGPointZero, _documentSize};
    _textDocumentView.frame = frame;
    [self _scrollToContentOffset:contentOffset];
    [_textDocumentView setNeedsDisplay:YES];
}

- (void)_updateDocumentSizeForLayout {
    CGSize visibleSize = [self _visibleSize];
    CGSize documentSize = _innerLayout.textBoundingSize;
    if (_verticalForm) {
        documentSize.width = MAX(documentSize.width, visibleSize.width);
        documentSize.height = visibleSize.height;
    } else {
        documentSize.width = visibleSize.width;
        documentSize.height = MAX(documentSize.height, visibleSize.height);
    }
    _documentSize = documentSize;
    [self _updateDocumentViewFrame];
}

- (void)_updateLayout {
    _innerContainer.size = [self _layoutContainerSize];
    _innerContainer.insets = _textContainerInset;
    _innerContainer.exclusionPaths = _exclusionPaths;
    _innerContainer.verticalForm = _verticalForm;
    _innerContainer.linePositionModifier = _linePositionModifier;

    NSMutableAttributedString *layoutText = _innerText.mutableCopy;
    [layoutText replaceCharactersInRange:NSMakeRange(layoutText.length, 0) withString:@"\r"];
    [layoutText kk_removeDiscontinuousAttributesInRange:NSMakeRange(_innerText.length, 1)];
    [layoutText removeAttribute:KKTextBorderAttributeName range:NSMakeRange(_innerText.length, 1)];
    [layoutText removeAttribute:KKTextBackgroundBorderAttributeName range:NSMakeRange(_innerText.length, 1)];
    if (_innerText.length == 0 || _selectedRange.location == _innerText.length) {
        [_currentTypingAttributes enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            [layoutText kk_setAttribute:key value:obj range:NSMakeRange(_innerText.length, 1)];
        }];
    }

    _innerLayout = [KKTextLayout layoutWithContainer:_innerContainer text:layoutText];
    _placeholderLayout = [KKTextLayout layoutWithContainer:_innerContainer text:_placeholderInnerText];
    [self _updateDocumentSizeForLayout];
    self.textLayout = _innerLayout;
    [self setNeedsDisplay:YES];
}

- (void)_drawSelectionInContext:(CGContextRef)context size:(CGSize)size {
    KKTextRange *range = [KKTextRange rangeWithRange:_selectedRange];
    NSArray *rects = [_innerLayout selectionRectsForRange:range];
    CGContextSaveGState(context); {
        KKTextViewFlipContextVertically(context, size);
        CGContextClipToRect(context, (CGRect){CGPointZero, size});
        CGContextSetFillColorWithColor(context, NSColor.selectedTextBackgroundColor.CGColor);
        for (KKTextSelectionRect *selectionRect in rects) {
            if (CGRectIsEmpty(selectionRect.rect) || CGRectIsNull(selectionRect.rect)) continue;
            CGRect rect = [self _viewRectFromLayoutRect:selectionRect.rect];
            CGContextFillRect(context, rect);
        }
    } CGContextRestoreGState(context);
}

- (void)_drawCaretInContext:(CGContextRef)context size:(CGSize)size {
    CGRect caretRect = [self _caretRectForLocation:_selectedRange.location];
    if (CGRectIsNull(caretRect)) return;
    caretRect = [self _viewRectFromLayoutRect:caretRect];
    if (_verticalForm) {
        caretRect.size.height = MAX(caretRect.size.height, 2);
    } else {
        caretRect.size.width = MAX(caretRect.size.width, 2);
    }
    CGContextSaveGState(context); {
        KKTextViewFlipContextVertically(context, size);
        CGContextClipToRect(context, (CGRect){CGPointZero, size});
        CGContextSetFillColorWithColor(context, NSColor.keyboardFocusIndicatorColor.CGColor);
        CGContextFillRect(context, caretRect);
    } CGContextRestoreGState(context);
}

- (BOOL)_shouldShowCaret {
    return _caretActive && _selectedRange.length == 0;
}

- (void)_startCaretBlink {
    if (_caretBlinkTimer) return;
    _caretBlinkTimer = [NSTimer timerWithTimeInterval:KKTextViewCaretBlinkInterval
                                               target:[KKTextWeakProxy proxyWithTarget:self]
                                             selector:@selector(_caretBlinkTimerDidFire:)
                                             userInfo:nil
                                              repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_caretBlinkTimer forMode:NSRunLoopCommonModes];
}

- (void)_stopCaretBlink {
    [_caretBlinkTimer invalidate];
    _caretBlinkTimer = nil;
    _caretVisible = NO;
    [self setNeedsDisplay:YES];
}

- (void)_resetCaretBlink {
    [_caretBlinkTimer invalidate];
    _caretBlinkTimer = nil;
    _caretVisible = [self _shouldShowCaret];
    if (_caretVisible) {
        [self _startCaretBlink];
    }
    [self setNeedsDisplay:YES];
}

- (void)_caretBlinkTimerDidFire:(NSTimer *)timer {
    (void)timer;
    if (![self _shouldShowCaret]) {
        [self _stopCaretBlink];
        return;
    }
    _caretVisible = !_caretVisible;
    [self setNeedsDisplay:YES];
}

- (void)_caretFontMetricsForLocation:(NSUInteger)location ascent:(CGFloat *)ascent descent:(CGFloat *)descent {
    id font = nil;
    if (_innerText.length > 0) {
        NSUInteger index = location == 0 ? 0 : MIN(location - 1, _innerText.length - 1);
        font = [_innerText attribute:NSFontAttributeName atIndex:index effectiveRange:NULL];
        if (!font) font = [_innerText attribute:(id)kCTFontAttributeName atIndex:index effectiveRange:NULL];
    }
    if (!font) font = _currentTypingAttributes[NSFontAttributeName];
    if (!font) font = _currentTypingAttributes[(id)kCTFontAttributeName];
    if (!font) font = _font;

    CGFloat fontAscent = _font.ascender;
    CGFloat fontDescent = -_font.descender;
    if ([font isKindOfClass:NSFont.class]) {
        NSFont *nsFont = font;
        fontAscent = nsFont.ascender;
        fontDescent = -nsFont.descender;
    } else if (font && CFGetTypeID((__bridge CFTypeRef)font) == CTFontGetTypeID()) {
        CTFontRef ctFont = (__bridge CTFontRef)font;
        fontAscent = CTFontGetAscent(ctFont);
        fontDescent = CTFontGetDescent(ctFont);
    }
    if (ascent) *ascent = ceil(MAX(fontAscent, 0));
    if (descent) *descent = ceil(MAX(fontDescent, 0));
}

- (CGRect)_caretRectForLocation:(NSUInteger)location {
    location = MIN(location, _innerText.length);
    CGFloat caretAscent = 0;
    CGFloat caretDescent = 0;
    [self _caretFontMetricsForLocation:location ascent:&caretAscent descent:&caretDescent];
    CGFloat caretHeight = caretAscent + caretDescent;
    KKTextPosition *position = [KKTextPosition positionWithOffset:location];
    CGRect rect = [_innerLayout caretRectForPosition:position];
    if (CGRectIsNull(rect)) {
        CGFloat x = _textContainerInset.left;
        CGFloat y = _textContainerInset.top;
        rect = CGRectMake(x, y, 0, caretHeight);
    } else if (!_verticalForm && caretHeight > 0) {
        CGPoint baseline = [_innerLayout linePositionForPosition:position];
        rect.size.height = caretHeight;
        rect.origin.y = baseline.y - caretAscent;
    }
    return rect;
}

- (NSRect)_firstRectForRange:(NSRange)range {
    if (!_innerLayout) [self _updateLayout];
    CGRect rect;
    if (range.length > 0) {
        rect = [_innerLayout firstRectForRange:[KKTextRange rangeWithRange:range]];
    } else {
        rect = [self _caretRectForLocation:range.location];
    }
    if (CGRectIsNull(rect)) rect = self.bounds;
    return rect;
}

#pragma mark - Text Storage

- (NSDictionary *)_defaultTypingAttributes {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.alignment = _textAlignment;
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    if (_font) attributes[NSFontAttributeName] = _font;
    if (_textColor) attributes[NSForegroundColorAttributeName] = _textColor;
    attributes[NSParagraphStyleAttributeName] = style;
    return attributes;
}

- (UIFont *)_defaultFont {
    return [NSFont systemFontOfSize:12];
}

- (NSAttributedString *)_attributedStringWithPlainText:(NSString *)text {
    return [[NSAttributedString alloc] initWithString:text ?: @"" attributes:_currentTypingAttributes];
}

- (void)_updateTypingAttributesForLocation:(NSUInteger)location {
    if (_innerText.length == 0) {
        _currentTypingAttributes = [[self _defaultTypingAttributes] mutableCopy];
        return;
    }

    NSUInteger index = location == 0 ? 0 : MIN(location - 1, _innerText.length - 1);
    NSMutableDictionary *attributes = [[_innerText kk_attributesAtIndex:index] mutableCopy] ?: [NSMutableDictionary dictionary];
    [attributes removeObjectsForKeys:[NSMutableAttributedString kk_allDiscontinuousAttributeKeys]];
    [attributes removeObjectForKey:KKTextBorderAttributeName];
    [attributes removeObjectForKey:KKTextBackgroundBorderAttributeName];
    _currentTypingAttributes = attributes;
}

- (void)_setInnerAttributedText:(NSAttributedString *)attributedText notify:(BOOL)notify {
    _innerText = attributedText ? attributedText.mutableCopy : [NSMutableAttributedString new];
    _selectedRange = KKTextViewMakeSafeRange(_selectedRange, _innerText.length);
    _markedRange = NSMakeRange(NSNotFound, 0);
    [self _parseText];
    [self _updateTypingAttributesForLocation:_selectedRange.location];
    [self _updateLayout];
    if (!_insideUndoOrRedo) {
        [self _resetUndoAndRedoStack];
    }
    if (notify) [self _notifyTextDidChange];
}

- (BOOL)_parseText {
    if (!_textParser) return NO;
    NSRange selectedRange = _selectedRange;
    BOOL changed = [_textParser parseText:_innerText selectedRange:&selectedRange];
    _selectedRange = KKTextViewMakeSafeRange(selectedRange, _innerText.length);
    return changed;
}

- (void)_replaceRange:(NSRange)range withAttributedString:(NSAttributedString *)attributedString notify:(BOOL)notify {
    range = KKTextViewMakeSafeRange(range, _innerText.length);
    NSString *replacementText = attributedString.string ?: @"";
    if (notify && _delegate && [_delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]) {
        if (![_delegate textView:self shouldChangeTextInRange:range replacementText:replacementText]) return;
    }
    if (notify) {
        [self _recordUndoBeforeEditing];
    }
    [_innerText replaceCharactersInRange:range withAttributedString:attributedString ?: [NSAttributedString new]];
    _selectedRange = NSMakeRange(range.location + attributedString.length, 0);
    _markedRange = NSMakeRange(NSNotFound, 0);
    [self _parseText];
    [self _updateTypingAttributesForLocation:_selectedRange.location];
    [self _updateLayout];
    [self scrollRangeToVisible:_selectedRange];
    if (notify) [self _notifyTextDidChange];
    [self _notifySelectionDidChange];
}

#pragma mark - Undo and Redo

- (void)_resetUndoAndRedoStack {
    [_undoStack removeAllObjects];
    [_redoStack removeAllObjects];
    if (!_allowsUndoAndRedo || _maximumUndoLevel == 0) return;
    [_undoStack addObject:[_KKTextViewUndoState stateWithText:_innerText.copy selectedRange:_selectedRange]];
}

- (void)_resetRedoStack {
    [_redoStack removeAllObjects];
}

- (void)_trimUndoStack:(NSMutableArray<_KKTextViewUndoState *> *)stack {
    while (stack.count > _maximumUndoLevel) {
        [stack removeObjectAtIndex:0];
    }
}

- (void)_trimUndoAndRedoStacks {
    [self _trimUndoStack:_undoStack];
    [self _trimUndoStack:_redoStack];
}

- (void)_saveToUndoStack {
    if (!_allowsUndoAndRedo || _maximumUndoLevel == 0) return;
    _KKTextViewUndoState *lastState = _undoStack.lastObject;
    if ([lastState.text isEqualToAttributedString:_innerText]) return;
    [_undoStack addObject:[_KKTextViewUndoState stateWithText:_innerText.copy selectedRange:_selectedRange]];
    [self _trimUndoStack:_undoStack];
}

- (void)_saveToRedoStack {
    if (!_allowsUndoAndRedo || _maximumUndoLevel == 0) return;
    _KKTextViewUndoState *lastState = _redoStack.lastObject;
    if ([lastState.text isEqualToAttributedString:_innerText]) return;
    [_redoStack addObject:[_KKTextViewUndoState stateWithText:_innerText.copy selectedRange:_selectedRange]];
    [self _trimUndoStack:_redoStack];
}

- (void)_recordUndoBeforeEditing {
    if (_insideUndoOrRedo) return;
    [self _saveToUndoStack];
    [self _resetRedoStack];
}

- (BOOL)_canUndo {
    _KKTextViewUndoState *state = _undoStack.lastObject;
    return state && ![state.text isEqualToAttributedString:_innerText];
}

- (BOOL)_canRedo {
    _KKTextViewUndoState *state = _redoStack.lastObject;
    return state && ![state.text isEqualToAttributedString:_innerText];
}

- (void)_restoreUndoState:(_KKTextViewUndoState *)state {
    if (!state) return;
    _innerText = state.text ? state.text.mutableCopy : [NSMutableAttributedString new];
    _selectedRange = KKTextViewMakeSafeRange(state.selectedRange, _innerText.length);
    _markedRange = NSMakeRange(NSNotFound, 0);
    _selectionAnchorLocation = _selectedRange.length > 0 ? NSMaxRange(_selectedRange) : _selectedRange.location;
    [self _parseText];
    [self _updateTypingAttributesForLocation:NSMaxRange(_selectedRange)];
    [self _updateLayout];
    [self scrollRangeToVisible:_selectedRange];
    [self _notifyTextDidChange];
    [self _notifySelectionDidChange];
}

- (void)_undo {
    if (![self _canUndo]) return;
    [self _saveToRedoStack];
    _KKTextViewUndoState *state = _undoStack.lastObject;
    [_undoStack removeLastObject];
    _insideUndoOrRedo = YES;
    [self _restoreUndoState:state];
    _insideUndoOrRedo = NO;
}

- (void)_redo {
    if (![self _canRedo]) return;
    [self _saveToUndoStack];
    _KKTextViewUndoState *state = _redoStack.lastObject;
    [_redoStack removeLastObject];
    _insideUndoOrRedo = YES;
    [self _restoreUndoState:state];
    _insideUndoOrRedo = NO;
}

#pragma mark - Notifications

- (void)_notifyTextDidChange {
    if (_delegate && [_delegate respondsToSelector:@selector(textViewDidChange:)]) {
        [_delegate textViewDidChange:self];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:KKTextViewTextDidChangeNotification object:self];
    [self _resetCaretBlink];
}

- (void)_notifySelectionDidChange {
    if (_delegate && [_delegate respondsToSelector:@selector(textViewDidChangeSelection:)]) {
        [_delegate textViewDidChangeSelection:self];
    }
    [self _resetCaretBlink];
}

#pragma mark - Public Properties

- (NSString *)text {
    return _innerText.string;
}

- (void)setAllowsUndoAndRedo:(BOOL)allowsUndoAndRedo {
    if (_allowsUndoAndRedo == allowsUndoAndRedo) return;
    _allowsUndoAndRedo = allowsUndoAndRedo;
    if (_allowsUndoAndRedo) {
        [self _resetUndoAndRedoStack];
    } else {
        [_undoStack removeAllObjects];
        [_redoStack removeAllObjects];
    }
}

- (void)setMaximumUndoLevel:(NSUInteger)maximumUndoLevel {
    _maximumUndoLevel = maximumUndoLevel;
    [self _trimUndoAndRedoStacks];
}

- (void)setText:(NSString *)text {
    [self _setInnerAttributedText:[self _attributedStringWithPlainText:text] notify:YES];
}

- (NSAttributedString *)attributedText {
    return _innerText.copy;
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    [self _setInnerAttributedText:attributedText notify:YES];
}

- (void)setFont:(UIFont *)font {
    _font = font ?: [self _defaultFont];
    _currentTypingAttributes = [[self _defaultTypingAttributes] mutableCopy];
    if (_innerText.length) [_innerText addAttribute:NSFontAttributeName value:_font range:NSMakeRange(0, _innerText.length)];
    [self _updateLayout];
}

- (void)setTextColor:(UIColor *)textColor {
    _textColor = textColor ?: NSColor.textColor;
    _currentTypingAttributes = [[self _defaultTypingAttributes] mutableCopy];
    if (_innerText.length) [_innerText addAttribute:NSForegroundColorAttributeName value:_textColor range:NSMakeRange(0, _innerText.length)];
    [self _updateLayout];
}

- (void)setTextAlignment:(NSTextAlignment)textAlignment {
    _textAlignment = textAlignment;
    _currentTypingAttributes = [[self _defaultTypingAttributes] mutableCopy];
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.alignment = textAlignment;
    if (_innerText.length) [_innerText addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, _innerText.length)];
    [self _updateLayout];
}

- (void)setTextVerticalAlignment:(KKTextVerticalAlignment)textVerticalAlignment {
    _textVerticalAlignment = textVerticalAlignment;
    [self setNeedsDisplay:YES];
}

- (void)setTypingAttributes:(NSDictionary *)typingAttributes {
    _typingAttributes = typingAttributes.copy;
    _currentTypingAttributes = typingAttributes ? typingAttributes.mutableCopy : [[self _defaultTypingAttributes] mutableCopy];
}

- (NSDictionary *)typingAttributes {
    return _typingAttributes ?: _currentTypingAttributes.copy;
}

- (void)setTextParser:(id<KKTextParser>)textParser {
    _textParser = textParser;
    [self _parseText];
    [self _updateLayout];
}

- (void)setTextContainerInset:(UIEdgeInsets)textContainerInset {
    _textContainerInset = textContainerInset;
    [self _updateLayout];
}

- (void)setExclusionPaths:(NSArray<UIBezierPath *> *)exclusionPaths {
    _exclusionPaths = exclusionPaths.copy;
    [self _updateLayout];
}

- (void)setVerticalForm:(BOOL)verticalForm {
    _verticalForm = verticalForm;
    [self _updateLayout];
}

- (void)setLinePositionModifier:(id<KKTextLinePositionModifier>)linePositionModifier {
    _linePositionModifier = [(id)linePositionModifier copy];
    [self _updateLayout];
}

- (void)setDebugOption:(KKTextDebugOption *)debugOption {
    _debugOption = debugOption.copy;
    [self setNeedsDisplay:YES];
}

- (void)setPlaceholderText:(NSString *)placeholderText {
    _placeholderText = placeholderText.copy;
    [self _updatePlaceholderText];
}

- (NSString *)placeholderText {
    return _placeholderInnerText.string;
}

- (void)setPlaceholderFont:(UIFont *)placeholderFont {
    _placeholderFont = placeholderFont ?: _font;
    [self _updatePlaceholderText];
}

- (UIFont *)placeholderFont {
    return _placeholderFont ?: _font;
}

- (void)setPlaceholderTextColor:(UIColor *)placeholderTextColor {
    _placeholderTextColor = placeholderTextColor ?: NSColor.placeholderTextColor;
    [self _updatePlaceholderText];
}

- (void)setPlaceholderAttributedText:(NSAttributedString *)placeholderAttributedText {
    _placeholderAttributedText = placeholderAttributedText.copy;
    _placeholderInnerText = placeholderAttributedText ? placeholderAttributedText.mutableCopy : [NSMutableAttributedString new];
    [self _updateLayout];
}

- (NSAttributedString *)placeholderAttributedText {
    return _placeholderInnerText.copy;
}

- (void)_updatePlaceholderText {
    if (_placeholderText.length == 0) {
        _placeholderInnerText = [NSMutableAttributedString new];
    } else {
        NSMutableDictionary *attributes = [[self _defaultTypingAttributes] mutableCopy];
        attributes[NSFontAttributeName] = self.placeholderFont ?: [self _defaultFont];
        attributes[NSForegroundColorAttributeName] = _placeholderTextColor ?: NSColor.placeholderTextColor;
        _placeholderInnerText = [[NSMutableAttributedString alloc] initWithString:_placeholderText attributes:attributes];
    }
    [self _updateLayout];
}

- (void)setSelectedRange:(NSRange)selectedRange {
    [self _setSelectedRange:selectedRange updateAnchor:YES];
}

- (NSRange)selectedRange {
    return _selectedRange;
}

- (void)scrollRangeToVisible:(NSRange)range {
    range = KKTextViewMakeSafeRange(range, _innerText.length);
    if (!_innerLayout) [self _updateLayout];
    CGRect rect = range.length > 0 ? [_innerLayout rectForRange:[KKTextRange rangeWithRange:range]] : [self _caretRectForLocation:range.location];
    if (CGRectIsNull(rect)) return;
    if (rect.size.width < 1) rect.size.width = 1;
    if (rect.size.height < 1) rect.size.height = 1;

    CGFloat padding = range.length > 0 ? 4 : 0;
    [self _scrollDocumentRectToVisible:rect padding:padding];
    [_textDocumentView setNeedsDisplay:YES];
}

- (void)_setSelectedRange:(NSRange)selectedRange updateAnchor:(BOOL)updateAnchor {
    _selectedRange = KKTextViewMakeSafeRange(selectedRange, _innerText.length);
    _markedRange = NSMakeRange(NSNotFound, 0);
    [self _updateTypingAttributesForLocation:NSMaxRange(_selectedRange)];
    if (updateAnchor) {
        _selectionAnchorLocation = _selectedRange.length > 0 ? NSMaxRange(_selectedRange) : _selectedRange.location;
    }
    NSUInteger visibleLocation = [self _selectionExtentLocation];
    [self scrollRangeToVisible:NSMakeRange(visibleLocation, 0)];
    [self _notifySelectionDidChange];
}

- (NSUInteger)_textLocationForPoint:(CGPoint)point {
    if (!_innerLayout) [self _updateLayout];
    CGPoint layoutPoint = [self _layoutPointFromViewPoint:point];
    KKTextPosition *position = [_innerLayout closestPositionToPoint:layoutPoint];
    if (!position || position.offset < 0) return _innerText.length;
    return MIN((NSUInteger)position.offset, _innerText.length);
}

- (NSUInteger)_textLocationForEvent:(NSEvent *)event {
    NSPoint point = [_textDocumentView convertPoint:event.locationInWindow fromView:nil];
    return [self _textLocationForPoint:point];
}

- (NSRange)_selectionRangeWithAnchor:(NSUInteger)anchor location:(NSUInteger)location {
    anchor = MIN(anchor, _innerText.length);
    location = MIN(location, _innerText.length);
    NSUInteger start = MIN(anchor, location);
    NSUInteger end = MAX(anchor, location);
    return NSMakeRange(start, end - start);
}

- (NSUInteger)_selectionExtentLocation {
    if (_selectedRange.length == 0) return _selectedRange.location;
    if (_selectionAnchorLocation == _selectedRange.location) return NSMaxRange(_selectedRange);
    if (_selectionAnchorLocation == NSMaxRange(_selectedRange)) return _selectedRange.location;
    return NSMaxRange(_selectedRange);
}

- (NSRange)_wordRangeByExtendingLayoutRange:(NSRange)range {
    range = KKTextViewMakeSafeRange(range, _innerText.length);
    if (range.length == 0) return range;
    if (!_innerLayout) [self _updateLayout];

    KKTextRange *textRange = [KKTextRange rangeWithRange:range];
    KKTextRange *extendedStart = [_innerLayout textRangeByExtendingPosition:textRange.start];
    KKTextRange *extendedEnd = [_innerLayout textRangeByExtendingPosition:textRange.end];
    if (extendedStart && extendedEnd) {
        NSArray *positions = [@[extendedStart.start, extendedStart.end, extendedEnd.start, extendedEnd.end]
                              sortedArrayUsingSelector:@selector(compare:)];
        NSRange extendedRange = [KKTextRange rangeWithStart:positions.firstObject end:positions.lastObject].asRange;
        return KKTextViewMakeSafeRange(extendedRange, _innerText.length);
    }
    return range;
}

- (NSRange)_wordRangeEnclosingLayoutRange:(NSRange)range {
    range = KKTextViewMakeSafeRange(range, _innerText.length);
    if (_innerText.length == 0) return NSMakeRange(0, 0);

    NSUInteger targetLocation = MIN(range.location, _innerText.length - 1);
    NSUInteger targetEnd = range.length > 0 ? MIN(NSMaxRange(range) - 1, _innerText.length - 1) : targetLocation;
    NSRange targetRange = NSMakeRange(targetLocation, targetEnd - targetLocation + 1);
    __block NSRange wordRange = NSMakeRange(NSNotFound, 0);
    [_innerText.string enumerateSubstringsInRange:NSMakeRange(0, _innerText.length)
                                          options:NSStringEnumerationByWords
                                       usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        if (NSIntersectionRange(substringRange, targetRange).length == 0) return;
        if (wordRange.location == NSNotFound) {
            wordRange = substringRange;
        } else {
            wordRange = NSUnionRange(wordRange, substringRange);
        }
    }];
    if (wordRange.location == NSNotFound) return wordRange;
    return [self _wordRangeByExtendingLayoutRange:wordRange];
}

- (NSRange)_wordRangeAtPoint:(CGPoint)point {
    if (_innerText.length == 0) return NSMakeRange(0, 0);
    if (!_innerLayout) [self _updateLayout];

    KKTextRange *layoutRange = [_innerLayout closestTextRangeAtPoint:point];
    if (!layoutRange || layoutRange.asRange.length == 0) {
        NSUInteger location = [self _textLocationForPoint:point];
        KKTextPosition *position = [KKTextPosition positionWithOffset:MIN(location, _innerText.length)];
        layoutRange = [_innerLayout textRangeByExtendingPosition:position inDirection:UITextLayoutDirectionRight offset:1];
        if (!layoutRange || layoutRange.asRange.length == 0) {
            layoutRange = [_innerLayout textRangeByExtendingPosition:position inDirection:UITextLayoutDirectionLeft offset:1];
        }
    }
    if (!layoutRange) {
        NSUInteger location = MIN([self _textLocationForPoint:point], _innerText.length - 1);
        return [_innerText.string rangeOfComposedCharacterSequenceAtIndex:location];
    }

    NSRange range = KKTextViewMakeSafeRange(layoutRange.asRange, _innerText.length);
    NSRange wordRange = [self _wordRangeEnclosingLayoutRange:range];
    if (wordRange.location != NSNotFound && wordRange.length > 0) return wordRange;

    if (range.length > 0) return [self _wordRangeByExtendingLayoutRange:range];

    NSUInteger safeLocation = MIN(range.location, _innerText.length - 1);
    return [_innerText.string rangeOfComposedCharacterSequenceAtIndex:safeLocation];
}

- (void)_extendSelectionToLocation:(NSUInteger)location {
    NSRange range = [self _selectionRangeWithAnchor:_selectionAnchorLocation location:location];
    [self _setSelectedRange:range updateAnchor:NO];
}

- (BOOL)_selectedRangeContainsLocation:(NSUInteger)location {
    if (_selectedRange.length == 0) return NO;
    return _selectedRange.location <= location && location <= NSMaxRange(_selectedRange);
}

- (void)_prepareContextMenuSelectionForEvent:(NSEvent *)event {
    if (!_selectable && !_editable) return;
    [self.window makeFirstResponder:self];
    NSUInteger location = [self _textLocationForEvent:event];
    if (![self _selectedRangeContainsLocation:location]) {
        _caretActive = YES;
        _selectionAnchorLocation = location;
        [self _setSelectedRange:NSMakeRange(location, 0) updateAnchor:NO];
    } else {
        [self _resetCaretBlink];
    }
}

- (NSMenuItem *)_menuItemWithTitle:(NSString *)title action:(SEL)action enabled:(BOOL)enabled {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    item.enabled = enabled;
    return item;
}

- (NSMenu *)_contextMenuForEvent:(NSEvent *)event {
    if (!_selectable && !_editable) return nil;
    [self _prepareContextMenuSelectionForEvent:event];

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    menu.autoenablesItems = NO;
    [menu addItem:[self _menuItemWithTitle:@"Undo" action:@selector(undo:) enabled:[self canPerformAction:@selector(undo:) withSender:menu]]];
    [menu addItem:[self _menuItemWithTitle:@"Redo" action:@selector(redo:) enabled:[self canPerformAction:@selector(redo:) withSender:menu]]];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:[self _menuItemWithTitle:@"Cut" action:@selector(cut:) enabled:[self canPerformAction:@selector(cut:) withSender:menu]]];
    [menu addItem:[self _menuItemWithTitle:@"Copy" action:@selector(copy:) enabled:[self canPerformAction:@selector(copy:) withSender:menu]]];
    [menu addItem:[self _menuItemWithTitle:@"Paste" action:@selector(paste:) enabled:[self canPerformAction:@selector(paste:) withSender:menu]]];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:[self _menuItemWithTitle:@"Select All" action:@selector(selectAll:) enabled:[self canPerformAction:@selector(selectAll:) withSender:menu]]];
    return menu;
}

#pragma mark - Events

- (void)mouseDown:(NSEvent *)event {
    if (!_selectable && !_editable) return;
    [self.window makeFirstResponder:self];
    _caretActive = YES;

    if (event.clickCount >= 2) {
        CGPoint point = [self _viewPointForEvent:event];
        NSRange range = [self _wordRangeAtPoint:point];
        [self _setSelectedRange:range updateAnchor:YES];
        _trackingSelection = NO;
    } else {
        NSUInteger location = [self _textLocationForEvent:event];
        if ((event.modifierFlags & NSEventModifierFlagShift) != 0) {
            if (_selectedRange.length == 0) _selectionAnchorLocation = _selectedRange.location;
            [self _extendSelectionToLocation:location];
        } else {
            _selectionAnchorLocation = location;
            [self _setSelectedRange:NSMakeRange(location, 0) updateAnchor:NO];
        }
        _trackingSelection = YES;
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_trackingSelection || (!_selectable && !_editable)) return;
    NSUInteger location = [self _textLocationForEvent:event];
    [self _extendSelectionToLocation:location];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    _trackingSelection = NO;
}

- (void)rightMouseDown:(NSEvent *)event {
    NSMenu *menu = [self _contextMenuForEvent:event];
    if (menu) {
        [NSMenu popUpContextMenu:menu withEvent:event forView:_textDocumentView ?: self];
    } else {
        [super rightMouseDown:event];
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    return [self _contextMenuForEvent:event];
}

- (void)keyDown:(NSEvent *)event {
    if (!_editable) {
        [super keyDown:event];
        return;
    }
    _caretActive = YES;
    [self _resetCaretBlink];
    [self interpretKeyEvents:@[event]];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if ((event.modifierFlags & NSEventModifierFlagCommand) == 0) return [super performKeyEquivalent:event];
    NSString *characters = event.charactersIgnoringModifiers.lowercaseString;
    BOOL shiftPressed = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    if ([characters isEqualToString:@"z"]) {
        shiftPressed ? [self _redo] : [self _undo];
        return YES;
    }
    if ([characters isEqualToString:@"y"]) {
        [self _redo];
        return YES;
    }
    if ([characters isEqualToString:@"a"]) {
        [self selectAll:nil];
        return YES;
    }
    if ([characters isEqualToString:@"c"]) {
        [self copy:nil];
        return YES;
    }
    if ([characters isEqualToString:@"x"]) {
        [self cut:nil];
        return YES;
    }
    if ([characters isEqualToString:@"v"]) {
        [self paste:nil];
        return YES;
    }
    return [super performKeyEquivalent:event];
}

#pragma mark - Edit Actions

- (void)insertText:(NSString *)text {
    [self insertText:text replacementRange:NSMakeRange(NSNotFound, 0)];
}

- (void)deleteBackward {
    [self deleteBackward:nil];
}

- (void)undo:(id)sender {
    (void)sender;
    [self _undo];
}

- (void)redo:(id)sender {
    (void)sender;
    [self _redo];
}

- (void)deleteBackward:(id)sender {
    if (!_editable || _innerText.length == 0) return;
    NSRange range = self.hasMarkedText ? _markedRange : _selectedRange;
    if (range.length == 0) {
        if (range.location == 0) return;
        range.location -= 1;
        range.length = 1;
    }
    [self _replaceRange:range withAttributedString:[NSAttributedString new] notify:YES];
}

- (void)insertNewline:(id)sender {
    [self insertText:@"\n" replacementRange:NSMakeRange(NSNotFound, 0)];
}

- (void)insertTab:(id)sender {
    [self insertText:@"\t" replacementRange:NSMakeRange(NSNotFound, 0)];
}

- (void)moveLeft:(id)sender {
    if (_selectedRange.length > 0) {
        self.selectedRange = NSMakeRange(_selectedRange.location, 0);
    } else if (_selectedRange.location > 0) {
        self.selectedRange = NSMakeRange(_selectedRange.location - 1, 0);
    }
}

- (void)moveRight:(id)sender {
    if (_selectedRange.length > 0) {
        self.selectedRange = NSMakeRange(NSMaxRange(_selectedRange), 0);
    } else if (_selectedRange.location < _innerText.length) {
        self.selectedRange = NSMakeRange(_selectedRange.location + 1, 0);
    }
}

- (void)moveLeftAndModifySelection:(id)sender {
    NSUInteger location = [self _selectionExtentLocation];
    if (_selectedRange.length == 0) _selectionAnchorLocation = _selectedRange.location;
    if (location > 0) location--;
    [self _extendSelectionToLocation:location];
}

- (NSUInteger)_locationByMovingFromLocation:(NSUInteger)location inDirection:(UITextLayoutDirection)direction {
    [self _updateLayout];
    location = MIN(location, _innerText.length);
    KKTextPosition *position = [KKTextPosition positionWithOffset:location];
    KKTextRange *range = [_innerLayout textRangeByExtendingPosition:position inDirection:direction offset:1];
    if (!range) return location;

    NSUInteger targetLocation;
    if (direction == UITextLayoutDirectionUp || direction == UITextLayoutDirectionLeft) {
        targetLocation = MIN((NSUInteger)MAX(range.start.offset, 0), _innerText.length);
    } else {
        targetLocation = MIN((NSUInteger)MAX(range.end.offset, 0), _innerText.length);
    }

    if ((direction == UITextLayoutDirectionUp || direction == UITextLayoutDirectionDown) &&
        targetLocation == location && location > 0) {
        NSString *textBeforeLocation = [_innerText.string substringToIndex:location];
        NSUInteger lineBreakTailLength = KKTextLinebreakTailLength(textBeforeLocation);
        if (lineBreakTailLength > 0) {
            targetLocation = location - lineBreakTailLength;
        }
    }
    return targetLocation;
}

- (void)_moveSelectionEndpointInDirection:(UITextLayoutDirection)direction {
    NSUInteger location = [self _selectionExtentLocation];
    if (_selectedRange.length == 0) _selectionAnchorLocation = _selectedRange.location;
    location = [self _locationByMovingFromLocation:location inDirection:direction];
    [self _extendSelectionToLocation:location];
}

- (void)moveUp:(id)sender {
    (void)sender;
    if (_selectedRange.length > 0) {
        self.selectedRange = NSMakeRange(_selectedRange.location, 0);
        return;
    }
    NSUInteger location = [self _locationByMovingFromLocation:_selectedRange.location inDirection:UITextLayoutDirectionUp];
    self.selectedRange = NSMakeRange(location, 0);
}

- (void)moveDown:(id)sender {
    (void)sender;
    if (_selectedRange.length > 0) {
        self.selectedRange = NSMakeRange(NSMaxRange(_selectedRange), 0);
        return;
    }
    NSUInteger location = [self _locationByMovingFromLocation:_selectedRange.location inDirection:UITextLayoutDirectionDown];
    self.selectedRange = NSMakeRange(location, 0);
}

- (void)moveUpAndModifySelection:(id)sender {
    (void)sender;
    [self _moveSelectionEndpointInDirection:UITextLayoutDirectionUp];
}

- (void)moveDownAndModifySelection:(id)sender {
    (void)sender;
    [self _moveSelectionEndpointInDirection:UITextLayoutDirectionDown];
}

- (void)moveRightAndModifySelection:(id)sender {
    NSUInteger location = [self _selectionExtentLocation];
    if (_selectedRange.length == 0) _selectionAnchorLocation = _selectedRange.location;
    if (location < _innerText.length) location++;
    [self _extendSelectionToLocation:location];
}

- (void)moveToBeginningOfDocument:(id)sender {
    self.selectedRange = NSMakeRange(0, 0);
}

- (void)moveToEndOfDocument:(id)sender {
    self.selectedRange = NSMakeRange(_innerText.length, 0);
}

- (void)moveToBeginningOfDocumentAndModifySelection:(id)sender {
    if (_selectedRange.length == 0) _selectionAnchorLocation = _selectedRange.location;
    [self _extendSelectionToLocation:0];
}

- (void)moveToEndOfDocumentAndModifySelection:(id)sender {
    if (_selectedRange.length == 0) _selectionAnchorLocation = _selectedRange.location;
    [self _extendSelectionToLocation:_innerText.length];
}

- (void)selectAll:(id)sender {
    if (!_selectable) return;
    self.selectedRange = NSMakeRange(0, _innerText.length);
}

- (NSData *)_RTFDataForAttributedString:(NSAttributedString *)attributedString {
    if (attributedString.length == 0) return nil;
    NSDictionary *documentAttributes = @{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType};
    NSData *data = nil;
    @try {
        data = [attributedString dataFromRange:NSMakeRange(0, attributedString.length)
                            documentAttributes:documentAttributes
                                         error:nil];
    } @catch (__unused NSException *exception) {
        data = nil;
    }
    return data;
}

- (NSAttributedString *)_attributedStringFromRTFData:(NSData *)data {
    if (data.length == 0) return nil;
    NSDictionary *options = @{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType};
    NSAttributedString *attributedString = nil;
    @try {
        attributedString = [[NSAttributedString alloc] initWithData:data
                                                            options:options
                                                 documentAttributes:nil
                                                              error:nil];
    } @catch (__unused NSException *exception) {
        attributedString = nil;
    }
    return attributedString.length > 0 ? attributedString : nil;
}

- (NSAttributedString *)_attributedStringFromPasteboard:(NSPasteboard *)pasteboard {
    if (!pasteboard) return nil;
    if (_allowsPasteAttributedString) {
        NSData *data = [pasteboard dataForType:KKTextViewPasteboardTypeAttributedString];
        if (data.length > 0) {
            NSAttributedString *attributedString = [NSAttributedString kk_unarchiveFromData:data];
            if (attributedString.length > 0) return attributedString;
        }

        data = [pasteboard dataForType:NSPasteboardTypeRTF];
        NSAttributedString *rtfString = [self _attributedStringFromRTFData:data];
        if (rtfString.length > 0) return rtfString;
    }

    NSString *string = [pasteboard stringForType:NSPasteboardTypeString];
    if (string.length == 0) return nil;
    return [self _attributedStringWithPlainText:string];
}

- (BOOL)_isPasteboardContainsValidValue {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    if ([pasteboard stringForType:NSPasteboardTypeString].length > 0) return YES;
    if (_allowsPasteAttributedString) {
        if ([pasteboard dataForType:KKTextViewPasteboardTypeAttributedString].length > 0) return YES;
        if ([pasteboard dataForType:NSPasteboardTypeRTF].length > 0) return YES;
    }
    return NO;
}

- (void)copy:(id)sender {
    if (_selectedRange.length == 0) return;

    NSAttributedString *attributedString = [_innerText attributedSubstringFromRange:_selectedRange];
    NSString *plainText = [_innerText kk_plainTextForRange:_selectedRange];
    if (plainText.length == 0) plainText = attributedString.string ?: @"";

    NSData *archivedData = nil;
    NSData *rtfData = nil;
    NSMutableArray<NSPasteboardType> *types = [NSMutableArray array];
    if (plainText.length > 0) {
        [types addObject:NSPasteboardTypeString];
    }
    if (_allowsCopyAttributedString && attributedString.length > 0) {
        archivedData = [attributedString kk_archiveToData];
        if (archivedData.length > 0) {
            [types addObject:KKTextViewPasteboardTypeAttributedString];
        }
        rtfData = [self _RTFDataForAttributedString:attributedString];
        if (rtfData.length > 0) {
            [types addObject:NSPasteboardTypeRTF];
        }
    }
    if (types.count == 0) return;

    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard declareTypes:types owner:nil];
    if (plainText.length > 0) {
        [pasteboard setString:plainText forType:NSPasteboardTypeString];
    }
    if (archivedData.length > 0) {
        [pasteboard setData:archivedData forType:KKTextViewPasteboardTypeAttributedString];
    }
    if (rtfData.length > 0) {
        [pasteboard setData:rtfData forType:NSPasteboardTypeRTF];
    }
}

- (void)cut:(id)sender {
    if (!_editable || _selectedRange.length == 0) return;
    [self copy:sender];
    [self _replaceRange:_selectedRange withAttributedString:[NSAttributedString new] notify:YES];
}

- (void)paste:(id)sender {
    if (!_editable) return;
    NSAttributedString *attributedString = [self _attributedStringFromPasteboard:NSPasteboard.generalPasteboard];
    if (attributedString.length == 0) return;
    [self insertText:attributedString replacementRange:NSMakeRange(NSNotFound, 0)];
}

#pragma mark - NSTextInputClient

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
    if (!_editable) return;
    _caretActive = YES;
    NSAttributedString *attributedString;
    if ([string isKindOfClass:NSAttributedString.class]) {
        attributedString = string;
    } else {
        attributedString = [self _attributedStringWithPlainText:[string description]];
    }
    NSRange replaceRange = replacementRange.location != NSNotFound ? replacementRange : (self.hasMarkedText ? _markedRange : _selectedRange);
    [self _replaceRange:replaceRange withAttributedString:attributedString notify:YES];
}

- (void)doCommandBySelector:(SEL)selector {
    if (selector == @selector(deleteBackward:)) {
        [self deleteBackward:nil];
    } else if (selector == @selector(insertNewline:)) {
        [self insertNewline:nil];
    } else if (selector == @selector(insertTab:)) {
        [self insertTab:nil];
    } else if (selector == @selector(moveLeft:)) {
        [self moveLeft:nil];
    } else if (selector == @selector(moveRight:)) {
        [self moveRight:nil];
    } else if (selector == @selector(moveUp:)) {
        [self moveUp:nil];
    } else if (selector == @selector(moveDown:)) {
        [self moveDown:nil];
    } else if (selector == @selector(moveLeftAndModifySelection:)) {
        [self moveLeftAndModifySelection:nil];
    } else if (selector == @selector(moveRightAndModifySelection:)) {
        [self moveRightAndModifySelection:nil];
    } else if (selector == @selector(moveUpAndModifySelection:)) {
        [self moveUpAndModifySelection:nil];
    } else if (selector == @selector(moveDownAndModifySelection:)) {
        [self moveDownAndModifySelection:nil];
    } else if (selector == @selector(moveToBeginningOfDocument:)) {
        [self moveToBeginningOfDocument:nil];
    } else if (selector == @selector(moveToEndOfDocument:)) {
        [self moveToEndOfDocument:nil];
    } else if (selector == @selector(moveToBeginningOfDocumentAndModifySelection:)) {
        [self moveToBeginningOfDocumentAndModifySelection:nil];
    } else if (selector == @selector(moveToEndOfDocumentAndModifySelection:)) {
        [self moveToEndOfDocumentAndModifySelection:nil];
    } else if (selector == @selector(undo:)) {
        [self undo:nil];
    } else if (selector == @selector(redo:)) {
        [self redo:nil];
    }
}

- (NSAttributedString *)_markedTextWithInput:(id)string selectedRange:(NSRange)selectedRange {
    NSMutableAttributedString *markedText;
    if ([string isKindOfClass:NSAttributedString.class]) {
        markedText = [(NSAttributedString *)string mutableCopy];
    } else {
        NSString *plainText = string ? [string description] : @"";
        markedText = [[NSMutableAttributedString alloc] initWithString:plainText];
    }
    NSRange fullRange = NSMakeRange(0, markedText.length);
    if (fullRange.length == 0) return markedText;

    [_currentTypingAttributes enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        (void)stop;
        [markedText addAttribute:key value:obj range:fullRange];
    }];
    if (_font &&
        ![markedText attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] &&
        ![markedText attribute:(id)kCTFontAttributeName atIndex:0 effectiveRange:NULL]) {
        [markedText addAttribute:NSFontAttributeName value:_font range:fullRange];
    }
    if (_textColor &&
        ![markedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] &&
        ![markedText attribute:(id)kCTForegroundColorAttributeName atIndex:0 effectiveRange:NULL]) {
        [markedText addAttribute:NSForegroundColorAttributeName value:_textColor range:fullRange];
    }
    [markedText addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:fullRange];
    [markedText addAttribute:NSUnderlineColorAttributeName value:NSColor.keyboardFocusIndicatorColor range:fullRange];

    KKTextBorder *border = [KKTextBorder borderWithFillColor:[NSColor.keyboardFocusIndicatorColor colorWithAlphaComponent:0.10] cornerRadius:3];
    border.insets = UIEdgeInsetsMake(-1, -2, -1, -2);
    [markedText kk_setTextBackgroundBorder:border range:fullRange];

    NSRange selectedMarkedRange = KKTextViewMakeSafeRange(selectedRange, markedText.length);
    if (selectedMarkedRange.length > 0) {
        KKTextBorder *selectedBorder = [KKTextBorder borderWithFillColor:[NSColor.keyboardFocusIndicatorColor colorWithAlphaComponent:0.18] cornerRadius:3];
        selectedBorder.insets = UIEdgeInsetsMake(-1, -2, -1, -2);
        [markedText kk_setTextBackgroundBorder:selectedBorder range:selectedMarkedRange];
    }
    return markedText;
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange {
    if (!_editable) return;
    _caretActive = YES;
    BOOL startsMarkedText = !self.hasMarkedText;
    NSAttributedString *markedText = [self _markedTextWithInput:string selectedRange:selectedRange];
    NSRange replaceRange = replacementRange.location != NSNotFound ? replacementRange : (self.hasMarkedText ? _markedRange : _selectedRange);
    replaceRange = KKTextViewMakeSafeRange(replaceRange, _innerText.length);
    if (startsMarkedText) {
        [self _recordUndoBeforeEditing];
    }
    [_innerText replaceCharactersInRange:replaceRange withAttributedString:markedText];
    _markedRange = NSMakeRange(replaceRange.location, markedText.length);
    _selectedRange = NSMakeRange(_markedRange.location + selectedRange.location, selectedRange.length);
    _selectedRange = KKTextViewMakeSafeRange(_selectedRange, _innerText.length);
    [self _updateTypingAttributesForLocation:NSMaxRange(_selectedRange)];
    [self _updateLayout];
    [self scrollRangeToVisible:_selectedRange];
    [self _notifyTextDidChange];
    [self _notifySelectionDidChange];
}

- (void)unmarkText {
    if (!self.hasMarkedText) return;
    NSRange markedRange = KKTextViewMakeSafeRange(_markedRange, _innerText.length);
    if (markedRange.length > 0) {
        [_innerText setAttributes:_currentTypingAttributes range:markedRange];
        [_innerText kk_removeDiscontinuousAttributesInRange:markedRange];
    }
    _markedRange = NSMakeRange(NSNotFound, 0);
    [self _parseText];
    [self _updateLayout];
    [self _resetCaretBlink];
}

- (BOOL)hasMarkedText {
    return _markedRange.location != NSNotFound && _markedRange.length > 0;
}

- (NSRange)markedRange {
    return self.hasMarkedText ? _markedRange : NSMakeRange(NSNotFound, 0);
}

- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText {
    return @[NSFontAttributeName,
             NSForegroundColorAttributeName,
             NSParagraphStyleAttributeName,
             NSUnderlineStyleAttributeName,
             NSUnderlineColorAttributeName,
             NSMarkedClauseSegmentAttributeName];
}

- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    range = KKTextViewMakeSafeRange(range, _innerText.length);
    if (actualRange) *actualRange = range;
    return [_innerText attributedSubstringFromRange:range];
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point {
    if (!self.window) return NSNotFound;
    NSPoint windowPoint = [self.window convertPointFromScreen:point];
    NSPoint viewPoint = [_textDocumentView convertPoint:windowPoint fromView:nil];
    if (!_innerLayout) [self _updateLayout];
    CGPoint layoutPoint = [self _layoutPointFromViewPoint:viewPoint];
    KKTextPosition *position = [_innerLayout closestPositionToPoint:layoutPoint];
    return position ? MIN((NSUInteger)position.offset, _innerText.length) : NSNotFound;
}

- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    range = KKTextViewMakeSafeRange(range, _innerText.length);
    if (actualRange) *actualRange = range;
    NSRect rect = [self _viewRectFromLayoutRect:[self _firstRectForRange:range]];
    rect = [_textDocumentView convertRect:rect toView:nil];
    return self.window ? [self.window convertRectToScreen:rect] : rect;
}

- (CGFloat)fractionOfDistanceThroughGlyphForPoint:(NSPoint)point {
    (void)point;
    return 0;
}

- (NSInteger)windowLevel {
    return self.window.level;
}

#pragma mark - Compatibility

- (BOOL)canBecomeFirstResponder {
    return [self acceptsFirstResponder];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    if (item.action == @selector(undo:)) return [self _canUndo];
    if (item.action == @selector(redo:)) return [self _canRedo];
    return YES;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(copy:)) return _selectedRange.length > 0;
    if (action == @selector(cut:)) return _editable && _selectedRange.length > 0;
    if (action == @selector(paste:)) return _editable && [self _isPasteboardContainsValidValue];
    if (action == @selector(selectAll:)) return (_selectable || _editable) && _innerText.length > 0;
    if (action == @selector(undo:)) return _editable && [self _canUndo];
    if (action == @selector(redo:)) return _editable && [self _canRedo];
    return [super respondsToSelector:action];
}

@end

@implementation _KKTextViewDocumentView

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [self.textView _drawDocumentViewInRect:dirtyRect];
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
