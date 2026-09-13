/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 缓存管理：统一清理机制，支持单应用缓存清理与全局缓存清理。
@interface SDRSandboxCache : NSObject

+ (instancetype)sharedCache;

// 清理单个应用的 cache 子目录。
- (BOOL)clearCacheForPackage:(NSString *)packageName error:(NSError **)error;

// 清理所有应用的 cache 子目录（全局缓存清理）。
- (BOOL)clearAllCaches:(NSError **)error;

// 计算单个应用 cache 目录占用字节数。
- (unsigned long long)cacheSizeForPackage:(NSString *)packageName;

// 计算全局 cache 总占用字节数。
- (unsigned long long)totalCacheSize;

@end

NS_ASSUME_NONNULL_END