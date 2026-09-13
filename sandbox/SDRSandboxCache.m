/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRSandboxCache.h"
#import "SDRSandboxDirectory.h"

@implementation SDRSandboxCache

+ (instancetype)sharedCache { static id s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [self new]; }); return s; }

- (BOOL)clearCacheForPackage:(NSString *)packageName error:(NSError **)error {
    NSString *root = [[SDRSandboxDirectory sharedDirectory] ensureDataRootForPackage:packageName];
    NSString *cacheDir = [root stringByAppendingPathComponent:@"cache"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:cacheDir]) return YES;
    return [fm removeItemAtPath:cacheDir error:error];
}

- (BOOL)clearAllCaches:(NSError **)error {
    NSArray<NSString *> *pkgs = [[SDRSandboxDirectory sharedDirectory] installedPackageNames];
    for (NSString *pkg in pkgs) {
        NSError *e = nil;
        if (![self clearCacheForPackage:pkg error:&e]) {
            if (error) *error = e;
            return NO;
        }
    }
    return YES;
}

- (unsigned long long)cacheSizeForPackage:(NSString *)packageName {
    NSString *root = [[SDRSandboxDirectory sharedDirectory] ensureDataRootForPackage:packageName];
    NSString *cacheDir = [root stringByAppendingPathComponent:@"cache"];
    return [self directorySizeAtPath:cacheDir];
}

- (unsigned long long)totalCacheSize {
    unsigned long long total = 0;
    for (NSString *pkg in [[SDRSandboxDirectory sharedDirectory] installedPackageNames]) {
        total += [self cacheSizeForPackage:pkg];
    }
    return total;
}

- (unsigned long long)directorySizeAtPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    unsigned long long total = 0;
    NSError *err = nil;
    NSArray *items = [fm contentsOfDirectoryAtPath:path error:&err];
    for (NSString *item in items ?: @[]) {
        NSString *full = [path stringByAppendingPathComponent:item];
        NSDictionary *attrs = [fm attributesOfItemAtPath:full error:NULL];
        if ([attrs[NSFileType] isEqualToString:NSFileTypeDirectory]) {
            total += [self directorySizeAtPath:full];
        } else {
            total += [attrs[NSFileSize] unsignedLongLongValue];
        }
    }
    return total;
}

@end