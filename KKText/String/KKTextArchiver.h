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

/**
 Archives a root object with KKText's delegate conversion for Core Text and
 Core Graphics bridge objects.
 */
+ (nullable NSData *)kk_archivedDataWithRootObject:(id)rootObject;
+ (BOOL)kk_archiveRootObject:(id)rootObject toFile:(NSString *)path;

@end

/**
 A subclass of `NSKeyedUnarchiver` which implement `NSKeyedUnarchiverDelegate` 
 protocol. The unarchiver can decode the data which is encoded by 
 `KKTextArchiver` or `NSKeyedArchiver`.
 */
@interface KKTextUnarchiver : NSKeyedUnarchiver <NSKeyedUnarchiverDelegate>

/**
 Unarchives data produced by `KKTextArchiver` while restoring Core Text and
 Core Graphics bridge objects.
 */
+ (nullable id)kk_unarchiveObjectWithData:(NSData *)data;
+ (nullable id)kk_unarchiveObjectWithFile:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
