/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 原生桥接层：安卓 API 层通过本层统一调用 iOS 原生 Objective-C / C 接口。
// 职责：
//  1. 内存管理：自动管理 ObjC 对象与 Java 堆对象（SDRDexObject）的生命周期映射；
//  2. 线程模型：将安卓线程调度统一映射到 iOS GCD 线程模型。
@interface SDRNativeBridge : NSObject

// ---------------------------------------------------------------------------
// ObjC 对象生命周期映射
// ---------------------------------------------------------------------------

// 将原生对象绑定到指定 Java 堆对象（以对象内存地址为键），强引用持有，保证生命周期。
+ (void)bindNativeObject:(id)object toJavaObject:(uintptr_t)javaObjectAddr;

// 取回与 Java 堆对象绑定的原生对象；无绑定返回 nil。
+ (nullable id)nativeObjectForJavaObject:(uintptr_t)javaObjectAddr;

// 解除绑定并释放原生对象。
+ (void)unbindNativeObjectForJavaObject:(uintptr_t)javaObjectAddr;

// 是否已存在绑定。
+ (BOOL)hasBindingForJavaObject:(uintptr_t)javaObjectAddr;

// ---------------------------------------------------------------------------
// 线程模型映射
// ---------------------------------------------------------------------------

// 映射到主线程执行（对应安卓主线程 / UI 线程）。
+ (void)performOnMainThread:(dispatch_block_t)block;
+ (void)performOnMainThread:(dispatch_block_t)block waitUntilDone:(BOOL)wait;

// 映射到后台串行队列执行（对应安卓后台 Work 线程）。
+ (void)performOnBackgroundThread:(dispatch_block_t)block;

// 映射到可并发队列执行（对应安卓多线程任务分发）。
+ (void)performOnConcurrentThread:(dispatch_block_t)block;

// 当前是否在主线程（供 UI 相关 API 判断）。
+ (BOOL)isMainThread;

// 获取逻辑线程标识：主线程返回 0，其它返回当前线程 hash（用于调试日志）。
+ (uintptr_t)currentLogicalThreadId;

@end

NS_ASSUME_NONNULL_END