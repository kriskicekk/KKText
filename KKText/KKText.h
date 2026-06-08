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

#import <UIKit/UIKit.h>

#if __has_include(<KKText/KKText.h>)
FOUNDATION_EXPORT double KKTextVersionNumber;
FOUNDATION_EXPORT const unsigned char KKTextVersionString[];
#import <KKText/KKLabel.h>
#import <KKText/KKTextView.h>
#import <KKText/KKTextAttribute.h>
#import <KKText/KKTextArchiver.h>
#import <KKText/KKTextParser.h>
#import <KKText/KKTextRunDelegate.h>
#import <KKText/KKTextRubyAnnotation.h>
#import <KKText/KKTextLayout.h>
#import <KKText/KKTextLine.h>
#import <KKText/KKTextInput.h>
#import <KKText/KKTextDebugOption.h>
#import <KKText/KKTextKeyboardManager.h>
#import <KKText/KKTextUtilities.h>
#import <KKText/NSAttributedString+KKText.h>
#import <KKText/NSParagraphStyle+KKText.h>
#import <KKText/UIPasteboard+KKText.h>
#else
#import "KKLabel.h"
#import "KKTextView.h"
#import "KKTextAttribute.h"
#import "KKTextArchiver.h"
#import "KKTextParser.h"
#import "KKTextRunDelegate.h"
#import "KKTextRubyAnnotation.h"
#import "KKTextLayout.h"
#import "KKTextLine.h"
#import "KKTextInput.h"
#import "KKTextDebugOption.h"
#import "KKTextKeyboardManager.h"
#import "KKTextUtilities.h"
#import "NSAttributedString+KKText.h"
#import "NSParagraphStyle+KKText.h"
#import "UIPasteboard+KKText.h"
#endif
