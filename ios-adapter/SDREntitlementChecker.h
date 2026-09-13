/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 单项签名权限的检测状态。
typedef NS_ENUM(NSInteger, SDREntitlementStatus) {
    SDREntitlementUnknown = -1,  // 无法确定（如无嵌入描述文件、接口被剥离）
    SDREntitlementMissing = 0,   // 明确缺失
    SDREntitlementPresent  = 1   // 明确存在
};

// 权限检测结果封装。侧载运行所需的两项硬性权限：
//  - 大地址空间：com.apple.developer.kernel.extended-virtual-addressing
//  - 大内存：com.apple.developer.kernel.increased-memory-limit
@interface SDREntitlementReport : NSObject

@property (nonatomic, assign) SDREntitlementStatus largeAddressSpace; // 大地址空间
@property (nonatomic, assign) SDREntitlementStatus largeMemory;       // 大内存

// 缺失项的中文标题（用于 UI 红色高亮告警），如 @[@"大地址空间", @"大内存"]。
@property (nonatomic, readonly) NSArray<NSString *> *missingTitles;

// 两项权限是否均已明确存在（Unknown 视为不满足，避免带病运行）。
@property (nonatomic, readonly) BOOL fullySatisfied;

// 生成面向设置页的摘要文字。
- (NSString *)summaryText;

// 生成面向启动告警弹窗的降级文案；无缺失项时返回 nil。
- (nullable NSString *)degradedTipText;

@end

// 权限检测器：启动时自动检测「大地址空间」「大内存」两项签名权限。
@interface SDREntitlementChecker : NSObject

// 检测当前进程（宿主 App）的签名权限。
+ (SDREntitlementReport *)checkCurrentProcess;

// 从嵌入描述文件解析出的完整 Entitlements 字典；无嵌入描述文件返回 nil。
+ (nullable NSDictionary<NSString *, id> *)embeddedProvisionEntitlements;

@end

NS_ASSUME_NONNULL_END