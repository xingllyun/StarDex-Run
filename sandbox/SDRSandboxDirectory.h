/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 沙盒目录管理：每个应用独立沙盒目录，模拟安卓标准路径 /data/data/[包名]/。
// 数据完全隔离，无法跨应用访问。
@interface SDRSandboxDirectory : NSObject

// 全局应用沙盒根：<App沙盒>/Documents/apps/
@property (nonatomic, copy, readonly) NSString *appsRoot;

+ (instancetype)sharedDirectory;

// 返回指定应用的沙盒根目录（<appsRoot>/<包名>/），自动创建。
- (NSString *)ensureDataRootForPackage:(NSString *)packageName;

// 返回并确保标准子目录存在：files / cache / databases / shared_prefs。
- (NSString *)ensureSubdirectory:(NSString *)subdirectory forPackage:(NSString *)packageName;

// 列出当前已安装（已创建沙盒）的包名。
- (NSArray<NSString *> *)installedPackageNames;

// 删除指定应用的完整沙盒（彻底卸载）。
- (BOOL)removeDataRootForPackage:(NSString *)packageName error:(NSError **)error;

// Android 标准路径 → 当前应用沙盒内绝对路径（超出自身沙盒返回 nil）。
- (nullable NSString *)absolutePathForAndroidPath:(NSString *)androidPath;

@end

NS_ASSUME_NONNULL_END