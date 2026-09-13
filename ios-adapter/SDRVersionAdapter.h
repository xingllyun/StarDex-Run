/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 系统版本适配器：区分 iOS 16-19 与 iOS 26-27 两套系统分支，自动适配 API 差异。
// 两代系统在内存策略、签名权限、原生接口上存在差异，运行时功能须按分支分流。
@interface SDRVersionAdapter : NSObject

@property (nonatomic, readonly) NSInteger majorVersion;
@property (nonatomic, readonly) NSInteger minorVersion;
@property (nonatomic, readonly) NSInteger patchVersion;

// 分支判定：旧分支（iOS 16 ~ 19），新分支（iOS 26 ~ 27）。
@property (nonatomic, readonly) BOOL isLegacyBranch;   // 16 ≤ major ≤ 19
@property (nonatomic, readonly) BOOL isModernBranch;   // 26 ≤ major ≤ 27

// 当前系统是否在本项目支持范围内。
@property (nonatomic, readonly) BOOL isSupported;

+ (instancetype)sharedAdapter;

// 分支名称（"legacy" / "modern"），供上层做接口分流。
- (NSString *)branchName;

// 当前系统描述文本（如 "iOS 26.4.2"）。
- (NSString *)systemDescription;

// 是否满足最低版本要求（基于给定最低版本比较）。
- (BOOL)systemVersionAtLeastMajor:(NSInteger)major minor:(NSInteger)minor;

@end

NS_ASSUME_NONNULL_END