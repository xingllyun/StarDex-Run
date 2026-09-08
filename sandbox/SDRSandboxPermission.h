/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 权限管控：应用仅能访问自身沙盒内文件，禁止越权访问。
// 通过记录「当前活动包名」并对其文件路径做沙盒边界校验实现。
@interface SDRSandboxPermission : NSObject

+ (instancetype)sharedPermission;

// 设置 / 清除当前活动应用（随 Activity 栈顶切换）。
- (void)enterPackage:(NSString *)packageName;
- (void)leavePackage:(NSString *)packageName;
- (nullable NSString *)currentPackageName;

// 判定某绝对路径是否允许当前应用访问。返回 YES 表示位于当前应用沙盒内。
- (BOOL)isPathAllowedForCurrentPackage:(NSString *)absolutePath;

// 将相对路径解析并校验，非法返回 nil（禁止越权访问的核心屏障）。
- (nullable NSString *)sanitizedPathForCurrentPackage:(NSString *)relativePath;

// 判定两个包是否为同一应用（用于跨组件访问校验）。
- (BOOL)canPackage:(NSString *)packageA accessPackage:(NSString *)packageB;

@end

NS_ASSUME_NONNULL_END