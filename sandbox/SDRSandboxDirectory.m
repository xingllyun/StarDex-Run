/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRSandboxDirectory.h"

// 标准子目录集合（对应安卓 /data/data/[包名]/ 结构）。
static NSArray<NSString *> *SDR_StandardSubdirs(void) {
    static NSArray *dirs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dirs = @[@"files", @"cache", @"databases", @"shared_prefs"];
    });
    return dirs;
}

@implementation SDRSandboxDirectory

+ (instancetype)sharedDirectory { static id s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [self new]; }); return s; }

- (instancetype)init {
    if (self = [super init]) {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        _appsRoot = [docs stringByAppendingPathComponent:@"apps"];
    }
    return self;
}

- (BOOL)ensureDirectoryAtPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) return YES;
    return [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (NSString *)ensureDataRootForPackage:(NSString *)packageName {
    NSString *root = [_appsRoot stringByAppendingPathComponent:packageName];
    [self ensureDirectoryAtPath:root];
    return root;
}

- (NSString *)ensureSubdirectory:(NSString *)subdirectory forPackage:(NSString *)packageName {
    NSString *root = [self ensureDataRootForPackage:packageName];
    NSString *dir = [root stringByAppendingPathComponent:subdirectory];
    [self ensureDirectoryAtPath:dir];
    return dir;
}

- (NSArray<NSString *> *)installedPackageNames {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *items = [fm contentsOfDirectoryAtPath:_appsRoot error:NULL] ?: @[];
    NSMutableArray *pkgs = [NSMutableArray array];
    for (NSString *item in items) {
        BOOL dir = NO;
        NSString *full = [_appsRoot stringByAppendingPathComponent:item];
        if ([fm fileExistsAtPath:full isDirectory:&dir] && dir) [pkgs addObject:item];
    }
    return pkgs;
}

- (BOOL)removeDataRootForPackage:(NSString *)packageName error:(NSError **)error {
    NSString *root = [_appsRoot stringByAppendingPathComponent:packageName];
    return [[NSFileManager defaultManager] removeItemAtPath:root error:error];
}

- (NSString *)absolutePathForAndroidPath:(NSString *)androidPath {
    // 形如 /data/data/[包名]/<subdir>/<rest> → <appsRoot>/<包名>/<subdir>/<rest>
    NSString *dataPrefix = @"/data/data/";
    if (![androidPath hasPrefix:dataPrefix]) return nil;
    NSString *relative = [androidPath substringFromIndex:dataPrefix.length];
    NSArray *comps = [relative pathComponents];
    if (comps.count == 0) return nil;
    // comps[0] 为包名，comps[1] 可能为 files/cache/databases 等。
    NSString *package = comps[0];
    NSString *rest = comps.count > 1 ? [NSString pathWithComponents:[comps subarrayWithRange:NSMakeRange(1, comps.count - 1)]] : @"";
    return [_appsRoot stringByAppendingPathComponent:package stringByAppendingPathComponent:rest];
}

@end