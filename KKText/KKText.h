//
//  KKText.h
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/08.
//  Originally created by ibireme.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "KKTextPlatform.h"

#if __has_include(<KKText/KKText.h>)
FOUNDATION_EXPORT double KKTextVersionNumber;
FOUNDATION_EXPORT const unsigned char KKTextVersionString[];
#import <KKText/KKLabel.h>
#if KKTEXT_UIKIT
#import <KKText/KKTextView.h>
#endif
#import <KKText/KKTextAttribute.h>
#import <KKText/KKTextArchiver.h>
#import <KKText/KKTextParser.h>
#import <KKText/KKTextRunDelegate.h>
#import <KKText/KKTextRubyAnnotation.h>
#import <KKText/KKTextLayout.h>
#import <KKText/KKTextLine.h>
#import <KKText/KKTextInput.h>
#import <KKText/KKTextDebugOption.h>
#if KKTEXT_UIKIT
#import <KKText/KKTextKeyboardManager.h>
#endif
#import <KKText/KKTextUtilities.h>
#import <KKText/NSAttributedString+KKText.h>
#import <KKText/NSParagraphStyle+KKText.h>
#if KKTEXT_UIKIT
#import <KKText/UIPasteboard+KKText.h>
#endif
#else
#import "KKLabel.h"
#if KKTEXT_UIKIT
#import "KKTextView.h"
#endif
#import "KKTextAttribute.h"
#import "KKTextArchiver.h"
#import "KKTextParser.h"
#import "KKTextRunDelegate.h"
#import "KKTextRubyAnnotation.h"
#import "KKTextLayout.h"
#import "KKTextLine.h"
#import "KKTextInput.h"
#import "KKTextDebugOption.h"
#if KKTEXT_UIKIT
#import "KKTextKeyboardManager.h"
#endif
#import "KKTextUtilities.h"
#import "NSAttributedString+KKText.h"
#import "NSParagraphStyle+KKText.h"
#if KKTEXT_UIKIT
#import "UIPasteboard+KKText.h"
#endif
#endif
