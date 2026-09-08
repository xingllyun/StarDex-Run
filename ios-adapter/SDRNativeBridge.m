/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRNativeBridge.h"

// ============================================================================
// ObjC 对象 ↔ Java 堆对象 生命周期映射
// ============================================================================

// 键：Java 堆对象内存地址（uintptr_t）→ 值：强引用持有的原生对象。
// 使用 NSMutableDictionary（对象强引用）自动保障 ObjC 对象不被提前释放。
static NSMutableDictionary<NSNumber *, id> *SDR_NativeObjectRegistry(void) {
    static NSMutableDictionary *registry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [NSMutableDictionary dictionary];
    });
    return registry;
}

@implementation SDRNativeBridge

+ (void)bindNativeObject:(id)object toJavaObject:(uintptr_t)javaObjectAddr {
    if (!object || javaObjectAddr == 0) return;
    @synchronized (SDR_NativeObjectRegistry()) {
        SDR_NativeObjectRegistry()[@(javaObjectAddr)] = object;
    }
}

+ (id)nativeObjectForJavaObject:(uintptr_t)javaObjectAddr {
    if (javaObjectAddr == 0) return nil;
    @synchronized (SDR_NativeObjectRegistry()) {
        return SDR_NativeObjectRegistry()[@(javaObjectAddr)];
    }
}

+ (void)unbindNativeObjectForJavaObject:(uintptr_t)javaObjectAddr {
    if (javaObjectAddr == 0) return;
    @synchronized (SDR_NativeObjectRegistry()) {
        [SDR_NativeObjectRegistry() removeObjectForKey:@(javaObjectAddr)];
    }
}

+ (BOOL)hasBindingForJavaObject:(uintptr_t)javaObjectAddr {
    if (javaObjectAddr == 0) return NO;
    @synchronized (SDR_NativeObjectRegistry()) {
        return SDR_NativeObjectRegistry()[@(javaObjectAddr)] != nil;
    }
}

// ============================================================================
// 线程模型映射：安卓线程 → iOS GCD
// ============================================================================

+ (void)performOnMainThread:(dispatch_block_t)block {
    [self performOnMainThread:block waitUntilDone:NO];
}

+ (void)performOnMainThread:(dispatch_block_t)block waitUntilDone:(BOOL)wait {
    if (!block) return;
    if ([self isMainThread]) {
        block();
    } else if (wait) {
        dispatch_sync(dispatch_get_main_queue(), block);
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

+ (void)performOnBackgroundThread:(dispatch_block_t)block {
    if (!block) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), block);
}

+ (void)performOnConcurrentThread:(dispatch_block_t)block {
    if (!block) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), block);
}

+ (BOOL)isMainThread {
    return [NSThread isMainThread];
}

+ (uintptr_t)currentLogicalThreadId {
    return [NSThread isMainThread] ? 0 : (uintptr_t)[NSThread currentThread];
}

@end