/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRVersionAdapter.h"

@implementation SDRVersionAdapter {
    NSOperatingSystemVersion _version;
}

+ (instancetype)sharedAdapter {
    static SDRVersionAdapter *adapter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        adapter = [[SDRVersionAdapter alloc] initInternal];
    });
    return adapter;
}

- (instancetype)initInternal {
    self = [super init];
    if (self) {
        _version = [NSProcessInfo processInfo].operatingSystemVersion;
    }
    return self;
}

- (NSInteger)majorVersion { return _version.majorVersion; }
- (NSInteger)minorVersion { return _version.minorVersion; }
- (NSInteger)patchVersion { return _version.patchVersion; }

- (BOOL)isLegacyBranch {
    return _version.majorVersion >= 16 && _version.majorVersion <= 19;
}

- (BOOL)isModernBranch {
    return _version.majorVersion >= 26 && _version.majorVersion <= 27;
}

- (BOOL)isSupported {
    return self.isLegacyBranch || self.isModernBranch;
}

- (NSString *)branchName {
    if (self.isLegacyBranch) return @"legacy";
    if (self.isModernBranch) return @"modern";
    return @"unsupported";
}

- (NSString *)systemDescription {
    return [NSString stringWithFormat:@"iOS %ld.%ld.%ld",
            (long)self.majorVersion, (long)self.minorVersion, (long)self.patchVersion];
}

- (BOOL)systemVersionAtLeastMajor:(NSInteger)major minor:(NSInteger)minor {
    if (_version.majorVersion != major) return _version.majorVersion > major;
    return _version.minorVersion >= minor;
}

@end