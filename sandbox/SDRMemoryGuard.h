/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 单应用内存管控：检测当前进程物理内存足迹，为每个运行中的应用设置内存预算。
// 超出阈值时主动告警并触发资源回收提示，而不是等到系统 OOM 强杀进程。
@interface SDRMemoryGuard : NSObject

+ (instancetype)sharedGuard;

// 单应用内存上限（字节），默认 256MB。可按运行配置动态调整。
@property (nonatomic, assign) uint64_t perAppMemoryLimit;

// 当前进程物理内存足迹（phys_footprint，字节）。
@property (nonatomic, readonly) uint64_t currentFootprint;

// 内存压力回调：检测到超限时在主线程触发，供上层弹窗提示/主动回收。
@property (nonatomic, copy, nullable) void (^onMemoryPressure)(NSString *packageName, uint64_t footprint, uint64_t limit);

// 检查指定包是否超限；超限返回 NO 并通过 reason 返回说明。
- (BOOL)checkMemoryForPackage:(NSString *)packageName reason:(NSString * _Nullable * _Nullable)reason;

// 主动触发一次内存压力提示（用于解释器执行前后兜底）。
- (void)notifyMemoryWarningForPackage:(NSString *)packageName;

@end

NS_ASSUME_NONNULL_END