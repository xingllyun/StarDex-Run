/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>
#import "SDRElfParser.h"

NS_ASSUME_NONNULL_BEGIN

// SO 加载器：加载无外部依赖的简单原生库，完成内存映射、符号解析。
// 当前阶段仅保证简单无依赖 SO 可加载；复杂依赖 SO 暂不兼容。
@interface SDRSoLoader : NSObject

// 已加载库基址（为 0 表示未加载）。
@property (nonatomic, readonly) uintptr_t baseAddress;
@property (nonatomic, strong, readonly, nullable) SDRElfParser *elf;

// 从 ELF 数据加载共享库；成功返回 YES。
- (BOOL)loadSharedObjectData:(NSData *)soData error:(NSError **)error;

// 解析一个导出函数的运行地址（baseAddress + 段偏移）。
- (nullable void *)functionPointerForSymbol:(NSString *)symbol error:(NSError **)error;

// 卸载并释放映射内存。
- (void)unload;

@end

NS_ASSUME_NONNULL_END