/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRSandboxPermission.h"
#import "SDRSandboxDirectory.h"

@implementation SDRSandboxPermission {
    NSString *_currentPackage;
}

+ (instancetype)sharedPermission { static id s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [self new]; }); return s; }

- (void)enterPackage:(NSString *)packageName { _currentPackage = [packageName copy]; }
- (void)leavePackage:(NSString *)packageName { _currentPackage = nil; }
- (NSString *)currentPackageName { return _currentPackage; }

- (BOOL)isPathAllowedForCurrentPackage:(NSString *)absolutePath {
    if (!_currentPackage || !absolutePath) return NO;
    NSString *root = [[SDRSandboxDirectory sharedDirectory] ensureDataRootForPackage:_currentPackage];
    NSString *standardized = [absolutePath stringByStandardizingPath];
    NSString *rootStd = [root stringByStandardizingPath];
    // 路径需严格位于自身沙盒根之内（含边界）。
    return [standardized isEqualToString:rootStd] || [standardized hasPrefix:[rootStd stringByAppendingString:@"/"]];
}

- (NSString *)sanitizedPathForCurrentPackage:(NSString *)relativePath {
    if (!_currentPackage || !relativePath) return nil;
    NSString *root = [[SDRSandboxDirectory sharedDirectory] ensureDataRootForPackage:_currentPackage];
    NSString *candidate = [root stringByAppendingPathComponent:relativePath];
    // 拒绝包含 .. 逃逸的相对路径。
    if ([[relativePath pathComponents] containsObject:@".."]) return nil;
    return [self isPathAllowedForCurrentPackage:candidate] ? candidate : nil;
}

- (BOOL)canPackage:(NSString *)packageA accessPackage:(NSString *)packageB {
    return [packageA isEqualToString:packageB];
}

@end