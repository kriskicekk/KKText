//
//  KKTextArchiver.m
//  KKText <https://github.com/kriskicekk/KKText>
//
//  Created by kris on 2026/06/08.
//  Originally created by ibireme.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "KKTextArchiver.h"
#import "KKTextRunDelegate.h"
#import "KKTextRubyAnnotation.h"

/**
 When call CTRunDelegateGetTypeID() on some devices (runs iOS6), I got the error:
 "dyld: lazy symbol binding failed: Symbol not found: _CTRunDelegateGetTypeID"
 
 Here's a workaround for this issue.
 */
static CFTypeID CTRunDelegateTypeID(void) {
    static CFTypeID typeID;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        /*
        if ((long)CTRunDelegateGetTypeID + 1 > 1) { //avoid compiler optimization
            typeID = CTRunDelegateGetTypeID();
        }
         */
        KKTextRunDelegate *delegate = [KKTextRunDelegate new];
        CTRunDelegateRef ref = delegate.CTRunDelegate;
        typeID = CFGetTypeID(ref);
        CFRelease(ref);
    });
    return typeID;
}

static CFTypeID CTRubyAnnotationTypeID(void) {
    static CFTypeID typeID;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if ((long)CTRubyAnnotationGetTypeID + 1 > 1) { //avoid compiler optimization
            typeID = CTRunDelegateGetTypeID();
        } else {
            typeID = kCFNotFound;
        }
    });
    return typeID;
}

/**
 A wrapper for CGColorRef. Used for Archive/Unarchive/Copy.
 */
@interface _KKCGColor : NSObject <NSCopying, NSCoding>
@property (nonatomic, assign) CGColorRef CGColor;
+ (instancetype)colorWithCGColor:(CGColorRef)CGColor;
@end

@implementation _KKCGColor

+ (instancetype)colorWithCGColor:(CGColorRef)CGColor {
    _KKCGColor *color = [self new];
    color.CGColor = CGColor;
    return color;
}

- (void)setCGColor:(CGColorRef)CGColor {
    if (_CGColor != CGColor) {
        if (CGColor) CGColor = (CGColorRef)CFRetain(CGColor);
        if (_CGColor) CFRelease(_CGColor);
        _CGColor = CGColor;
    }
}

- (void)dealloc {
    if (_CGColor) CFRelease(_CGColor);
    _CGColor = NULL;
}

- (id)copyWithZone:(NSZone *)zone {
    _KKCGColor *color = [self.class new];
    color.CGColor = self.CGColor;
    return color;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    UIColor *color = [UIColor colorWithCGColor:_CGColor];
    [aCoder encodeObject:color forKey:@"color"];
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [self init];
    UIColor *color = [aDecoder decodeObjectForKey:@"color"];
    self.CGColor = color.CGColor;
    return self;
}

@end

/**
 A wrapper for CGImageRef. Used for Archive/Unarchive/Copy.
 */
@interface _KKCGImage : NSObject <NSCoding, NSCopying>
@property (nonatomic, assign) CGImageRef CGImage;
+ (instancetype)imageWithCGImage:(CGImageRef)CGImage;
@end

@implementation _KKCGImage

+ (instancetype)imageWithCGImage:(CGImageRef)CGImage {
    _KKCGImage *image = [self new];
    image.CGImage = CGImage;
    return image;
}

- (void)setCGImage:(CGImageRef)CGImage {
    if (_CGImage != CGImage) {
        if (CGImage) CGImage = (CGImageRef)CFRetain(CGImage);
        if (_CGImage) CFRelease(_CGImage);
        _CGImage = CGImage;
    }
}

- (void)dealloc {
    if (_CGImage) CFRelease(_CGImage);
}

- (id)copyWithZone:(NSZone *)zone {
    _KKCGImage *image = [self.class new];
    image.CGImage = self.CGImage;
    return image;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    UIImage *image = [UIImage imageWithCGImage:_CGImage];
    [aCoder encodeObject:image forKey:@"image"];
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [self init];
    UIImage *image = [aDecoder decodeObjectForKey:@"image"];
    self.CGImage = image.CGImage;
    return self;
}

@end


@interface KKTextArchiver ()
- (instancetype)_initForKKTextArchiving;
@end

@implementation KKTextArchiver

+ (NSData *)kk_archivedDataWithRootObject:(id)rootObject {
    if (!rootObject) return nil;
    KKTextArchiver *archiver = [[[self class] alloc] _initForKKTextArchiving];
    [archiver encodeObject:rootObject forKey:NSKeyedArchiveRootObjectKey];
    [archiver finishEncoding];
    return archiver.encodedData;
}

+ (BOOL)kk_archiveRootObject:(id)rootObject toFile:(NSString *)path {
    NSData *data = [self kk_archivedDataWithRootObject:rootObject];
    if (!data) return NO;
    return [data writeToFile:path atomically:YES];
}

- (instancetype)_initForKKTextArchiving {
    self = [super initRequiringSecureCoding:NO];
    if (self) {
        self.delegate = self;
    }
    return self;
}

- (id)archiver:(NSKeyedArchiver *)archiver willEncodeObject:(id)object {
    CFTypeID typeID = CFGetTypeID((CFTypeRef)object);
    if (typeID == CTRunDelegateTypeID()) {
        CTRunDelegateRef runDelegate = (__bridge CFTypeRef)(object);
        id ref = CTRunDelegateGetRefCon(runDelegate);
        if (ref) return ref;
    } else if (typeID == CTRubyAnnotationTypeID()) {
        CTRubyAnnotationRef ctRuby = (__bridge CFTypeRef)(object);
        KKTextRubyAnnotation *ruby = [KKTextRubyAnnotation rubyWithCTRubyRef:ctRuby];
        if (ruby) return ruby;
    } else if (typeID == CGColorGetTypeID()) {
        return [_KKCGColor colorWithCGColor:(CGColorRef)object];
    } else if (typeID == CGImageGetTypeID()) {
        return [_KKCGImage imageWithCGImage:(CGImageRef)object];
    }
    return object;
}

@end


@interface KKTextUnarchiver ()
- (instancetype)_initForKKTextUnarchivingFromData:(NSData *)data error:(NSError **)error;
@end

@implementation KKTextUnarchiver

+ (id)kk_unarchiveObjectWithData:(NSData *)data {
    if (data.length == 0) return nil;
    NSError *error = nil;
    KKTextUnarchiver *unarchiver = [[self alloc] _initForKKTextUnarchivingFromData:data error:&error];
    if (!unarchiver) return nil;
    id object = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
    [unarchiver finishDecoding];
    return object;
}

+ (id)kk_unarchiveObjectWithFile:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    return [self kk_unarchiveObjectWithData:data];
}

- (instancetype)_initForKKTextUnarchivingFromData:(NSData *)data error:(NSError **)error {
    self = [super initForReadingFromData:data error:error];
    if (self) {
        self.requiresSecureCoding = NO;
        self.delegate = self;
    }
    return self;
}

- (id)unarchiver:(NSKeyedUnarchiver *)unarchiver didDecodeObject:(id) NS_RELEASES_ARGUMENT object NS_RETURNS_RETAINED {
    if ([object class] == [KKTextRunDelegate class]) {
        KKTextRunDelegate *runDelegate = object;
        CTRunDelegateRef ct = runDelegate.CTRunDelegate;
        id ctObj = (__bridge id)ct;
        if (ct) CFRelease(ct);
        return ctObj;
    } else if ([object class] == [KKTextRubyAnnotation class]) {
        KKTextRubyAnnotation *ruby = object;
        if (KKTextPlatformSystemVersion() >= 8) {
            CTRubyAnnotationRef ct = ruby.CTRubyAnnotation;
            id ctObj = (__bridge id)(ct);
            if (ct) CFRelease(ct);
            return ctObj;
        } else {
            return object;
        }
    } else if ([object class] == [_KKCGColor class]) {
        _KKCGColor *color = object;
        return (id)color.CGColor;
    } else if ([object class] == [_KKCGImage class]) {
        _KKCGImage *image = object;
        return (id)image.CGImage;
    }
    return object;
}

@end
