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
#import "KKTextViewDocumentView.h"
#import "KKTextViewParagraphContainerView.h"
#import "KKTextViewSelectionView.h"
#import "KKTextUtilities.h"
#import "KKTextWeakProxy.h"
#import "NSAttributedString+KKText.h"

NSString *const KKTextViewTextDidBeginEditingNotification = @"KKTextViewTextDidBeginEditing";
NSString *const KKTextViewTextDidChangeNotification = @"KKTextViewTextDidChange";
NSString *const KKTextViewTextDidEndEditingNotification = @"KKTextViewTextDidEndEditing";

static NSPasteboardType const KKTextViewPasteboardTypeAttributedString = @"com.ibireme.NSAttributedString";

// Clamp every externally supplied range to the current text length first.
// AppKit IME, mouse hit testing, and undo/redo restore paths may provide stale ranges; using them directly on an attributed string would go out of bounds.
static NSRange KKTextViewMakeSafeRange(NSRange range, NSUInteger length) {
    if (range.location == NSNotFound) return NSMakeRange(length, 0);
    if (range.location > length) range.location = length;
    if (range.length > length - range.location) range.length = length - range.location;
    return range;
}

static const NSTimeInterval KKTextViewCaretBlinkInterval = 0.5;
static const CGFloat KKTextViewSelectionAlpha = 0.2;
static const NSUInteger KKTextViewDefaultMaximumUndoLevel = 20;

// KKTextLayout text drawing follows the UIKit/Core Text coordinate direction.
// AppKit's default CGContext coordinates do not match it, so body text drawing needs one flip.
static inline void KKTextViewFlipContextVertically(CGContextRef context, CGSize size) {
    CGContextTranslateCTM(context, 0, size.height);
    CGContextScaleCTM(context, 1, -1);
}

// Undo/Redo currently uses full text snapshots to keep edit restoration simple and reliable.
// If large-text performance needs further optimization, this can later be replaced with an operation/diff model.
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

@interface KKTextView ()
@property (nullable, nonatomic, strong, readwrite) KKTextLayout *textLayout;
- (void)_drawDocumentViewInRect:(NSRect)dirtyRect;
- (void)_drawParagraphContainerView:(_KKTextViewParagraphContainerView *)paragraphView inRect:(NSRect)dirtyRect;
- (void)_drawSelectionViewInRect:(NSRect)dirtyRect;
@end

@implementation KKTextView {
    // Basic text state. _innerText is the only real text storage, and paragraph layouts are derived from it.
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

    // Selection and IME state.
    // _selectedRange is a global range; _markedRange is the IME pre-edit range; _selectionAnchorLocation is used for drag selection and Shift extension.
    NSRange _selectedRange;
    NSRange _markedRange;
    NSUInteger _selectionAnchorLocation;

    // AppKit view hierarchy.
    // _textDocumentView is the NSScrollView documentView; _selectionView is a separate overlay above the text.
    _KKTextViewDocumentView *_textDocumentView;
    _KKTextViewSelectionView *_selectionView;

    // Paragraph layout state.
    // Each paragraph context stores the global range, local layout, and paragraph view for one text paragraph.
    NSMutableArray<_KKTextViewParagraphContext *> *_paragraphContexts;
    CGSize _paragraphContentSize;
    CGSize _documentSize;

    // Undo/Redo snapshot stacks.
    NSMutableArray<_KKTextViewUndoState *> *_undoStack;
    NSMutableArray<_KKTextViewUndoState *> *_redoStack;
    NSTimer *_caretBlinkTimer;

    // Records the range shift before and after one edit, so rebuilt paragraph contexts can reuse old layouts where possible.
    NSRange _pendingParagraphEditNewRange;
    NSInteger _pendingParagraphEditDelta;
    BOOL _hasPendingParagraphEdit;

    // Interaction state.
    BOOL _caretVisible;
    BOOL _caretActive;
    BOOL _trackingSelection;
    BOOL _editing;
    BOOL _insideUndoOrRedo;

    // Cache the target x during vertical keyboard movement so repeated up/down keys do not drift with line width changes.
    CGFloat _verticalMovementTargetX;
    BOOL _hasVerticalMovementTargetX;
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
    // The timer is retained by the run loop, so it must be invalidated explicitly before deallocation.
    [_caretBlinkTimer invalidate];
}

- (BOOL)acceptsFirstResponder {
    // Read-only but selectable text still needs to become first responder for keyboard movement, copy, and menu actions.
    return _editable || _selectable;
}

- (BOOL)becomeFirstResponder {
    // The delegate may prevent entering the editing state.
    if (_delegate && [_delegate respondsToSelector:@selector(textViewShouldBeginEditing:)] && ![_delegate textViewShouldBeginEditing:self]) {
        return NO;
    }
    [super becomeFirstResponder];
    // AppKit may call becomeFirstResponder repeatedly; send the editing-began notification only once.
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
    // The delegate may prevent ending editing, for example to keep focus after validation fails.
    if (_delegate && [_delegate respondsToSelector:@selector(textViewShouldEndEditing:)] && ![_delegate textViewShouldEndEditing:self]) {
        return NO;
    }
    BOOL result = [super resignFirstResponder];
    if (result) {
        // After actually leaving first responder, commit/clear marked text and send the editing-ended notification.
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
    // Make KKTextView work as an NSScrollView: scroll bars, clipping, and content offset are handled by NSScrollView.
    self.wantsLayer = YES;
    self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
    self.borderType = NSNoBorder;
    self.drawsBackground = NO;
    self.hasVerticalScroller = YES;
    self.hasHorizontalScroller = YES;
    self.autohidesScrollers = YES;
    self.contentView.postsBoundsChangedNotifications = YES;

    // The documentView hosts all text paragraph views and the selection view.
    _textDocumentView = [[_KKTextViewDocumentView alloc] initWithFrame:(NSRect){CGPointZero, self.bounds.size}];
    _textDocumentView.textView = self;
    _textDocumentView.wantsLayer = YES;
    _textDocumentView.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
    self.documentView = _textDocumentView;

    // The selectionView sits above the documentView and only draws selection/caret, not body text.
    _selectionView = [[_KKTextViewSelectionView alloc] initWithFrame:_textDocumentView.bounds];
    _selectionView.textView = self;
    _selectionView.wantsLayer = YES;
    _selectionView.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
    [_textDocumentView addSubview:_selectionView];

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
    _paragraphContexts = [NSMutableArray new];
    _innerContainer = [KKTextContainer containerWithSize:self.bounds.size];
    // Typing attributes are used for new input, IME marked text, empty-text caret, and trailing sentinel/probe text.
    _currentTypingAttributes = [[self _defaultTypingAttributes] mutableCopy];
    [self _updateLayout];
    [self _resetUndoAndRedoStack];
}

#pragma mark - Layout and Drawing

- (void)setFrame:(NSRect)frameRect {
    CGSize oldSize = self.bounds.size;
    [super setFrame:frameRect];
    // Frame size changes can alter the layout width; position-only changes do not require relayout.
    if (!CGSizeEqualToSize(oldSize, self.bounds.size)) {
        [self _updateLayout];
    }
}

- (void)setBounds:(NSRect)bounds {
    CGSize oldSize = self.bounds.size;
    [super setBounds:bounds];
    // Bounds origin changes are usually scrolling and do not relayout; only bounds size changes rebuild layout.
    if (!CGSizeEqualToSize(oldSize, self.bounds.size)) {
        [self _updateLayout];
    }
}

- (void)setNeedsDisplay:(BOOL)needsDisplay {
    [super setNeedsDisplay:needsDisplay];
    // When external code requests redraw, notify the document, selection, and all paragraph views together.
    [_textDocumentView setNeedsDisplay:needsDisplay];
    [_selectionView setNeedsDisplay:needsDisplay];
    for (_KKTextViewParagraphContext *context in _paragraphContexts) {
        [context.contentView setNeedsDisplay:needsDisplay];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
}

- (void)_drawDocumentViewInRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    // With paragraph containers, body text is drawn by each paragraph view, so documentView no longer draws body text.
    if ([self _usesParagraphContainerViews]) return;

    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    if (!context) return;
    CGSize drawSize = _textDocumentView.bounds.size;
    CGContextSaveGState(context); {
        // The fallback global layout still needs the AppKit/Core Text coordinate flip.
        KKTextViewFlipContextVertically(context, drawSize);
        KKTextLayout *layout = _innerText.length > 0 ? _innerLayout : _placeholderLayout;
        [layout drawInContext:context size:drawSize point:CGPointZero view:_textDocumentView layer:_textDocumentView.layer debug:_debugOption cancel:nil];
    } CGContextRestoreGState(context);
}

- (CGSize)_visibleSize {
    CGSize size = self.contentView.bounds.size;
    // Defend against negative sizes during initialization or constraint updates.
    size.width = MAX(size.width, 0);
    size.height = MAX(size.height, 0);
    return size;
}

- (BOOL)_usesParagraphContainerViews {
    // Paragraph layout currently supports only normal horizontal text.
    // Empty text needs the placeholder/caret fallback; vertical text and exclusionPaths still use the global layout to avoid broken wrapping or vertical semantics after paragraph splitting.
    return _innerText.length > 0 && !_verticalForm && _exclusionPaths.count == 0;
}

- (CGSize)_paragraphLayoutContainerSize {
    // For horizontal paragraphs, width equals the visible width and height grows naturally with paragraph content.
    CGSize size = [self _visibleSize];
    size.height = CGFLOAT_MAX;
    return size;
}

- (KKTextContainer *)_paragraphContainerWithSize:(CGSize)size {
    // A paragraph view's y position is controlled by the outer layout, so only left/right insets are kept here.
    UIEdgeInsets insets = UIEdgeInsetsMake(0, _textContainerInset.left, 0, _textContainerInset.right);
    KKTextContainer *container = [KKTextContainer containerWithSize:size insets:insets];
    container.linePositionModifier = _linePositionModifier;
    return container;
}

- (NSArray<NSValue *> *)_paragraphContentRanges {
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSString *string = _innerText.string;
    NSUInteger length = string.length;
    NSUInteger location = 0;
    // Split paragraphs by line breaks into their visible text ranges; the line break itself is not stored in context.text.
    while (location < length) {
        NSUInteger start = location;
        while (location < length && !KKTextIsLinebreakChar([string characterAtIndex:location])) {
            location++;
        }
        [ranges addObject:[NSValue valueWithRange:NSMakeRange(start, location - start)]];
        if (location < length) {
            // Skip the paragraph-ending line break; treat CRLF as one line-break unit.
            unichar c = [string characterAtIndex:location];
            location++;
            if (c == '\r' && location < length && [string characterAtIndex:location] == '\n') {
                location++;
            }
        }
    }
    // Empty text or text ending with a line break needs an extra empty paragraph for the final empty-line caret/selection.
    if (length == 0 || KKTextLinebreakTailLength(string) > 0) {
        [ranges addObject:[NSValue valueWithRange:NSMakeRange(length, 0)]];
    }
    return ranges;
}

- (void)_applyHiddenLayoutAttributesToText:(NSMutableAttributedString *)text {
    // Hidden tail/probe text is only used for layout measurement; it must not be visible or carry border-like decoration attributes.
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
    // Keep the original line-break string and attribute base, but turn it into transparent layout helper text.
    NSMutableAttributedString *hiddenText = text.mutableCopy ?: [NSMutableAttributedString new];
    [self _applyHiddenLayoutAttributesToText:hiddenText];
    return hiddenText;
}

- (_KKTextViewParagraphContext *)_paragraphContextWithRange:(NSRange)range {
    // The context bridges global text storage and local paragraph layout.
    _KKTextViewParagraphContext *context = [_KKTextViewParagraphContext new];
    context.range = KKTextViewMakeSafeRange(range, _innerText.length);
    // context.text contains only this paragraph's real visible text, excluding the trailing line break.
    if (context.range.length > 0) {
        context.text = [[_innerText attributedSubstringFromRange:context.range] mutableCopy];
    } else {
        context.text = [NSMutableAttributedString new];
    }

    NSUInteger lineBreakLocation = NSMaxRange(context.range);
    NSUInteger lineBreakLength = 0;
    // Record the line-break range after this paragraph for cross-paragraph selection and paragraph-height calculation.
    if (lineBreakLocation < _innerText.length) {
        unichar c = [_innerText.string characterAtIndex:lineBreakLocation];
        if (KKTextIsLinebreakChar(c)) {
            lineBreakLength = 1;
            // CRLF must be treated as one line-break unit; otherwise range mapping would split one line break into two paragraphs.
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

- (NSDictionary *)_paragraphSentinelAttributesForContext:(_KKTextViewParagraphContext *)context {
    NSMutableDictionary *attributes = nil;
    // Put a sentinel at the end of a paragraph that does not end with a real line break to generate an end caret.
    // It inherits the last real character's attributes when present, or current typing attributes for an empty paragraph.
    if (context.text.length > 0) {
        attributes = [[context.text kk_attributesAtIndex:context.text.length - 1] mutableCopy];
    } else {
        attributes = [_currentTypingAttributes mutableCopy];
    }
    if (!attributes) attributes = [[self _defaultTypingAttributes] mutableCopy];
    // The sentinel is a hidden layout character and must not carry border/discontinuous attributes into layout.
    [attributes removeObjectsForKeys:[NSMutableAttributedString kk_allDiscontinuousAttributeKeys]];
    [attributes removeObjectForKey:KKTextBorderAttributeName];
    [attributes removeObjectForKey:KKTextBackgroundBorderAttributeName];
    // Make it transparent so it affects only caret/layout and is never visible.
    UIColor *clearColor = UIColor.clearColor;
    attributes[NSForegroundColorAttributeName] = clearColor;
    attributes[(id)kCTForegroundColorAttributeName] = (id)clearColor.CGColor;
    return attributes;
}

- (NSDictionary *)_paragraphProbeAttributesForContext:(_KKTextViewParagraphContext *)context {
    NSMutableDictionary *attributes = nil;
    // The probe simulates the next paragraph's first-line attributes to calculate the real advance from this paragraph to the next.
    if (context.text.length > 0) {
        attributes = [[context.text kk_attributesAtIndex:0] mutableCopy];
    } else if (context.range.location < _innerText.length) {
        // Empty paragraphs have no text, so fall back to their attribute position in the global string.
        attributes = [[_innerText kk_attributesAtIndex:context.range.location] mutableCopy];
    } else {
        // A trailing empty paragraph uses the current typing attributes.
        attributes = [_currentTypingAttributes mutableCopy];
    }
    if (!attributes) attributes = [[self _defaultTypingAttributes] mutableCopy];
    // The probe is also measurement-only and must not be visible or carry decoration attributes.
    [attributes removeObjectsForKeys:[NSMutableAttributedString kk_allDiscontinuousAttributeKeys]];
    [attributes removeObjectForKey:KKTextBorderAttributeName];
    [attributes removeObjectForKey:KKTextBackgroundBorderAttributeName];
    UIColor *clearColor = UIColor.clearColor;
    attributes[NSForegroundColorAttributeName] = clearColor;
    attributes[(id)kCTForegroundColorAttributeName] = (id)clearColor.CGColor;
    return attributes;
}

- (NSMutableAttributedString *)_paragraphLayoutProbeTextForNextContext:(_KKTextViewParagraphContext *)nextContext {
    // No next paragraph means no probe is needed.
    if (!nextContext) return [NSMutableAttributedString new];
    NSDictionary *attributes = [self _paragraphProbeAttributesForContext:nextContext];
    // The zero-width space only lets Core Text lay out the next paragraph's first-line position; it produces no visible character.
    return [[NSMutableAttributedString alloc] initWithString:@"\u200B" attributes:attributes];
}

- (NSMutableAttributedString *)_paragraphLayoutTailTextForContext:(_KKTextViewParagraphContext *)context nextContext:(_KKTextViewParagraphContext *)nextContext {
    NSMutableAttributedString *tailText = [NSMutableAttributedString new];
    // When a real line break exists, append the line break and next-paragraph probe to the current paragraph layout,
    // so this paragraph can measure where the next first line should appear after the line break.
    if (context.lineBreakRange.length > 0) {
        NSAttributedString *lineBreakSource = [_innerText attributedSubstringFromRange:context.lineBreakRange];
        [tailText appendAttributedString:[self _hiddenLayoutTextWithAttributedString:lineBreakSource]];
        [tailText appendAttributedString:[self _paragraphLayoutProbeTextForNextContext:nextContext]];
    } else {
        // For the last paragraph without a line break, append a hidden sentinel so the document-end caret has a stable rect.
        NSDictionary *attributes = [self _paragraphSentinelAttributesForContext:context];
        NSAttributedString *sentinel = [[NSAttributedString alloc] initWithString:@"\r" attributes:attributes];
        [tailText appendAttributedString:sentinel];
    }
    return tailText;
}

- (NSMutableAttributedString *)_layoutTextForParagraphContext:(_KKTextViewParagraphContext *)context {
    // layoutText = this paragraph's real text + hidden tail.
    // The tail is not included in context.text, so it cannot pollute editing, copy, or global ranges.
    NSMutableAttributedString *layoutText = context.text.mutableCopy ?: [NSMutableAttributedString new];
    [layoutText appendAttributedString:context.layoutTailText ?: [NSMutableAttributedString new]];
    return layoutText;
}

- (KKTextLayout *)_layoutForParagraphContext:(_KKTextViewParagraphContext *)context containerSize:(CGSize)containerSize {
    // Each paragraph owns its own container/layout, so later body-text redraw can be limited to the affected paragraph view.
    KKTextContainer *container = [self _paragraphContainerWithSize:containerSize];
    return [KKTextLayout layoutWithContainer:container text:[self _layoutTextForParagraphContext:context]];
}

- (void)_recordParagraphEditRange:(NSRange)range replacementLength:(NSUInteger)replacementLength {
    // Record the new range and length delta produced by this edit.
    // When paragraph contexts are rebuilt, the current range can be mapped back to the old range to improve layout reuse.
    _pendingParagraphEditNewRange = NSMakeRange(range.location, replacementLength);
    _pendingParagraphEditDelta = (NSInteger)replacementLength - (NSInteger)range.length;
    _hasPendingParagraphEdit = YES;
}

- (void)_clearParagraphEditRecord {
    // Clear edit tracking after one layout update so unrelated later relayouts are not affected.
    _pendingParagraphEditNewRange = NSMakeRange(0, 0);
    _pendingParagraphEditDelta = 0;
    _hasPendingParagraphEdit = NO;
}

- (NSUInteger)_oldParagraphLocationForCurrentRange:(NSRange)range {
    // Without a pending edit, current and old locations are the same.
    if (!_hasPendingParagraphEdit) return range.location;
    // Paragraphs after the edited range are only shifted; subtracting the delta finds the old paragraph start.
    if (range.location >= NSMaxRange(_pendingParagraphEditNewRange)) {
        NSInteger oldLocation = (NSInteger)range.location - _pendingParagraphEditDelta;
        return oldLocation > 0 ? (NSUInteger)oldLocation : 0;
    }
    return range.location;
}

- (_KKTextViewParagraphContext *)_oldParagraphContextForCurrentContext:(_KKTextViewParagraphContext *)context oldContexts:(NSArray<_KKTextViewParagraphContext *> *)oldContexts index:(NSUInteger)index {
    // With edit tracking, first find the old context by corrected old location to avoid index-based reuse misses after insertion.
    if (_hasPendingParagraphEdit) {
        NSUInteger oldLocation = [self _oldParagraphLocationForCurrentRange:context.range];
        for (_KKTextViewParagraphContext *oldContext in oldContexts) {
            if (oldContext.range.location == oldLocation) return oldContext;
        }
    }
    // If there is no edit record or no location match, fall back to same-index reuse.
    return index < oldContexts.count ? oldContexts[index] : nil;
}

- (BOOL)_paragraphContext:(_KKTextViewParagraphContext *)context canReuseLayoutFromContext:(_KKTextViewParagraphContext *)oldContext containerSize:(CGSize)containerSize {
    // No old layout means there is nothing to reuse.
    if (!oldContext.layout) return NO;
    // Container-size changes affect wrapping, so the layout cannot be reused.
    if (!CGSizeEqualToSize(oldContext.layoutContainerSize, containerSize)) return NO;
    // Real paragraph text changed, so the layout cannot be reused.
    if (![oldContext.text isEqualToAttributedString:context.text]) return NO;
    // Tail/probe changes affect inter-paragraph height and end caret, so the layout cannot be reused either.
    if (![oldContext.layoutTailText isEqualToAttributedString:context.layoutTailText]) return NO;
    return YES;
}

- (_KKTextViewParagraphContext *)_paragraphContextForLocation:(NSUInteger)location {
    // Find the paragraph context that contains the global location.
    if (_paragraphContexts.count == 0) return nil;
    location = MIN(location, _innerText.length);
    for (_KKTextViewParagraphContext *context in _paragraphContexts) {
        NSUInteger start = context.range.location;
        NSUInteger end = NSMaxRange(context.range);
        if (context.range.length == 0) {
            // An empty paragraph has only one insertion position.
            if (location == start) return context;
        } else if (start <= location && location <= end) {
            return context;
        }
    }
    // If hit testing or positioning lands outside paragraph bounds, snap to the first or last paragraph.
    return location <= _paragraphContexts.firstObject.range.location ? _paragraphContexts.firstObject : _paragraphContexts.lastObject;
}

- (_KKTextViewParagraphContext *)_paragraphContextForPoint:(CGPoint)point {
    // Find the paragraph view at a point in documentView coordinates.
    if (_paragraphContexts.count == 0) return nil;
    for (_KKTextViewParagraphContext *context in _paragraphContexts) {
        if (NSPointInRect(point, context.contentView.frame)) return context;
    }
    // If the point is above or below content, snap to the first or last paragraph so blank-area clicks still produce a position.
    if (point.y <= CGRectGetMinY(_paragraphContexts.firstObject.contentView.frame)) {
        return _paragraphContexts.firstObject;
    }
    return _paragraphContexts.lastObject;
}

- (NSUInteger)_localLocationForGlobalLocation:(NSUInteger)location inParagraphContext:(_KKTextViewParagraphContext *)context {
    // Convert a global location to a paragraph-local location.
    if (!context) return 0;
    if (location <= context.range.location) return 0;
    return MIN(location - context.range.location, context.text.length);
}

- (NSRange)_localRangeForGlobalRange:(NSRange)range inParagraphContext:(_KKTextViewParagraphContext *)context {
    // Clip a global range to the current paragraph and return a paragraph-local range.
    if (!context) return NSMakeRange(NSNotFound, 0);
    range = KKTextViewMakeSafeRange(range, _innerText.length);
    NSUInteger paragraphStart = context.range.location;
    NSUInteger paragraphEnd = NSMaxRange(context.range);
    if (range.length == 0) {
        // A collapsed selection must be inside this paragraph range; otherwise this paragraph does not participate.
        if (range.location < paragraphStart || range.location > paragraphEnd) return NSMakeRange(NSNotFound, 0);
        return NSMakeRange([self _localLocationForGlobalLocation:range.location inParagraphContext:context], 0);
    }

    // Intersect a non-empty selection with the current paragraph.
    NSUInteger start = MAX(range.location, paragraphStart);
    NSUInteger end = MIN(NSMaxRange(range), paragraphEnd);
    if (end <= start) return NSMakeRange(NSNotFound, 0);
    return NSMakeRange(start - paragraphStart, end - start);
}

- (NSRange)_globalRangeForLocalRange:(NSRange)localRange inParagraphContext:(_KKTextViewParagraphContext *)context {
    // Convert a paragraph-local range back to a global range.
    if (!context || localRange.location == NSNotFound) return NSMakeRange(NSNotFound, 0);
    localRange = KKTextViewMakeSafeRange(localRange, context.text.length);
    return NSMakeRange(context.range.location + localRange.location, localRange.length);
}

- (CGPoint)_localPointForDocumentPoint:(CGPoint)point inParagraphContext:(_KKTextViewParagraphContext *)context {
    // Convert a documentView point into paragraph-view coordinates.
    NSRect frame = context.contentView.frame;
    return CGPointMake(point.x - frame.origin.x, point.y - frame.origin.y);
}

- (CGRect)_documentRectForLocalRect:(CGRect)rect inParagraphContext:(_KKTextViewParagraphContext *)context {
    // Convert a paragraph-view rect into documentView coordinates.
    if (CGRectIsNull(rect)) return rect;
    NSRect frame = context.contentView.frame;
    rect.origin.x += frame.origin.x;
    rect.origin.y += frame.origin.y;
    return rect;
}

- (void)_resetVerticalMovementTargetX {
    // Left/right movement, mouse clicks, and text changes all reset the vertical-movement target x.
    _hasVerticalMovementTargetX = NO;
}

- (CGFloat)_verticalMovementTargetXForLocation:(NSUInteger)location {
    // On repeated up/down keys, record the current caret center x once, then use that x to find target-line positions.
    if (!_hasVerticalMovementTargetX) {
        CGRect caretRect = [self _caretRectForLocation:location];
        _verticalMovementTargetX = CGRectIsNull(caretRect) ? _textContainerInset.left : CGRectGetMidX(caretRect);
        _hasVerticalMovementTargetX = YES;
    }
    return _verticalMovementTargetX;
}

- (BOOL)_paragraphContext:(_KKTextViewParagraphContext *)context canUseLineAtIndex:(NSUInteger)lineIndex {
    // The layout may contain hidden tail/probe lines; they must not be used as real text lines for keyboard movement.
    if (!context || lineIndex == NSNotFound || lineIndex >= context.layout.lines.count) return NO;
    KKTextLine *line = context.layout.lines[lineIndex];
    // Empty paragraphs may use the line at offset 0.
    if (context.text.length == 0) return line.range.location == 0;
    return line.range.location < context.text.length;
}

- (NSUInteger)_lineIndexForParagraphContext:(_KKTextViewParagraphContext *)context localLocation:(NSUInteger)localLocation {
    // Find the real text line that contains the current localLocation.
    if (!context.layout) return NSNotFound;
    localLocation = MIN(localLocation, context.text.length);
    KKTextPosition *position = [KKTextPosition positionWithOffset:localLocation];
    NSUInteger lineIndex = [context.layout lineIndexForPosition:position];
    if ([self _paragraphContext:context canUseLineAtIndex:lineIndex]) return lineIndex;
    // At line/paragraph end, forward affinity may land on a tail line; retry with backward affinity.
    if (localLocation > 0) {
        position = [KKTextPosition positionWithOffset:localLocation affinity:KKTextAffinityBackward];
        lineIndex = [context.layout lineIndexForPosition:position];
        if ([self _paragraphContext:context canUseLineAtIndex:lineIndex]) return lineIndex;
    }
    return NSNotFound;
}

- (NSUInteger)_lineIndexInParagraphContext:(_KKTextViewParagraphContext *)context fromLineIndex:(NSUInteger)lineIndex direction:(UITextLayoutDirection)direction {
    // Search previous/next lines within the same paragraph and skip hidden tail/probe lines.
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
    // For cross-paragraph movement, use the previous paragraph's last real line or the next paragraph's first real line.
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
    // On the specified line in the specified paragraph, use targetX in document coordinates to find a global text position.
    if (![self _paragraphContext:context canUseLineAtIndex:lineIndex]) return NSNotFound;
    KKTextLine *line = context.layout.lines[lineIndex];
    CGFloat localX = targetX - context.contentView.frame.origin.x;
    NSUInteger localLocation = [context.layout textPositionForPoint:CGPointMake(localX, line.position.y) lineIndex:lineIndex];
    if (localLocation == NSNotFound) {
        // If targetX is outside the line width, clamp it to the line edge and hit test again.
        localX = MIN(MAX(localX, line.left), line.right);
        localLocation = [context.layout textPositionForPoint:CGPointMake(localX, line.position.y) lineIndex:lineIndex];
    }
    if (localLocation == NSNotFound) return NSNotFound;
    localLocation = MIN(localLocation, context.text.length);
    return MIN(context.range.location + localLocation, _innerText.length);
}

- (NSUInteger)_caretAttributeIndexForText:(NSAttributedString *)text location:(NSUInteger)location {
    // Choose the attribute character used for caret metrics based on the insertion position.
    if (text.length == 0) return NSNotFound;
    location = MIN(location, text.length);
    // At document start there is no previous character, so use the first character.
    if (location == 0) return 0;
    // If the previous character is a line break, the caret is at the start of a new line; prefer the current character.
    if (location < text.length && KKTextIsLinebreakChar([text.string characterAtIndex:location - 1])) {
        return location;
    }
    return MIN(location - 1, text.length - 1);
}

- (void)_caretFontMetricsForFont:(id)font ascent:(CGFloat *)ascent descent:(CGFloat *)descent {
    // The font may come from NSFont or from a Core Text attribute.
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

- (void)_caretFontMetricsForParagraphContext:(_KKTextViewParagraphContext *)context location:(NSUInteger)location ascent:(CGFloat *)ascent descent:(CGFloat *)descent {
    id font = nil;
    // In paragraph mode, caret height is taken from the local text attributes of the containing paragraph first.
    if (context.text.length > 0) {
        NSUInteger localLocation = location <= context.range.location ? 0 : MIN(location - context.range.location, context.text.length);
        NSUInteger index = [self _caretAttributeIndexForText:context.text location:localLocation];
        if (index != NSNotFound) {
            font = [context.text attribute:NSFontAttributeName atIndex:index effectiveRange:NULL];
            if (!font) font = [context.text attribute:(id)kCTFontAttributeName atIndex:index effectiveRange:NULL];
        }
    }
    // For empty paragraphs or missing font attributes, fall back to current typing attributes.
    if (!font) font = _currentTypingAttributes[NSFontAttributeName];
    if (!font) font = _currentTypingAttributes[(id)kCTFontAttributeName];
    [self _caretFontMetricsForFont:font ascent:ascent descent:descent];
}

- (CGRect)_caretRectByCenteringRect:(CGRect)rect withHeight:(CGFloat)height {
    // Core Text caret rects do not always match the current font height, so mixed font sizes need centerline height adjustment.
    if (CGRectIsNull(rect) || height <= 0) return rect;
    rect.origin.y = CGRectGetMidY(rect) - height * 0.5;
    rect.size.height = height;
    return rect;
}

- (CGRect)_localCaretRectForParagraphContext:(_KKTextViewParagraphContext *)context location:(NSUInteger)location {
    // Return the caret rect in paragraph-view coordinates.
    if (!context.layout) return CGRectNull;
    NSUInteger localLocation = location <= context.range.location ? 0 : MIN(location - context.range.location, context.text.length);
    CGFloat caretAscent = 0;
    CGFloat caretDescent = 0;
    [self _caretFontMetricsForParagraphContext:context location:location ascent:&caretAscent descent:&caretDescent];
    CGFloat caretHeight = caretAscent + caretDescent;
    KKTextPosition *position = [KKTextPosition positionWithOffset:localLocation];
    CGRect rect = [context.layout caretRectForPosition:position];
    if (CGRectIsNull(rect)) {
        // For empty paragraphs or layout misses, fall back to the paragraph's upper-left corner.
        rect = CGRectMake(_textContainerInset.left, 0, 0, caretHeight);
    } else if (!_verticalForm && caretHeight > 0) {
        // In horizontal mixed-font layout, center the caret using the current font metrics.
        rect = [self _caretRectByCenteringRect:rect withHeight:caretHeight];
    }
    // Give the caret a minimum visible size.
    if (_verticalForm) {
        rect.size.height = MAX(rect.size.height, 2);
    } else {
        rect.size.width = MAX(rect.size.width, 2);
    }
    return rect;
}

- (CGFloat)_minimumParagraphHeightForContext:(_KKTextViewParagraphContext *)context {
    // Empty paragraphs need at least one caret-height line; otherwise consecutive empty lines collapse.
    CGFloat ascent = 0;
    CGFloat descent = 0;
    [self _caretFontMetricsForParagraphContext:context location:context.range.location ascent:&ascent descent:&descent];
    return MAX(ceil(ascent + descent), 1);
}

- (CGFloat)_paragraphFirstVisibleLineTopForContext:(_KKTextViewParagraphContext *)context {
    // The next-paragraph probe may create hidden lines; only use the top of real text lines here.
    if (!context.layout) return 0;
    for (NSUInteger idx = 0; idx < context.layout.lines.count; idx++) {
        if (![self _paragraphContext:context canUseLineAtIndex:idx]) continue;
        KKTextLine *line = context.layout.lines[idx];
        return line.top;
    }
    return 0;
}

- (CGFloat)_paragraphVisibleTextHeightForContext:(_KKTextViewParagraphContext *)context {
    // Paragraph body height is the maximum bottom of all real text lines, with at least the minimum line height kept.
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
    // Paragraph view height must cover not only real lines, but also the paragraph-start caret.
    CGSize size = boundsSize;
    size.height = [self _paragraphVisibleTextHeightForContext:context];
    CGRect startCaretRect = [self _localCaretRectForParagraphContext:context location:context.range.location];
    if (!CGRectIsNull(startCaretRect)) {
        size.height = MAX(size.height, ceil(CGRectGetMaxY(startCaretRect)));
    }
    return size;
}

- (BOOL)_paragraphContextHasLineBreakTerminator:(_KKTextViewParagraphContext *)context {
    // Whether this paragraph is followed by a real line break.
    return context.lineBreakRange.length > 0;
}

- (NSUInteger)_paragraphAttributeIndexForContext:(_KKTextViewParagraphContext *)context preferEnd:(BOOL)preferEnd {
    // Reading paragraph spacing needs a usable attribute location.
    if (_innerText.length == 0) return NSNotFound;
    if (context.range.length > 0) {
        // Non-empty paragraphs can use the first or last character's attributes.
        return preferEnd ? NSMaxRange(context.range) - 1 : context.range.location;
    }
    // Empty paragraphs use their global text position; a trailing empty paragraph falls back to the last real character.
    if (context.range.location < _innerText.length) return context.range.location;
    return _innerText.length - 1;
}

- (CGFloat)_paragraphSpacingAfterContext:(_KKTextViewParagraphContext *)context nextContext:(_KKTextViewParagraphContext *)nextContext {
    // When the probe cannot produce a stable advance, use paragraph spacing after/before as a fallback.
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
    // Only calculate the post-line-break caret y position when this paragraph has a real line break.
    if (![self _paragraphContextHasLineBreakTerminator:context] || !context.layout) return 0;
    NSUInteger localLocation = context.text.length + MAX(context.lineBreakRange.length, 1);
    KKTextPosition *position = [KKTextPosition positionWithOffset:localLocation affinity:KKTextAffinityBackward];
    CGRect rect = [context.layout caretRectForPosition:position];
    return CGRectIsNull(rect) ? 0 : ceil(CGRectGetMinY(rect));
}

- (CGFloat)_paragraphAdvanceToNextContext:(_KKTextViewParagraphContext *)context nextContext:(_KKTextViewParagraphContext *)nextContext {
    // Measure the next paragraph's first-line advance relative to this paragraph through the hidden line break + probe at the end of the layout.
    if (!nextContext || !context.layout || context.lineBreakRange.length == 0) return 0;
    NSUInteger probeLocation = context.text.length + context.lineBreakRange.length;
    KKTextPosition *position = [KKTextPosition positionWithOffset:probeLocation];
    CGRect rect = [context.layout caretRectForPosition:position];
    if (CGRectIsNull(rect)) {
        // Forward affinity may fail at the tail boundary; retry once with backward affinity.
        position = [KKTextPosition positionWithOffset:probeLocation affinity:KKTextAffinityBackward];
        rect = [context.layout caretRectForPosition:position];
    }
    if (CGRectIsNull(rect)) return 0;
    CGFloat nextTop = [self _paragraphFirstVisibleLineTopForContext:nextContext];
    return MAX(ceil(CGRectGetMinY(rect) - nextTop), 0);
}

- (CGFloat)_paragraphHeightForContext:(_KKTextViewParagraphContext *)context nextContext:(_KKTextViewParagraphContext *)nextContext boundsSize:(CGSize)boundsSize {
    // The paragraph view's final height determines the next paragraph's y position.
    CGFloat height = [self _paragraphDrawSizeForContext:context boundsSize:boundsSize].height;
    if (nextContext) {
        CGFloat advance = [self _paragraphAdvanceToNextContext:context nextContext:nextContext];
        if (advance > 0) {
            // Prefer the real inter-paragraph advance measured by the probe.
            height = MAX(height, advance);
        } else {
            // If the probe is unavailable, fall back to line-break advance plus paragraph spacing.
            height = MAX(height, [self _paragraphLineBreakAdvanceForContext:context]);
            height += [self _paragraphSpacingAfterContext:context nextContext:nextContext];
        }
    }
    return MAX(height, [self _minimumParagraphHeightForContext:context]);
}

- (BOOL)_selectionRange:(NSRange)range containsEmptyParagraphContext:(_KKTextViewParagraphContext *)context {
    // Empty paragraphs have no glyphs, so layout will not return a selection rect; synthesize the empty-line selection manually.
    if (!context || context.text.length > 0 || range.length == 0) return NO;
    NSUInteger selectionStart = range.location;
    NSUInteger selectionEnd = NSMaxRange(range);
    if (context.lineBreakRange.length > 0) {
        // If the empty paragraph itself has a line break, draw the empty-line background whenever the selection includes that line break.
        return NSIntersectionRange(range, context.lineBreakRange).length > 0;
    }
    // A trailing empty paragraph has no lineBreakRange; fill selection only when it crosses the previous line break and covers this position.
    if (context.range.location == 0 || selectionStart >= context.range.location || selectionEnd < context.range.location) {
        return NO;
    }
    unichar previous = [_innerText.string characterAtIndex:context.range.location - 1];
    return KKTextIsLinebreakChar(previous);
}

- (BOOL)_selectionRange:(NSRange)range containsLineBreakForParagraphContext:(_KKTextViewParagraphContext *)context {
    // When selection crosses the paragraph-ending line break, fill the selection background from line end to the right/bottom of the paragraph view.
    if (!context || context.lineBreakRange.length == 0 || range.length == 0) return NO;
    return NSIntersectionRange(range, context.lineBreakRange).length > 0;
}

- (CGRect)_paragraphTailSelectionLineBoundsForContext:(_KKTextViewParagraphContext *)context {
    // Find the real line bounds at the paragraph end to fill the selection rect for the line break.
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
    // Generate selection rects for paragraph-ending line breaks and empty paragraphs; normal glyph selection does not produce these rects.
    if (!context.contentView) return @[];
    CGRect caretRect = [self _localCaretRectForParagraphContext:context location:NSMaxRange(context.range)];
    if (CGRectIsNull(caretRect)) {
        // If no caret rect is available, fall back to the minimum paragraph height.
        caretRect = CGRectMake(_textContainerInset.left, 0, 0, [self _minimumParagraphHeightForContext:context]);
    }
    CGRect lineBounds = [self _paragraphTailSelectionLineBoundsForContext:context];
    if (CGRectIsNull(lineBounds)) {
        // If no line bounds are available, handle it as an empty line as well.
        lineBounds = CGRectMake(_textContainerInset.left, 0, 0, [self _minimumParagraphHeightForContext:context]);
    }

    NSMutableArray<KKTextSelectionRect *> *rects = [NSMutableArray arrayWithCapacity:2];
    CGFloat left = _textContainerInset.left;
    CGFloat right = _textContainerInset.right;
    CGFloat maxX = MAX(context.contentView.bounds.size.width - right, left);
    CGFloat minY = MAX(CGRectGetMinY(lineBounds), 0);
    CGFloat lineMaxY = MIN(CGRectGetMaxY(lineBounds), context.contentView.bounds.size.height);
    if (lineMaxY <= minY) {
        // Fill a minimum height when line height is invalid, avoiding zero-height selection rects.
        lineMaxY = MIN(minY + [self _minimumParagraphHeightForContext:context], context.contentView.bounds.size.height);
    }
    CGFloat caretX = MIN(MAX(CGRectGetMinX(caretRect), left), maxX);

    if (maxX > caretX && lineMaxY > minY) {
        // First segment: from caret to line end.
        KKTextSelectionRect *lineRect = [KKTextSelectionRect new];
        lineRect.rect = [self _documentRectForLocalRect:CGRectMake(caretX, minY, maxX - caretX, lineMaxY - minY) inParagraphContext:context];
        lineRect.isVertical = NO;
        [rects addObject:lineRect];
    }

    if (context.contentView.bounds.size.height > lineMaxY && maxX > left) {
        // Second segment: if the paragraph view includes inter-paragraph blank space, tint that blank space too.
        KKTextSelectionRect *tailRect = [KKTextSelectionRect new];
        tailRect.rect = [self _documentRectForLocalRect:CGRectMake(left, lineMaxY, maxX - left, context.contentView.bounds.size.height - lineMaxY) inParagraphContext:context];
        tailRect.isVertical = NO;
        [rects addObject:tailRect];
    }
    return rects;
}

- (NSArray<KKTextSelectionRect *> *)_selectionRectsForRange:(NSRange)range {
    range = KKTextViewMakeSafeRange(range, _innerText.length);
    // Collapsed selection has no selection rect; draw only the caret.
    if (range.length == 0) return @[];
    if (![self _usesParagraphContainerViews]) {
        // The fallback global layout can be delegated directly to KKTextLayout.
        if (!_innerLayout) return @[];
        return [_innerLayout selectionRectsForRange:[KKTextRange rangeWithRange:range]];
    }

    NSMutableArray<KKTextSelectionRect *> *rects = [NSMutableArray array];
    // In paragraph mode, clip the global range to each paragraph, then convert local rects back into document coordinates.
    for (_KKTextViewParagraphContext *context in _paragraphContexts) {
        NSRange localRange = [self _localRangeForGlobalRange:range inParagraphContext:context];
        BOOL containsLineBreak = [self _selectionRange:range containsLineBreakForParagraphContext:context];
        if (localRange.location == NSNotFound || localRange.length == 0) {
            // Even without real local glyphs, empty paragraphs or line breaks may still need supplemental tail rects.
            if ([self _selectionRange:range containsEmptyParagraphContext:context]) {
                [rects addObjectsFromArray:[self _selectionRectsForParagraphTailInContext:context]];
            } else if (containsLineBreak) {
                [rects addObjectsFromArray:[self _selectionRectsForParagraphTailInContext:context]];
            }
            continue;
        }
        NSArray<KKTextSelectionRect *> *localRects = [context.layout selectionRectsForRange:[KKTextRange rangeWithRange:localRange]];
        for (KKTextSelectionRect *localRect in localRects) {
            // Copy the rect before modifying objects returned by the layout.
            KKTextSelectionRect *rect = localRect.copy;
            rect.rect = [self _documentRectForLocalRect:rect.rect inParagraphContext:context];
            [rects addObject:rect];
        }
        if (containsLineBreak) {
            // Append selection rects for line breaks and inter-paragraph blank space after real glyph rects.
            [rects addObjectsFromArray:[self _selectionRectsForParagraphTailInContext:context]];
        }
    }
    return rects;
}

- (CGRect)_rectForRange:(NSRange)range {
    range = KKTextViewMakeSafeRange(range, _innerText.length);
    // Empty ranges return the caret rect for scrollRangeToVisible.
    if (range.length == 0) return [self _caretRectForLocation:range.location];
    if (![self _usesParagraphContainerViews]) {
        if (!_innerLayout) return CGRectNull;
        return [_innerLayout rectForRange:[KKTextRange rangeWithRange:range]];
    }

    CGRect rect = CGRectNull;
    // A non-empty range's visible rect is the union of all selection rects.
    for (KKTextSelectionRect *selectionRect in [self _selectionRectsForRange:range]) {
        if (CGRectIsEmpty(selectionRect.rect) || CGRectIsNull(selectionRect.rect)) continue;
        rect = CGRectIsNull(rect) ? selectionRect.rect : CGRectUnion(rect, selectionRect.rect);
    }
    return rect;
}

- (void)_setSelectionNeedsDisplay {
    // Selection and caret live on selectionView, so changes redraw only that layer.
    [_selectionView setNeedsDisplay:YES];
}

- (void)_updateSelectionFrame {
    // selectionView covers the entire documentView and stays above paragraph views.
    if (!_selectionView || !_textDocumentView) return;
    _selectionView.frame = _textDocumentView.bounds;
    [_selectionView removeFromSuperview];
    [_textDocumentView addSubview:_selectionView positioned:NSWindowAbove relativeTo:nil];
}

- (void)_updateParagraphContainerViewsReusingLayouts:(BOOL)reuseLayouts {
    if (![self _usesParagraphContainerViews]) {
        // If paragraph mode is not applicable, remove all paragraph views and return to global layout drawing.
        for (_KKTextViewParagraphContext *context in _paragraphContexts) {
            [context.contentView removeFromSuperview];
        }
        [_paragraphContexts removeAllObjects];
        _paragraphContentSize = CGSizeZero;
        [self _updateSelectionFrame];
        [self _clearParagraphEditRecord];
        return;
    }

    NSArray<_KKTextViewParagraphContext *> *oldContexts = _paragraphContexts.copy;
    NSArray<NSValue *> *ranges = [self _paragraphContentRanges];
    NSMutableArray<_KKTextViewParagraphContext *> *contexts = [NSMutableArray arrayWithCapacity:ranges.count];
    NSMutableSet<_KKTextViewParagraphContainerView *> *activeViews = [NSMutableSet set];
    NSMutableSet<_KKTextViewParagraphContext *> *reusedOldContexts = [NSMutableSet set];
    CGSize containerSize = [self _paragraphLayoutContainerSize];
    CGFloat width = [self _visibleSize].width;
    CGFloat fallbackY = _textContainerInset.top;

    // First pass: split the global text into new paragraph contexts only, without creating layouts yet.
    for (NSUInteger idx = 0; idx < ranges.count; idx++) {
        _KKTextViewParagraphContext *context = [self _paragraphContextWithRange:ranges[idx].rangeValue];
        context.layoutContainerSize = containerSize;
        [contexts addObject:context];
    }

    // Second pass: because tail/probe text depends on the next paragraph, build layoutTailText and layout only after all contexts exist.
    for (NSUInteger idx = 0; idx < contexts.count; idx++) {
        _KKTextViewParagraphContext *context = contexts[idx];
        _KKTextViewParagraphContext *nextContext = idx + 1 < contexts.count ? contexts[idx + 1] : nil;
        context.layoutTailText = [self _paragraphLayoutTailTextForContext:context nextContext:nextContext];
        _KKTextViewParagraphContext *oldContext = [self _oldParagraphContextForCurrentContext:context oldContexts:oldContexts index:idx];
        // Each oldContext can be reused only once, preventing two new paragraphs from sharing one view/layout after insertion or deletion.
        if (oldContext && [reusedOldContexts containsObject:oldContext]) oldContext = nil;
        if (reuseLayouts &&
            [self _paragraphContext:context canReuseLayoutFromContext:oldContext containerSize:containerSize]) {
            // On a reuse hit, keep the old layout and view, and only update the context reference.
            context.layout = oldContext.layout;
            context.contentView = oldContext.contentView;
            [reusedOldContexts addObject:oldContext];
        } else {
            // If text, tail, or container changed, relayout only this paragraph.
            context.layout = [self _layoutForParagraphContext:context containerSize:containerSize];
        }

        if (!context.contentView) {
            // Create a paragraph container view when the new paragraph has no reusable view.
            context.contentView = [_KKTextViewParagraphContainerView new];
            context.contentView.textView = self;
            context.contentView.wantsLayer = YES;
            context.contentView.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
            [_textDocumentView addSubview:context.contentView];
        }
        context.contentView.paragraphContext = context;
        [activeViews addObject:context.contentView];
    }

    // Third pass: place paragraph views from top to bottom according to each paragraph height.
    for (NSUInteger idx = 0; idx < contexts.count; idx++) {
        _KKTextViewParagraphContext *context = contexts[idx];
        _KKTextViewParagraphContext *nextContext = idx + 1 < contexts.count ? contexts[idx + 1] : nil;
        CGFloat height = [self _paragraphHeightForContext:context nextContext:nextContext boundsSize:CGSizeMake(width, 0)];
        context.contentView.frame = (NSRect){CGPointMake(0, fallbackY), CGSizeMake(width, height)};
        // Even when the layout was reused, frame/selection may have changed, so the paragraph view still needs redraw.
        [context.contentView setNeedsDisplay:YES];
        fallbackY += height;
    }

    // Remove old paragraph views that were not reused in this update.
    for (_KKTextViewParagraphContext *oldContext in oldContexts) {
        if (oldContext.contentView && ![activeViews containsObject:oldContext.contentView]) {
            [oldContext.contentView removeFromSuperview];
        }
    }

    // Total paragraph content height drives the documentView frame and scroll range.
    _paragraphContexts = contexts;
    _paragraphContentSize = CGSizeMake(width, fallbackY + _textContainerInset.bottom);
    [self _updateSelectionFrame];
    [self _clearParagraphEditRecord];
}

- (CGSize)_layoutContainerSize {
    CGSize size = [self _visibleSize];
    // Fallback global-layout container size: vertical text grows horizontally, horizontal text grows vertically.
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
    // When the document is smaller than the visible area, keep the maximum offset at 0 to avoid negative scrolling.
    return CGPointMake(MAX(_documentSize.width - visibleSize.width, 0),
                       MAX(_documentSize.height - visibleSize.height, 0));
}

- (CGPoint)_clampedContentOffset:(CGPoint)contentOffset {
    // Clamp all programmatic scrolling to the valid content range.
    CGPoint maximumOffset = [self _maximumContentOffset];
    contentOffset.x = MIN(MAX(contentOffset.x, 0), maximumOffset.x);
    contentOffset.y = MIN(MAX(contentOffset.y, 0), maximumOffset.y);
    return contentOffset;
}

- (void)_scrollToContentOffset:(CGPoint)contentOffset {
    NSClipView *clipView = self.contentView;
    if (!clipView) return;
    // In AppKit, scroll position is represented by NSClipView.bounds.origin.
    contentOffset = [self _clampedContentOffset:contentOffset];
    [clipView scrollToPoint:contentOffset];
    [self reflectScrolledClipView:clipView];
}

- (void)_scrollDocumentRectToVisible:(CGRect)rect padding:(CGFloat)padding {
    // Do not scroll for invalid rects.
    if (CGRectIsNull(rect)) return;
    CGRect visibleRect = (CGRect){[self _contentOffset], [self _visibleSize]};
    CGRect visibleRectWithTolerance = CGRectInset(visibleRect, -1, -1);
    // Use a 1 pt tolerance to avoid tiny scroll jitter near the caret due to floating-point error.
    if (CGRectContainsRect(visibleRectWithTolerance, rect)) return;

    CGRect targetRect = CGRectInset(rect, -padding, -padding);
    CGPoint contentOffset = visibleRect.origin;

    // Scroll left/right when the rect is outside the visible bounds horizontally.
    if (CGRectGetMinX(targetRect) < CGRectGetMinX(visibleRect)) {
        contentOffset.x = CGRectGetMinX(targetRect);
    } else if (CGRectGetMaxX(targetRect) > CGRectGetMaxX(visibleRect)) {
        contentOffset.x = CGRectGetMaxX(targetRect) - visibleRect.size.width;
    }

    // Scroll up/down when the rect is outside the visible bounds vertically.
    if (CGRectGetMinY(targetRect) < CGRectGetMinY(visibleRect)) {
        contentOffset.y = CGRectGetMinY(targetRect);
    } else if (CGRectGetMaxY(targetRect) > CGRectGetMaxY(visibleRect)) {
        contentOffset.y = CGRectGetMaxY(targetRect) - visibleRect.size.height;
    }

    [self _scrollToContentOffset:contentOffset];
}

- (void)_updateDocumentViewFrame {
    if (!_textDocumentView) return;
    // Preserve the current scroll position before resizing documentView, so relayout does not jump back to the top.
    CGPoint contentOffset = [self _contentOffset];
    NSRect frame = (NSRect){CGPointZero, _documentSize};
    _textDocumentView.frame = frame;
    [self _updateSelectionFrame];
    [self _scrollToContentOffset:contentOffset];
    [_textDocumentView setNeedsDisplay:YES];
}

- (void)_updateDocumentSizeForLayout {
    CGSize visibleSize = [self _visibleSize];
    if ([self _usesParagraphContainerViews]) {
        // In paragraph mode, documentSize comes from the accumulated height of all paragraph views.
        CGSize documentSize = _paragraphContentSize;
        documentSize.width = visibleSize.width;
        documentSize.height = MAX(documentSize.height, visibleSize.height);
        _documentSize = documentSize;
        [self _updateDocumentViewFrame];
        return;
    }

    // In fallback global layout, documentSize comes from _innerLayout.textBoundingSize.
    CGSize documentSize = _innerLayout ? _innerLayout.textBoundingSize : CGSizeZero;
    if (_verticalForm) {
        // For vertical text, width grows with content and height is at least the visible height.
        documentSize.width = MAX(documentSize.width, visibleSize.width);
        documentSize.height = visibleSize.height;
    } else {
        // For horizontal text, width is fixed to the visible width and height grows with content.
        documentSize.width = visibleSize.width;
        documentSize.height = MAX(documentSize.height, visibleSize.height);
    }
    _documentSize = documentSize;
    [self _updateDocumentViewFrame];
}

- (void)_updateLayout {
    // Synchronize common container state first. Even in paragraph mode, _innerContainer must stay consistent for the fallback path.
    _innerContainer.size = [self _layoutContainerSize];
    _innerContainer.insets = _textContainerInset;
    _innerContainer.exclusionPaths = _exclusionPaths;
    _innerContainer.verticalForm = _verticalForm;
    _innerContainer.linePositionModifier = _linePositionModifier;

    if ([self _usesParagraphContainerViews]) {
        // Paragraph mode: clear the global layout; body text is owned by each paragraph view.
        _innerLayout = nil;
        _placeholderLayout = nil;
        [self _updateParagraphContainerViewsReusingLayouts:YES];
        [self _updateDocumentSizeForLayout];
        // In paragraph mode there is no single textLayout object that can represent the whole document for public exposure.
        self.textLayout = nil;
        [self setNeedsDisplay:YES];
        return;
    }

    // Fallback global layout: keep the original YYTextView/KKTextView whole-document layout behavior.
    NSMutableAttributedString *layoutText = _innerText.mutableCopy;
    // Append a hidden sentinel to guarantee stable rects for empty text and document-end caret.
    NSUInteger sentinelLocation = _innerText.length;
    NSRange sentinelRange = NSMakeRange(sentinelLocation, 1);
    [layoutText replaceCharactersInRange:NSMakeRange(sentinelLocation, 0) withString:@"\r"];
    // The sentinel must not carry border/discontinuous attributes, or it may affect end caret and marked text appearance.
    [layoutText kk_removeDiscontinuousAttributesInRange:sentinelRange];
    [layoutText removeAttribute:KKTextBorderAttributeName range:sentinelRange];
    [layoutText removeAttribute:KKTextBackgroundBorderAttributeName range:sentinelRange];
    // When the caret is at the real text end, apply current typing attributes to the sentinel.
    if (_innerText.length == 0 || _selectedRange.location == sentinelLocation) {
        [_currentTypingAttributes enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            [layoutText kk_setAttribute:key value:obj range:sentinelRange];
        }];
    }

    _innerLayout = [KKTextLayout layoutWithContainer:_innerContainer text:layoutText];
    _placeholderLayout = [KKTextLayout layoutWithContainer:_innerContainer text:_placeholderInnerText];
    // Also call this in fallback mode to remove old paragraph views.
    [self _updateParagraphContainerViewsReusingLayouts:YES];
    [self _updateDocumentSizeForLayout];
    self.textLayout = _innerLayout;
    [self setNeedsDisplay:YES];
}

- (void)_drawSelectionInContext:(CGContextRef)context size:(CGSize)size {
    // selectionView uses documentView coordinates, and rects are already in document coordinates.
    NSArray *rects = [self _selectionRectsForRange:_selectedRange];
    CGContextSaveGState(context); {
        CGContextClipToRect(context, (CGRect){CGPointZero, size});
        CGContextSetAlpha(context, KKTextViewSelectionAlpha);
        CGContextSetFillColorWithColor(context, NSColor.selectedTextBackgroundColor.CGColor);
        CGMutablePathRef selectionPath = CGPathCreateMutable();
        for (KKTextSelectionRect *selectionRect in rects) {
            // Filter invalid rects and align to pixels to reduce blurry selection edges.
            if (CGRectIsEmpty(selectionRect.rect) || CGRectIsNull(selectionRect.rect)) continue;
            CGPathAddRect(selectionPath, NULL, KKTextCGRectPixelCeil(selectionRect.rect));
        }
        CGContextAddPath(context, selectionPath);
        CGContextFillPath(context);
        CGPathRelease(selectionPath);
    } CGContextRestoreGState(context);
}

- (void)_drawCaretInContext:(CGContextRef)context size:(CGSize)size {
    CGRect caretRect = [self _caretRectForLocation:_selectedRange.location];
    // If no caret rect can be obtained, do not draw it to avoid blinking at a wrong position.
    if (CGRectIsNull(caretRect)) return;
    // Ensure the caret is at least 2 pt visible for small fonts.
    if (_verticalForm) {
        caretRect.size.height = MAX(caretRect.size.height, 2);
    } else {
        caretRect.size.width = MAX(caretRect.size.width, 2);
    }
    CGContextSaveGState(context); {
        CGContextClipToRect(context, (CGRect){CGPointZero, size});
        CGContextSetFillColorWithColor(context, NSColor.keyboardFocusIndicatorColor.CGColor);
        CGContextFillRect(context, caretRect);
    } CGContextRestoreGState(context);
}

- (void)_drawSelectionViewInRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    // Without a fallback layout and outside paragraph mode, there is no content to draw.
    if (!_innerLayout && ![self _usesParagraphContainerViews]) return;

    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    if (!context) return;
    CGSize drawSize = _selectionView.bounds.size;
    // Draw selection first, then caret, so the caret is not covered by selection.
    if (_innerText.length > 0 && _selectedRange.length > 0) {
        [self _drawSelectionInContext:context size:drawSize];
    }
    if ([self _shouldShowCaret] && _caretVisible) {
        [self _drawCaretInContext:context size:drawSize];
    }
}

- (void)_drawParagraphContainerView:(_KKTextViewParagraphContainerView *)paragraphView inRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    _KKTextViewParagraphContext *paragraphContext = paragraphView.paragraphContext;
    // A reused/removed paragraph view may temporarily lack a layout; skip drawing in that case.
    if (!paragraphContext.layout) return;

    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    if (!context) return;
    CGSize drawSize = paragraphView.bounds.size;
    CGContextSaveGState(context); {
        // Each paragraph view still needs to flip the AppKit CGContext into the direction expected by KKTextLayout.
        KKTextViewFlipContextVertically(context, drawSize);
        CGContextClipToRect(context, (CGRect){CGPointZero, paragraphView.bounds.size});
        [paragraphContext.layout drawInContext:context size:drawSize point:CGPointZero view:paragraphView layer:paragraphView.layer debug:_debugOption cancel:nil];
    } CGContextRestoreGState(context);
}

- (BOOL)_shouldShowCaret {
    // Show the caret only while active and the selection is collapsed.
    return _caretActive && _selectedRange.length == 0;
}

- (void)_startCaretBlink {
    // Do not create duplicate timers; multiple timers would toggle visibility out of phase.
    if (_caretBlinkTimer) return;
    _caretBlinkTimer = [NSTimer timerWithTimeInterval:KKTextViewCaretBlinkInterval
                                               target:[KKTextWeakProxy proxyWithTarget:self]
                                             selector:@selector(_caretBlinkTimerDidFire:)
                                             userInfo:nil
                                              repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_caretBlinkTimer forMode:NSRunLoopCommonModes];
}

- (void)_stopCaretBlink {
    // Hide the caret on stop and redraw only selectionView.
    [_caretBlinkTimer invalidate];
    _caretBlinkTimer = nil;
    _caretVisible = NO;
    [self _setSelectionNeedsDisplay];
}

- (void)_resetCaretBlink {
    // After text, selection, or focus changes, restart blinking from the visible state.
    [_caretBlinkTimer invalidate];
    _caretBlinkTimer = nil;
    _caretVisible = [self _shouldShowCaret];
    if (_caretVisible) {
        [self _startCaretBlink];
    }
    [self _setSelectionNeedsDisplay];
}

- (void)_caretBlinkTimerDidFire:(NSTimer *)timer {
    (void)timer;
    // If current state does not allow caret display, stop the timer immediately.
    if (![self _shouldShowCaret]) {
        [self _stopCaretBlink];
        return;
    }
    _caretVisible = !_caretVisible;
    [self _setSelectionNeedsDisplay];
}

- (void)_caretFontMetricsForLocation:(NSUInteger)location ascent:(CGFloat *)ascent descent:(CGFloat *)descent {
    id font = nil;
    // Fallback global-layout caret metrics come from the global text.
    if (_innerText.length > 0) {
        NSUInteger index = [self _caretAttributeIndexForText:_innerText location:location];
        if (index != NSNotFound) {
            font = [_innerText attribute:NSFontAttributeName atIndex:index effectiveRange:NULL];
            if (!font) font = [_innerText attribute:(id)kCTFontAttributeName atIndex:index effectiveRange:NULL];
        }
    }
    // Use current typing attributes when there is no text or no font attribute.
    if (!font) font = _currentTypingAttributes[NSFontAttributeName];
    if (!font) font = _currentTypingAttributes[(id)kCTFontAttributeName];
    [self _caretFontMetricsForFont:font ascent:ascent descent:descent];
}

- (CGRect)_caretRectForLocation:(NSUInteger)location {
    location = MIN(location, _innerText.length);
    if ([self _usesParagraphContainerViews]) {
        // Paragraph mode: find the paragraph for the global location, then convert its local caret rect to document coordinates.
        _KKTextViewParagraphContext *context = [self _paragraphContextForLocation:location];
        CGRect rect = [self _localCaretRectForParagraphContext:context location:location];
        return [self _documentRectForLocalRect:rect inParagraphContext:context];
    }

    // Fallback global layout: query _innerLayout for the caret rect directly.
    CGFloat caretAscent = 0;
    CGFloat caretDescent = 0;
    [self _caretFontMetricsForLocation:location ascent:&caretAscent descent:&caretDescent];
    CGFloat caretHeight = caretAscent + caretDescent;
    KKTextPosition *position = [KKTextPosition positionWithOffset:location];
    CGRect rect = [_innerLayout caretRectForPosition:position];
    if (CGRectIsNull(rect)) {
        // If text is empty or layout cannot locate the caret, fall back to the upper-left textContainerInset.
        CGFloat x = _textContainerInset.left;
        CGFloat y = _textContainerInset.top;
        rect = CGRectMake(x, y, 0, caretHeight);
    } else if (!_verticalForm && caretHeight > 0) {
        // For mixed font sizes, center the caret by current font height.
        rect = [self _caretRectByCenteringRect:rect withHeight:caretHeight];
    }
    return rect;
}

- (NSRect)_firstRectForRange:(NSRange)range {
    // IME candidate windows need a screen rect for the character range; compute it first in document coordinates.
    if (!_innerLayout && ![self _usesParagraphContainerViews]) [self _updateLayout];
    if ([self _usesParagraphContainerViews]) {
        range = KKTextViewMakeSafeRange(range, _innerText.length);
        if (range.length == 0) {
            // Empty ranges return the caret rect.
            CGRect caretRect = [self _caretRectForLocation:range.location];
            return CGRectIsNull(caretRect) ? self.bounds : caretRect;
        }

        // For non-empty ranges, return the first rect from the first intersecting paragraph.
        for (_KKTextViewParagraphContext *context in _paragraphContexts) {
            NSRange localRange = [self _localRangeForGlobalRange:range inParagraphContext:context];
            if (localRange.location == NSNotFound || localRange.length == 0) continue;
            CGRect rect = [context.layout firstRectForRange:[KKTextRange rangeWithRange:localRange]];
            rect = [self _documentRectForLocalRect:rect inParagraphContext:context];
            return CGRectIsNull(rect) ? self.bounds : rect;
        }
        return self.bounds;
    }

    // Fallback global layout matches the original YYTextView behavior.
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
    // Default typing attributes are built from font/color/alignment.
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.alignment = _textAlignment;
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    if (_font) attributes[NSFontAttributeName] = _font;
    if (_textColor) attributes[NSForegroundColorAttributeName] = _textColor;
    attributes[NSParagraphStyleAttributeName] = style;
    return attributes;
}

- (UIFont *)_defaultFont {
    // Under platform macros, UIFont maps to NSFont.
    return [NSFont systemFontOfSize:12];
}

- (NSAttributedString *)_attributedStringWithPlainText:(NSString *)text {
    // Plain text input uses current typing attributes by default.
    return [[NSAttributedString alloc] initWithString:text ?: @"" attributes:_currentTypingAttributes];
}

- (void)_updateTypingAttributesForLocation:(NSUInteger)location {
    // Empty text has no attributes to inherit, so return default typing attributes.
    if (_innerText.length == 0) {
        _currentTypingAttributes = [[self _defaultTypingAttributes] mutableCopy];
        return;
    }

    // Non-empty text inherits from the character before the insertion point, or from the first character at document start.
    NSUInteger index = location == 0 ? 0 : MIN(location - 1, _innerText.length - 1);
    NSMutableDictionary *attributes = [[_innerText kk_attributesAtIndex:index] mutableCopy] ?: [NSMutableDictionary dictionary];
    // Discontinuous attributes and borders should not automatically continue onto newly typed characters.
    [attributes removeObjectsForKeys:[NSMutableAttributedString kk_allDiscontinuousAttributeKeys]];
    [attributes removeObjectForKey:KKTextBorderAttributeName];
    [attributes removeObjectForKey:KKTextBackgroundBorderAttributeName];
    _currentTypingAttributes = attributes;
}

- (void)_setInnerAttributedText:(NSAttributedString *)attributedText notify:(BOOL)notify {
    // Replacing the whole text changes all paragraphs, so reset the vertical-key target x.
    [self _resetVerticalMovementTargetX];
    _innerText = attributedText ? attributedText.mutableCopy : [NSMutableAttributedString new];
    // The new text may be shorter, so clamp the old selection.
    _selectedRange = KKTextViewMakeSafeRange(_selectedRange, _innerText.length);
    // Replacing the whole text ends the current IME composition.
    _markedRange = NSMakeRange(NSNotFound, 0);
    [self _parseText];
    [self _updateTypingAttributesForLocation:_selectedRange.location];
    [self _updateLayout];
    if (!_insideUndoOrRedo) {
        // Normal whole-text assignment uses the current content as the new undo baseline; undo/redo restore must not reset the stack.
        [self _resetUndoAndRedoStack];
    }
    if (notify) [self _notifyTextDidChange];
}

- (BOOL)_parseText {
    // Skip when there is no parser.
    if (!_textParser) return NO;
    // The parser may rewrite text and selectedRange, for example to add links or highlighting.
    NSRange selectedRange = _selectedRange;
    BOOL changed = [_textParser parseText:_innerText selectedRange:&selectedRange];
    _selectedRange = KKTextViewMakeSafeRange(selectedRange, _innerText.length);
    return changed;
}

- (void)_replaceRange:(NSRange)range withAttributedString:(NSAttributedString *)attributedString notify:(BOOL)notify {
    // All edit entry points converge here; reset the vertical-key target x first.
    [self _resetVerticalMovementTargetX];
    range = KKTextViewMakeSafeRange(range, _innerText.length);
    NSString *replacementText = attributedString.string ?: @"";
    // User edit paths ask the delegate first; internal silent operations can pass notify:NO to skip it.
    if (notify && _delegate && [_delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]) {
        if (![_delegate textView:self shouldChangeTextInRange:range replacementText:replacementText]) return;
    }
    // Record undo before modification.
    if (notify) {
        [self _recordUndoBeforeEditing];
    }
    // Record the edit range for later paragraph-layout reuse mapping.
    [self _recordParagraphEditRange:range replacementLength:attributedString.length];
    // A nil attributedString means deletion.
    [_innerText replaceCharactersInRange:range withAttributedString:attributedString ?: [NSAttributedString new]];
    // After replacement, place the caret at the end of inserted text and clear marked range.
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
    // Rebuild the undo baseline.
    [_undoStack removeAllObjects];
    [_redoStack removeAllObjects];
    // If undo is disabled or max level is 0, do not save snapshots.
    if (!_allowsUndoAndRedo || _maximumUndoLevel == 0) return;
    [_undoStack addObject:[_KKTextViewUndoState stateWithText:_innerText.copy selectedRange:_selectedRange]];
}

- (void)_resetRedoStack {
    [_redoStack removeAllObjects];
}

- (void)_trimUndoStack:(NSMutableArray<_KKTextViewUndoState *> *)stack {
    // Drop the oldest state when exceeding the maximum undo level.
    while (stack.count > _maximumUndoLevel) {
        [stack removeObjectAtIndex:0];
    }
}

- (void)_trimUndoAndRedoStacks {
    [self _trimUndoStack:_undoStack];
    [self _trimUndoStack:_redoStack];
}

- (void)_saveToUndoStack {
    // Callers do not need to repeat the enable-state check.
    if (!_allowsUndoAndRedo || _maximumUndoLevel == 0) return;
    _KKTextViewUndoState *lastState = _undoStack.lastObject;
    // Do not push duplicate states when text has not changed.
    if ([lastState.text isEqualToAttributedString:_innerText]) return;
    [_undoStack addObject:[_KKTextViewUndoState stateWithText:_innerText.copy selectedRange:_selectedRange]];
    [self _trimUndoStack:_undoStack];
}

- (void)_saveToRedoStack {
    // The redo stack stores the current state before undo.
    if (!_allowsUndoAndRedo || _maximumUndoLevel == 0) return;
    _KKTextViewUndoState *lastState = _redoStack.lastObject;
    if ([lastState.text isEqualToAttributedString:_innerText]) return;
    [_redoStack addObject:[_KKTextViewUndoState stateWithText:_innerText.copy selectedRange:_selectedRange]];
    [self _trimUndoStack:_redoStack];
}

- (void)_recordUndoBeforeEditing {
    // Undo/redo restore mutates storage, but must not record another undo entry.
    if (_insideUndoOrRedo) return;
    [self _saveToUndoStack];
    // Once a new edit happens, old redo history becomes invalid.
    [self _resetRedoStack];
}

- (BOOL)_canUndo {
    _KKTextViewUndoState *state = _undoStack.lastObject;
    // If current text equals the stack top, we are already at that history point.
    return state && ![state.text isEqualToAttributedString:_innerText];
}

- (BOOL)_canRedo {
    _KKTextViewUndoState *state = _redoStack.lastObject;
    // Redo is unavailable when the redo stack is empty or its top is already the current text.
    return state && ![state.text isEqualToAttributedString:_innerText];
}

- (void)_restoreUndoState:(_KKTextViewUndoState *)state {
    // Ignore empty states.
    if (!state) return;
    [self _resetVerticalMovementTargetX];
    _innerText = state.text ? state.text.mutableCopy : [NSMutableAttributedString new];
    _selectedRange = KKTextViewMakeSafeRange(state.selectedRange, _innerText.length);
    // End current marked text before restoring history so stale composition ranges do not point into the new text.
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
    // Keep undo idempotent when there is no undoable state.
    if (![self _canUndo]) return;
    // Save the current state to the redo stack before undo.
    [self _saveToRedoStack];
    _KKTextViewUndoState *state = _undoStack.lastObject;
    [_undoStack removeLastObject];
    // Do not record undo/redo while restoring history.
    _insideUndoOrRedo = YES;
    [self _restoreUndoState:state];
    _insideUndoOrRedo = NO;
}

- (void)_redo {
    // Redo mirrors undo.
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
    // Text changes notify both delegate and Notification observers.
    if (_delegate && [_delegate respondsToSelector:@selector(textViewDidChange:)]) {
        [_delegate textViewDidChange:self];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:KKTextViewTextDidChangeNotification object:self];
    [self _resetCaretBlink];
}

- (void)_notifySelectionDidChange {
    // After selection changes, restart caret blinking so the new position is visible immediately.
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
    // When enabling, establish a new baseline from current text; when disabling, clear history.
    if (_allowsUndoAndRedo) {
        [self _resetUndoAndRedoStack];
    } else {
        [_undoStack removeAllObjects];
        [_redoStack removeAllObjects];
    }
}

- (void)setMaximumUndoLevel:(NSUInteger)maximumUndoLevel {
    _maximumUndoLevel = maximumUndoLevel;
    // Trim old stacks immediately after the maximum level changes.
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
    // setFont is a global style change and updates both existing text and future input style.
    _font = font ?: [self _defaultFont];
    _currentTypingAttributes = [[self _defaultTypingAttributes] mutableCopy];
    if (_innerText.length) [_innerText addAttribute:NSFontAttributeName value:_font range:NSMakeRange(0, _innerText.length)];
    [self _updateLayout];
}

- (void)setTextColor:(UIColor *)textColor {
    // setTextColor likewise applies to all existing text and future input.
    _textColor = textColor ?: NSColor.textColor;
    _currentTypingAttributes = [[self _defaultTypingAttributes] mutableCopy];
    if (_innerText.length) [_innerText addAttribute:NSForegroundColorAttributeName value:_textColor range:NSMakeRange(0, _innerText.length)];
    [self _updateLayout];
}

- (void)setTextAlignment:(NSTextAlignment)textAlignment {
    // Alignment is written into paragraph style, so changes require relayout of all paragraphs.
    _textAlignment = textAlignment;
    _currentTypingAttributes = [[self _defaultTypingAttributes] mutableCopy];
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.alignment = textAlignment;
    if (_innerText.length) [_innerText addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, _innerText.length)];
    [self _updateLayout];
}

- (void)setTextVerticalAlignment:(KKTextVerticalAlignment)textVerticalAlignment {
    // The current macOS text view is top-layout oriented, so vertical alignment changes only trigger redraw.
    _textVerticalAlignment = textVerticalAlignment;
    [self setNeedsDisplay:YES];
}

- (void)setTypingAttributes:(NSDictionary *)typingAttributes {
    // After external typingAttributes are set, future input prefers those attributes.
    _typingAttributes = typingAttributes.copy;
    _currentTypingAttributes = typingAttributes ? typingAttributes.mutableCopy : [[self _defaultTypingAttributes] mutableCopy];
}

- (NSDictionary *)typingAttributes {
    return _typingAttributes ?: _currentTypingAttributes.copy;
}

- (void)setTextParser:(id<KKTextParser>)textParser {
    // Parser changes reparse current text and update layout.
    _textParser = textParser;
    [self _parseText];
    [self _updateLayout];
}

- (void)setTextContainerInset:(UIEdgeInsets)textContainerInset {
    // Insets affect paragraph-view layout and the fallback container.
    _textContainerInset = textContainerInset;
    [self _updateLayout];
}

- (void)setExclusionPaths:(NSArray<UIBezierPath *> *)exclusionPaths {
    // exclusionPaths currently do not use paragraph mode, so changes trigger fallback global relayout.
    _exclusionPaths = exclusionPaths.copy;
    [self _updateLayout];
}

- (void)setVerticalForm:(BOOL)verticalForm {
    // Vertical text currently falls back to global layout; toggling it must rebuild layout/view state.
    _verticalForm = verticalForm;
    [self _updateLayout];
}

- (void)setLinePositionModifier:(id<KKTextLinePositionModifier>)linePositionModifier {
    // Line-position modifiers change each paragraph's height and line positions.
    _linePositionModifier = [(id)linePositionModifier copy];
    [self _updateLayout];
}

- (void)setDebugOption:(KKTextDebugOption *)debugOption {
    // debugOption affects only drawing, not layout.
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
    // Placeholder is drawn only in empty-text fallback mode.
    _placeholderAttributedText = placeholderAttributedText.copy;
    _placeholderInnerText = placeholderAttributedText ? placeholderAttributedText.mutableCopy : [NSMutableAttributedString new];
    [self _updateLayout];
}

- (NSAttributedString *)placeholderAttributedText {
    return _placeholderInnerText.copy;
}

- (void)_updatePlaceholderText {
    // Plain placeholder starts from default typing attributes, then overrides placeholder font/color.
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
    if (!_innerLayout && ![self _usesParagraphContainerViews]) [self _updateLayout];
    // Non-empty ranges use range rects; empty ranges use the caret rect.
    CGRect rect = [self _rectForRange:range];
    if (CGRectIsNull(rect)) return;
    // Scroll calculations need non-zero width and height.
    if (rect.size.width < 1) rect.size.width = 1;
    if (rect.size.height < 1) rect.size.height = 1;

    // Selection scrolling keeps a small margin; caret scrolling adds no extra margin to avoid frequent jumps while typing.
    CGFloat padding = range.length > 0 ? 4 : 0;
    [self _scrollDocumentRectToVisible:rect padding:padding];
    [self _setSelectionNeedsDisplay];
}

- (void)_setSelectedRange:(NSRange)selectedRange updateAnchor:(BOOL)updateAnchor {
    // All selection-setting paths converge here so range, marked text, typing attributes, and display stay synchronized.
    _selectedRange = KKTextViewMakeSafeRange(selectedRange, _innerText.length);
    _markedRange = NSMakeRange(NSNotFound, 0);
    [self _updateTypingAttributesForLocation:NSMaxRange(_selectedRange)];
    if (updateAnchor) {
        // Normal selection updates the anchor; drag/Shift extension keeps the existing anchor.
        _selectionAnchorLocation = _selectedRange.length > 0 ? NSMaxRange(_selectedRange) : _selectedRange.location;
    }
    // For non-empty selection, scroll the active endpoint instead of always scrolling range.start.
    NSUInteger visibleLocation = [self _selectionExtentLocation];
    [self scrollRangeToVisible:NSMakeRange(visibleLocation, 0)];
    [self _setSelectionNeedsDisplay];
    [self _notifySelectionDidChange];
}

- (NSUInteger)_textLocationForPoint:(CGPoint)point {
    if ([self _usesParagraphContainerViews]) {
        // Paragraph mode: find the paragraph from document coordinates, then convert to a local point for that paragraph layout.
        _KKTextViewParagraphContext *context = [self _paragraphContextForPoint:point];
        CGPoint localPoint = [self _localPointForDocumentPoint:point inParagraphContext:context];
        KKTextPosition *position = [context.layout closestPositionToPoint:localPoint];
        if (!position || position.offset < 0) return _innerText.length;
        NSUInteger localLocation = MIN((NSUInteger)position.offset, context.text.length);
        return MIN(context.range.location + localLocation, _innerText.length);
    }

    // Fallback global mode hit tests directly with _innerLayout.
    if (!_innerLayout) [self _updateLayout];
    KKTextPosition *position = [_innerLayout closestPositionToPoint:point];
    if (!position || position.offset < 0) return _innerText.length;
    return MIN((NSUInteger)position.offset, _innerText.length);
}

- (NSPoint)_viewPointForEvent:(NSEvent *)event {
    // NSEvent uses window coordinates; text hit testing needs documentView coordinates.
    return [_textDocumentView convertPoint:event.locationInWindow fromView:nil];
}

- (NSUInteger)_textLocationForEvent:(NSEvent *)event {
    NSPoint point = [self _viewPointForEvent:event];
    return [self _textLocationForPoint:point];
}

- (NSRange)_selectionRangeWithAnchor:(NSUInteger)anchor location:(NSUInteger)location {
    // The anchor and location may be in either direction, so normalize them into a forward NSRange.
    anchor = MIN(anchor, _innerText.length);
    location = MIN(location, _innerText.length);
    NSUInteger start = MIN(anchor, location);
    NSUInteger end = MAX(anchor, location);
    return NSMakeRange(start, end - start);
}

- (NSUInteger)_selectionExtentLocation {
    // The active endpoint is the end currently moving during drag or Shift extension.
    if (_selectedRange.length == 0) return _selectedRange.location;
    if (_selectionAnchorLocation == _selectedRange.location) return NSMaxRange(_selectedRange);
    if (_selectionAnchorLocation == NSMaxRange(_selectedRange)) return _selectedRange.location;
    return NSMaxRange(_selectedRange);
}

- (NSRange)_wordRangeByExtendingLayoutRange:(NSRange)range {
    range = KKTextViewMakeSafeRange(range, _innerText.length);
    if (range.length == 0) return range;
    if ([self _usesParagraphContainerViews]) {
        // In paragraph mode, layout extension only works within one paragraph; cross-paragraph ranges are kept unchanged.
        _KKTextViewParagraphContext *startContext = [self _paragraphContextForLocation:range.location];
        _KKTextViewParagraphContext *endContext = [self _paragraphContextForLocation:NSMaxRange(range)];
        if (!startContext || startContext != endContext) return range;

        // Convert to local range, extend with that paragraph layout, then convert back to global range.
        NSRange localRange = [self _localRangeForGlobalRange:range inParagraphContext:startContext];
        if (localRange.location == NSNotFound) return range;
        KKTextRange *textRange = [KKTextRange rangeWithRange:localRange];
        KKTextRange *extendedStart = [startContext.layout textRangeByExtendingPosition:textRange.start];
        KKTextRange *extendedEnd = [startContext.layout textRangeByExtendingPosition:textRange.end];
        if (extendedStart && extendedEnd) {
            NSArray *positions = [@[extendedStart.start, extendedStart.end, extendedEnd.start, extendedEnd.end]
                                  sortedArrayUsingSelector:@selector(compare:)];
            NSRange extendedRange = [KKTextRange rangeWithStart:positions.firstObject end:positions.lastObject].asRange;
            return KKTextViewMakeSafeRange([self _globalRangeForLocalRange:extendedRange inParagraphContext:startContext], _innerText.length);
        }
        return range;
    }

    // Fallback global mode extends directly on the global layout.
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
    // Empty text has no word range.
    if (_innerText.length == 0) return NSMakeRange(0, 0);

    // Convert the range into the character range used for word enumeration.
    NSUInteger targetLocation = MIN(range.location, _innerText.length - 1);
    NSUInteger targetEnd = range.length > 0 ? MIN(NSMaxRange(range) - 1, _innerText.length - 1) : targetLocation;
    NSRange targetRange = NSMakeRange(targetLocation, targetEnd - targetLocation + 1);
    __block NSRange wordRange = NSMakeRange(NSNotFound, 0);
    // NSStringEnumerationByWords handles language-aware tokenization.
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
    // Feed the word range back to layout extension to include composed-character and complex-glyph boundaries.
    return [self _wordRangeByExtendingLayoutRange:wordRange];
}

- (NSRange)_wordRangeAtPoint:(CGPoint)point {
    // Double-clicking empty text returns an empty range.
    if (_innerText.length == 0) return NSMakeRange(0, 0);
    if ([self _usesParagraphContainerViews]) {
        // Paragraph mode: hit test the paragraph first, then hit test the text range inside it.
        _KKTextViewParagraphContext *context = [self _paragraphContextForPoint:point];
        CGPoint localPoint = [self _localPointForDocumentPoint:point inParagraphContext:context];
        KKTextRange *layoutRange = [context.layout closestTextRangeAtPoint:localPoint];
        if (!layoutRange || layoutRange.asRange.length == 0) {
            // closestTextRange may be empty near glyph edges; fall back to the nearest insertion point and extend left/right.
            NSUInteger location = [self _textLocationForPoint:point];
            NSUInteger localLocation = [self _localLocationForGlobalLocation:location inParagraphContext:context];
            KKTextPosition *position = [KKTextPosition positionWithOffset:localLocation];
            layoutRange = [context.layout textRangeByExtendingPosition:position inDirection:UITextLayoutDirectionRight offset:1];
            if (!layoutRange || layoutRange.asRange.length == 0) {
                layoutRange = [context.layout textRangeByExtendingPosition:position inDirection:UITextLayoutDirectionLeft offset:1];
            }
        }
        if (!layoutRange) {
            // If hit testing still fails, fall back to composed-character range to avoid splitting emoji or combined characters.
            NSUInteger location = MIN([self _textLocationForPoint:point], _innerText.length - 1);
            return [_innerText.string rangeOfComposedCharacterSequenceAtIndex:location];
        }

        // Convert the paragraph-local layout range back to global range before word extension.
        NSRange range = KKTextViewMakeSafeRange([self _globalRangeForLocalRange:layoutRange.asRange inParagraphContext:context], _innerText.length);
        NSRange wordRange = [self _wordRangeEnclosingLayoutRange:range];
        if (wordRange.location != NSNotFound && wordRange.length > 0) return wordRange;

        if (range.length > 0) return [self _wordRangeByExtendingLayoutRange:range];

        NSUInteger safeLocation = MIN(range.location, _innerText.length - 1);
        return [_innerText.string rangeOfComposedCharacterSequenceAtIndex:safeLocation];
    }

    // Fallback global mode hit tests directly on _innerLayout.
    if (!_innerLayout) [self _updateLayout];

    KKTextRange *layoutRange = [_innerLayout closestTextRangeAtPoint:point];
    if (!layoutRange || layoutRange.asRange.length == 0) {
        // If edge hit testing fails, extend from the nearest insertion point to the right or left.
        NSUInteger location = [self _textLocationForPoint:point];
        KKTextPosition *position = [KKTextPosition positionWithOffset:MIN(location, _innerText.length)];
        layoutRange = [_innerLayout textRangeByExtendingPosition:position inDirection:UITextLayoutDirectionRight offset:1];
        if (!layoutRange || layoutRange.asRange.length == 0) {
            layoutRange = [_innerLayout textRangeByExtendingPosition:position inDirection:UITextLayoutDirectionLeft offset:1];
        }
    }
    if (!layoutRange) {
        // Finally fall back to composed-character range.
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
    // During drag or Shift extension, the anchor stays fixed and location is the active endpoint.
    NSRange range = [self _selectionRangeWithAnchor:_selectionAnchorLocation location:location];
    [self _setSelectedRange:range updateAnchor:NO];
}

- (BOOL)_selectedRangeContainsLocation:(NSUInteger)location {
    // Used by the context menu to decide whether the click is inside the current selection.
    if (_selectedRange.length == 0) return NO;
    return _selectedRange.location <= location && location <= NSMaxRange(_selectedRange);
}

- (void)_prepareContextMenuSelectionForEvent:(NSEvent *)event {
    // Do not change selection when the view is neither selectable nor editable.
    if (!_selectable && !_editable) return;
    [self.window makeFirstResponder:self];
    NSUInteger location = [self _textLocationForEvent:event];
    if (![self _selectedRangeContainsLocation:location]) {
        // Right-clicking outside the selection moves the caret to the clicked position.
        _caretActive = YES;
        _selectionAnchorLocation = location;
        [self _setSelectedRange:NSMakeRange(location, 0) updateAnchor:NO];
    } else {
        // Right-clicking inside the selection preserves the selection and only refreshes caret/selection display.
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
    // Menu availability is centralized through canPerformAction so context menus and shortcuts stay consistent.
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
    // If the view is neither selectable nor editable, do not consume mouse events.
    if (!_selectable && !_editable) return;
    // Mouse clicks interrupt the repeated vertical-movement targetX.
    [self _resetVerticalMovementTargetX];
    // Become first responder after clicking the text area so keyboard and IME events are delivered to this view.
    [self.window makeFirstResponder:self];
    _caretActive = YES;

    if (event.clickCount >= 2) {
        // Double-click selects by word.
        CGPoint point = [self _viewPointForEvent:event];
        NSRange range = [self _wordRangeAtPoint:point];
        [self _setSelectedRange:range updateAnchor:YES];
        _trackingSelection = NO;
    } else {
        NSUInteger location = [self _textLocationForEvent:event];
        if ((event.modifierFlags & NSEventModifierFlagShift) != 0) {
            // Shift-click extends the existing selection.
            if (_selectedRange.length == 0) _selectionAnchorLocation = _selectedRange.location;
            [self _extendSelectionToLocation:location];
        } else {
            // A normal click moves the caret and resets the anchor to the clicked position.
            _selectionAnchorLocation = location;
            [self _setSelectedRange:NSMakeRange(location, 0) updateAnchor:NO];
        }
        _trackingSelection = YES;
    }
}

- (void)mouseDragged:(NSEvent *)event {
    // Dragging updates selection only after mouseDown starts tracking.
    if (!_trackingSelection || (!_selectable && !_editable)) return;
    [self _resetVerticalMovementTargetX];
    NSUInteger location = [self _textLocationForEvent:event];
    [self _extendSelectionToLocation:location];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    // Mouse up ends drag selection.
    _trackingSelection = NO;
}

- (void)rightMouseDown:(NSEvent *)event {
    // Use the custom editing menu; if no menu is available, hand back to AppKit's default handling.
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
    // When not editable, ordinary text input is passed to the responder chain.
    if (!_editable) {
        [super keyDown:event];
        return;
    }
    _caretActive = YES;
    [self _resetCaretBlink];
    // interpretKeyEvents sends ordinary characters to insertText:replacementRange:,
    // and sends arrow keys, delete, return, and other control keys to doCommandBySelector:.
    [self interpretKeyEvents:@[event]];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    // Intercept only Command key combinations; normal keys go through keyDown/IME.
    if ((event.modifierFlags & NSEventModifierFlagCommand) == 0) return [super performKeyEquivalent:event];
    NSString *characters = event.charactersIgnoringModifiers.lowercaseString;
    BOOL shiftPressed = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    if ([characters isEqualToString:@"z"]) {
        // Command-Z undo，Shift-Command-Z redo。
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
    // Delete only when editable and real text exists.
    if (!_editable || _innerText.length == 0) return;
    [self _resetVerticalMovementTargetX];
    // During IME composition, delete marked text first; otherwise delete selection or the character before caret.
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
    // Left/right movement does not preserve the vertical-movement targetX.
    [self _resetVerticalMovementTargetX];
    if (_selectedRange.length > 0) {
        // With a selection, moving left collapses to the selection start.
        self.selectedRange = NSMakeRange(_selectedRange.location, 0);
    } else if (_selectedRange.location > 0) {
        self.selectedRange = NSMakeRange(_selectedRange.location - 1, 0);
    }
}

- (void)moveRight:(id)sender {
    [self _resetVerticalMovementTargetX];
    if (_selectedRange.length > 0) {
        // With a selection, moving right collapses to the selection end.
        self.selectedRange = NSMakeRange(NSMaxRange(_selectedRange), 0);
    } else if (_selectedRange.location < _innerText.length) {
        self.selectedRange = NSMakeRange(_selectedRange.location + 1, 0);
    }
}

- (void)moveLeftAndModifySelection:(id)sender {
    [self _resetVerticalMovementTargetX];
    // Shift-left keeps the anchor fixed and moves the active endpoint one offset left.
    NSUInteger location = [self _selectionExtentLocation];
    if (_selectedRange.length == 0) _selectionAnchorLocation = _selectedRange.location;
    if (location > 0) location--;
    [self _extendSelectionToLocation:location];
}

- (NSUInteger)_locationByMovingFromLocation:(NSUInteger)location inDirection:(UITextLayoutDirection)direction {
    if ([self _usesParagraphContainerViews]) {
        // In paragraph mode, left/right movement simply moves by global offset.
        location = MIN(location, _innerText.length);
        if (direction == UITextLayoutDirectionLeft) return location > 0 ? location - 1 : location;
        if (direction == UITextLayoutDirectionRight) return location < _innerText.length ? location + 1 : location;

        // Up/down movement first locates the current paragraph and line, then uses targetX to find the target-line position.
        _KKTextViewParagraphContext *context = [self _paragraphContextForLocation:location];
        if (!context.layout) return location;
        NSUInteger localLocation = [self _localLocationForGlobalLocation:location inParagraphContext:context];
        CGFloat targetX = [self _verticalMovementTargetXForLocation:location];

        NSUInteger currentLineIndex = [self _lineIndexForParagraphContext:context localLocation:localLocation];
        NSUInteger targetLineIndex = [self _lineIndexInParagraphContext:context fromLineIndex:currentLineIndex direction:direction];
        NSUInteger targetLocation = [self _textLocationInParagraphContext:context lineIndex:targetLineIndex targetX:targetX];
        // If a target line is found within the same paragraph, return it directly.
        if (targetLocation != NSNotFound) return targetLocation;

        // If there is no previous/next line in the same paragraph, cross into the neighboring paragraph.
        NSUInteger contextIndex = [_paragraphContexts indexOfObjectIdenticalTo:context];
        if (contextIndex == NSNotFound) return location;
        if (direction == UITextLayoutDirectionUp) {
            if (contextIndex == 0) return location;
            context = _paragraphContexts[contextIndex - 1];
        } else if (direction == UITextLayoutDirectionDown) {
            if (contextIndex + 1 >= _paragraphContexts.count) return location;
            context = _paragraphContexts[contextIndex + 1];
        } else {
            return location;
        }

        // After crossing paragraphs, use the target paragraph's edge real line and hit test with the same targetX.
        targetLineIndex = [self _edgeLineIndexForParagraphContext:context direction:direction];
        targetLocation = [self _textLocationInParagraphContext:context lineIndex:targetLineIndex targetX:targetX];
        return targetLocation == NSNotFound ? location : targetLocation;
    }

    // The fallback global layout uses KKTextLayout's built-in direction extension.
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
        // At the end of a line break, layout may return the same position; step back before the line break to avoid up/down getting stuck.
        NSString *textBeforeLocation = [_innerText.string substringToIndex:location];
        NSUInteger lineBreakTailLength = KKTextLinebreakTailLength(textBeforeLocation);
        if (lineBreakTailLength > 0) {
            targetLocation = location - lineBreakTailLength;
        }
    }
    return targetLocation;
}

- (void)_moveSelectionEndpointInDirection:(UITextLayoutDirection)direction {
    // Shift-up/down reuses the same active-endpoint movement logic.
    NSUInteger location = [self _selectionExtentLocation];
    if (_selectedRange.length == 0) _selectionAnchorLocation = _selectedRange.location;
    location = [self _locationByMovingFromLocation:location inDirection:direction];
    [self _extendSelectionToLocation:location];
}

- (void)moveUp:(id)sender {
    (void)sender;
    if (_selectedRange.length > 0) {
        // With a selection, moving up first collapses to the selection start.
        [self _resetVerticalMovementTargetX];
        self.selectedRange = NSMakeRange(_selectedRange.location, 0);
        return;
    }
    NSUInteger location = [self _locationByMovingFromLocation:_selectedRange.location inDirection:UITextLayoutDirectionUp];
    self.selectedRange = NSMakeRange(location, 0);
}

- (void)moveDown:(id)sender {
    (void)sender;
    if (_selectedRange.length > 0) {
        // With a selection, moving down first collapses to the selection end.
        [self _resetVerticalMovementTargetX];
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
    [self _resetVerticalMovementTargetX];
    // Shift-right keeps the anchor fixed and moves the active endpoint one offset right.
    NSUInteger location = [self _selectionExtentLocation];
    if (_selectedRange.length == 0) _selectionAnchorLocation = _selectedRange.location;
    if (location < _innerText.length) location++;
    [self _extendSelectionToLocation:location];
}

- (void)moveToBeginningOfDocument:(id)sender {
    [self _resetVerticalMovementTargetX];
    self.selectedRange = NSMakeRange(0, 0);
}

- (void)moveToEndOfDocument:(id)sender {
    [self _resetVerticalMovementTargetX];
    self.selectedRange = NSMakeRange(_innerText.length, 0);
}

- (void)moveToBeginningOfDocumentAndModifySelection:(id)sender {
    [self _resetVerticalMovementTargetX];
    if (_selectedRange.length == 0) _selectionAnchorLocation = _selectedRange.location;
    [self _extendSelectionToLocation:0];
}

- (void)moveToEndOfDocumentAndModifySelection:(id)sender {
    [self _resetVerticalMovementTargetX];
    if (_selectedRange.length == 0) _selectionAnchorLocation = _selectedRange.location;
    [self _extendSelectionToLocation:_innerText.length];
}

- (void)selectAll:(id)sender {
    // Select all is available only when selectable.
    if (!_selectable) return;
    [self _resetVerticalMovementTargetX];
    self.selectedRange = NSMakeRange(0, _innerText.length);
}

- (NSData *)_RTFDataForAttributedString:(NSAttributedString *)attributedString {
    // RTF is used to exchange rich text with the system and other apps.
    if (attributedString.length == 0) return nil;
    NSDictionary *documentAttributes = @{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType};
    NSData *data = nil;
    @try {
        // Some custom attributes may throw during RTF export, so copy needs a fallback.
        data = [attributedString dataFromRange:NSMakeRange(0, attributedString.length)
                            documentAttributes:documentAttributes
                                         error:nil];
    } @catch (__unused NSException *exception) {
        data = nil;
    }
    return data;
}

- (NSAttributedString *)_attributedStringFromRTFData:(NSData *)data {
    // When pasting RTF from external apps, try to restore it as an attributed string.
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
        // Prefer KKText custom archives because they preserve KKText-specific attributes.
        NSData *data = [pasteboard dataForType:KKTextViewPasteboardTypeAttributedString];
        if (data.length > 0) {
            NSAttributedString *attributedString = [NSAttributedString kk_unarchiveFromData:data];
            if (attributedString.length > 0) return attributedString;
        }

        // Then read system RTF for rich-text compatibility with other apps.
        data = [pasteboard dataForType:NSPasteboardTypeRTF];
        NSAttributedString *rtfString = [self _attributedStringFromRTFData:data];
        if (rtfString.length > 0) return rtfString;
    }

    // Finally fall back to plain text and apply current typing attributes.
    NSString *string = [pasteboard stringForType:NSPasteboardTypeString];
    if (string.length == 0) return nil;
    return [self _attributedStringWithPlainText:string];
}

- (BOOL)_isPasteboardContainsValidValue {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    // Plain text is always pasteable.
    if ([pasteboard stringForType:NSPasteboardTypeString].length > 0) return YES;
    if (_allowsPasteAttributedString) {
        // Rich-text paste is controlled by the feature switch.
        if ([pasteboard dataForType:KKTextViewPasteboardTypeAttributedString].length > 0) return YES;
        if ([pasteboard dataForType:NSPasteboardTypeRTF].length > 0) return YES;
    }
    return NO;
}

- (void)copy:(id)sender {
    // Do not modify the pasteboard when there is no selection.
    if (_selectedRange.length == 0) return;

    NSAttributedString *attributedString = [_innerText attributedSubstringFromRange:_selectedRange];
    NSString *plainText = [_innerText kk_plainTextForRange:_selectedRange];
    // plainText may be empty after attachment filtering; fall back to attributedString.string.
    if (plainText.length == 0) plainText = attributedString.string ?: @"";

    NSData *archivedData = nil;
    NSData *rtfData = nil;
    NSMutableArray<NSPasteboardType> *types = [NSMutableArray array];
    if (plainText.length > 0) {
        [types addObject:NSPasteboardTypeString];
    }
    if (_allowsCopyAttributedString && attributedString.length > 0) {
        // Write both custom archive and RTF: the former is lossless for KKText, the latter works across apps.
        archivedData = [attributedString kk_archiveToData];
        if (archivedData.length > 0) {
            [types addObject:KKTextViewPasteboardTypeAttributedString];
        }
        rtfData = [self _RTFDataForAttributedString:attributedString];
        if (rtfData.length > 0) {
            [types addObject:NSPasteboardTypeRTF];
        }
    }
    // Do not clear the existing pasteboard if there is no writable type.
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
    // cut = copy + delete selection.
    if (!_editable || _selectedRange.length == 0) return;
    [self copy:sender];
    [self _replaceRange:_selectedRange withAttributedString:[NSAttributedString new] notify:YES];
}

- (void)paste:(id)sender {
    // paste only works while editable.
    if (!_editable) return;
    NSAttributedString *attributedString = [self _attributedStringFromPasteboard:NSPasteboard.generalPasteboard];
    if (attributedString.length == 0) return;
    [self insertText:attributedString replacementRange:NSMakeRange(NSNotFound, 0)];
}

#pragma mark - NSTextInputClient

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
    // Final NSTextInputClient commit entry: normal keyboard input and IME commit both arrive here.
    if (!_editable) return;
    _caretActive = YES;
    NSAttributedString *attributedString;
    if ([string isKindOfClass:NSAttributedString.class]) {
        // IMEs may commit an attributed string.
        attributedString = string;
    } else {
        // Plain strings use current typing attributes.
        attributedString = [self _attributedStringWithPlainText:[string description]];
    }
    // Prefer replacementRange; otherwise marked text takes priority over normal selectedRange.
    NSRange replaceRange = replacementRange.location != NSNotFound ? replacementRange : (self.hasMarkedText ? _markedRange : _selectedRange);
    [self _replaceRange:replaceRange withAttributedString:attributedString notify:YES];
}

- (void)doCommandBySelector:(SEL)selector {
    // interpretKeyEvents translates control keys into selectors; map them to KKTextView editing methods here.
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
        // IMEs may provide attributed marked text.
        markedText = [(NSAttributedString *)string mutableCopy];
    } else {
        NSString *plainText = string ? [string description] : @"";
        markedText = [[NSMutableAttributedString alloc] initWithString:plainText];
    }
    NSRange fullRange = NSMakeRange(0, markedText.length);
    // Empty marked text does not need style completion.
    if (fullRange.length == 0) return markedText;

    // Marked text first inherits current typing attributes so pre-edit and final input share the same style.
    [_currentTypingAttributes enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        (void)stop;
        [markedText addAttribute:key value:obj range:fullRange];
    }];
    // If IME-provided attributes lack font/color, fill them with current defaults.
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

    // Show marked text with a light background and underline to indicate IME pre-edit state.
    KKTextBorder *border = [KKTextBorder borderWithFillColor:[NSColor.keyboardFocusIndicatorColor colorWithAlphaComponent:0.10] cornerRadius:3];
    border.insets = UIEdgeInsetsMake(-1, -2, -1, -2);
    [markedText kk_setTextBackgroundBorder:border range:fullRange];

    NSRange selectedMarkedRange = KKTextViewMakeSafeRange(selectedRange, markedText.length);
    if (selectedMarkedRange.length > 0) {
        // The selected subrange inside marked text uses a stronger background.
        KKTextBorder *selectedBorder = [KKTextBorder borderWithFillColor:[NSColor.keyboardFocusIndicatorColor colorWithAlphaComponent:0.18] cornerRadius:3];
        selectedBorder.insets = UIEdgeInsetsMake(-1, -2, -1, -2);
        [markedText kk_setTextBackgroundBorder:selectedBorder range:selectedMarkedRange];
    }
    return markedText;
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange {
    // IME pre-edit entry: marked text is temporarily written into _innerText for layout and candidate-window positioning.
    if (!_editable) return;
    _caretActive = YES;
    BOOL startsMarkedText = !self.hasMarkedText;
    NSAttributedString *markedText = [self _markedTextWithInput:string selectedRange:selectedRange];
    // Prefer replacementRange; otherwise replace old marked text or the current selection.
    NSRange replaceRange = replacementRange.location != NSNotFound ? replacementRange : (self.hasMarkedText ? _markedRange : _selectedRange);
    replaceRange = KKTextViewMakeSafeRange(replaceRange, _innerText.length);
    if (startsMarkedText) {
        // Record undo only when a composition starts, avoiding an undo step for every IME update.
        [self _recordUndoBeforeEditing];
    }
    // Marked-text changes also record paragraph edits, which helps local layout reuse.
    [self _recordParagraphEditRange:replaceRange replacementLength:markedText.length];
    [_innerText replaceCharactersInRange:replaceRange withAttributedString:markedText];
    _markedRange = NSMakeRange(replaceRange.location, markedText.length);
    // selectedRange is inside marked text, so convert it to global selectedRange.
    _selectedRange = NSMakeRange(_markedRange.location + selectedRange.location, selectedRange.length);
    _selectedRange = KKTextViewMakeSafeRange(_selectedRange, _innerText.length);
    [self _updateTypingAttributesForLocation:NSMaxRange(_selectedRange)];
    [self _updateLayout];
    [self scrollRangeToVisible:_selectedRange];
    [self _notifyTextDidChange];
    [self _notifySelectionDidChange];
}

- (void)unmarkText {
    // Keep this idempotent when there is no marked text.
    if (!self.hasMarkedText) return;
    NSRange markedRange = KKTextViewMakeSafeRange(_markedRange, _innerText.length);
    if (markedRange.length > 0) {
        // After commit, remove temporary IME styling and restore current typing attributes.
        [_innerText setAttributes:_currentTypingAttributes range:markedRange];
        [_innerText kk_removeDiscontinuousAttributesInRange:markedRange];
    }
    _markedRange = NSMakeRange(NSNotFound, 0);
    [self _parseText];
    [self _updateLayout];
    [self _resetCaretBlink];
}

- (BOOL)hasMarkedText {
    // NSNotFound means there is no marked text.
    return _markedRange.location != NSNotFound && _markedRange.length > 0;
}

- (NSRange)markedRange {
    return self.hasMarkedText ? _markedRange : NSMakeRange(NSNotFound, 0);
}

- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText {
    // Tell the IME which marked-text attributes this view supports.
    return @[NSFontAttributeName,
             NSForegroundColorAttributeName,
             NSParagraphStyleAttributeName,
             NSUnderlineStyleAttributeName,
             NSUnderlineColorAttributeName,
             NSMarkedClauseSegmentAttributeName];
}

- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    // When the IME asks for text contents, return a clipped attributed substring.
    range = KKTextViewMakeSafeRange(range, _innerText.length);
    if (actualRange) *actualRange = range;
    return [_innerText attributedSubstringFromRange:range];
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point {
    // The IME provides screen coordinates; convert to window and then documentView coordinates before hit testing.
    if (!self.window) return NSNotFound;
    NSPoint windowPoint = [self.window convertPointFromScreen:point];
    NSPoint viewPoint = [_textDocumentView convertPoint:windowPoint fromView:nil];
    NSUInteger location = [self _textLocationForPoint:viewPoint];
    return location == NSNotFound ? NSNotFound : MIN(location, _innerText.length);
}

- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    // IME candidate windows need a screen rect, so convert document rect to window and then to screen.
    range = KKTextViewMakeSafeRange(range, _innerText.length);
    if (actualRange) *actualRange = range;
    NSRect rect = [self _firstRectForRange:range];
    rect = [_textDocumentView convertRect:rect toView:nil];
    return self.window ? [self.window convertRectToScreen:rect] : rect;
}

- (CGFloat)fractionOfDistanceThroughGlyphForPoint:(NSPoint)point {
    (void)point;
    // Glyph-internal distance is not refined yet; return 0 to mean near the glyph start.
    return 0;
}

- (NSInteger)windowLevel {
    // IMEs use windowLevel to decide candidate-window layering.
    return self.window.level;
}

#pragma mark - Compatibility

- (BOOL)canBecomeFirstResponder {
    // Keep UIKit naming compatibility and forward to AppKit acceptsFirstResponder.
    return [self acceptsFirstResponder];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    // Validate system menu items against current undo/redo state.
    if (item.action == @selector(undo:)) return [self _canUndo];
    if (item.action == @selector(redo:)) return [self _canRedo];
    return YES;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    // Centralize availability for context menus, system menus, and Command shortcuts.
    if (action == @selector(copy:)) return _selectedRange.length > 0;
    if (action == @selector(cut:)) return _editable && _selectedRange.length > 0;
    if (action == @selector(paste:)) return _editable && [self _isPasteboardContainsValidValue];
    if (action == @selector(selectAll:)) return (_selectable || _editable) && _innerText.length > 0;
    if (action == @selector(undo:)) return _editable && [self _canUndo];
    if (action == @selector(redo:)) return _editable && [self _canRedo];
    return [super respondsToSelector:action];
}

@end

#endif
