/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>
#import "SDRApkInfo.h"

NS_ASSUME_NONNULL_BEGIN

// APK 解析器：解包 APK、解析二进制 AndroidManifest.xml，
// 提取包名/版本/权限/四大组件，并分离 DEX、SO、资源、图标。
// 只读分析，不做任何运行时执行。
@interface SDRApkParser : NSObject

- (nullable instancetype)initWithApkData:(NSData *)apkData error:(NSError **)error;

// 进行完整解析，填充 SDRApkInfo；失败返回 nil 并写 error。
- (nullable SDRApkInfo *)parseInfo:(NSError **)error;

// 便捷：从 ZIP 条目按名取内容（供签名工具 / 解释器复用）。
- (nullable NSData *)entryDataNamed:(NSString *)name error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END