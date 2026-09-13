/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// APK 解析结果：包信息、组件、权限、DEX/SO 清单。
@interface SDRApkInfo : NSObject

@property (nonatomic, copy) NSString *packageName;
@property (nonatomic, copy) NSString *versionName;
@property (nonatomic, assign) int64_t versionCode;
@property (nonatomic, copy) NSString *appLabel;
@property (nonatomic, assign) uint32_t minSdkVersion;
@property (nonatomic, assign) uint32_t targetSdkVersion;

// uses-permission 的 android:name 全量列表。
@property (nonatomic, strong) NSArray<NSString *> *permissions;

// manifest 声明的四大组件类名（android:name 原始值）。
@property (nonatomic, strong) NSArray<NSString *> *activities;
@property (nonatomic, strong) NSArray<NSString *> *services;
@property (nonatomic, strong) NSArray<NSString *> *receivers;
@property (nonatomic, strong) NSArray<NSString *> *providers;

// 包内 APK 条目路径。
@property (nonatomic, strong) NSArray<NSString *> *dexFiles;   // classes.dex / classes2.dex ...
@property (nonatomic, strong) NSArray<NSString *> *nativeLibs; // lib/.../*.so
@property (nonatomic, strong) NSArray<NSString *> *assetFiles;
@property (nonatomic, strong) NSArray<NSString *> *resourceFiles;

// 应用图标（若可解析，返回解码后 PNG/JPEG 数据；否则 nil）。
@property (nonatomic, strong, nullable) NSData *iconData;

@end

NS_ASSUME_NONNULL_END