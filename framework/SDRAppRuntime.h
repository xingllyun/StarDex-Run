/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// APK 运行时：把「APK 文件」真正跑起来的执行管线。
// 流程：解包 APK → 加载全部 DEX → 构建类加载器 → 定位入口 Activity →
//       实例化并解释执行 onCreate，各步骤与结果通过完成回调上报。
// 当前阶段：聚焦打通执行链路（第一个版本可"点到为止"——
// 遇到未映射的 Android API 调用会以明确错误结束，而不会崩溃）。
@interface SDRAppRuntime : NSObject

+ (instancetype)sharedInstance;

// 在后台线程执行启动流程；completion 在主线程回调。
// apkPath：沙盒内 APK 副本路径。
// completion 参数：
//   summary：最终结果概述（成功/失败原因）
//   steps  ：分步日志（加载 DEX、定位入口、onCreate 结果等）
//   error  ：非 nil 表示启动流程失败
- (void)launchApkAtPath:(NSString *)apkPath
            packageName:(NSString *)packageName
             completion:(void (^)(NSString * _Nullable summary,
                                  NSArray<NSString *> * _Nullable steps,
                                  NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END