/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRApkInfo.h"

@implementation SDRApkInfo

- (instancetype)init {
    if (self = [super init]) {
        _permissions = @[];
        _activities = @[];
        _services = @[];
        _receivers = @[];
        _providers = @[];
        _dexFiles = @[];
        _nativeLibs = @[];
        _assetFiles = @[];
        _resourceFiles = @[];
        _minSdkVersion = 0;
        _targetSdkVersion = 0;
        _versionCode = 0;
    }
    return self;
}

@end