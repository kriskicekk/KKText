//
//  KKTextArchiver.h
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

NS_ASSUME_NONNULL_BEGIN

/**
 A subclass of `NSKeyedArchiver` which implement `NSKeyedArchiverDelegate` protocol.
 
 The archiver can encode the object which contains
 CGColor/CGImage/CTRunDelegateRef/.. (such as NSAttributedString).
 */
@interface KKTextArchiver : NSKeyedArchiver <NSKeyedArchiverDelegate>
@end

/**
 A subclass of `NSKeyedUnarchiver` which implement `NSKeyedUnarchiverDelegate` 
 protocol. The unarchiver can decode the data which is encoded by 
 `KKTextArchiver` or `NSKeyedArchiver`.
 */
@interface KKTextUnarchiver : NSKeyedUnarchiver <NSKeyedUnarchiverDelegate>
@end

NS_ASSUME_NONNULL_END
