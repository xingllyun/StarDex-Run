/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

@class SDRApkInfo;

NS_ASSUME_NONNULL_BEGIN

// APK 导入安装器：把 APK 解包后按 DEX / SO / 资源 / Manifest 分类存入对应沙盒目录，
// 并维护一份包元数据 plist（metadata.plist）供启动管线与包管理器读取。
// 全程流式分片解压，控制内存峰值；任何损坏包 / 非法格式只返回错误，绝不崩溃。
@interface SDRPackageInstaller : NSObject

+ (instancetype)sharedInstaller;

// 在后台线程安装 APK；completion 在主线程回调。
- (void)installApkAtPath:(NSString *)apkPath
              completion:(void (^)(SDRApkInfo * _Nullable info, NSError * _Nullable error))completion;

// 同步安装（内部调用，需在后台线程执行）。
- (nullable SDRApkInfo *)installApkAtPath:(NSString *)apkPath error:(NSError **)error;

// 已安装应用的元数据（nil 表示未安装）。
- (nullable NSDictionary<NSString *, id> *)metadataForPackage:(NSString *)packageName;

// 已安装应用列表（从各包 metadata.plist 重建 SDRApkInfo）。
- (NSArray<SDRApkInfo *> *)installedApkInfos;

@end

NS_ASSUME_NONNULL_END