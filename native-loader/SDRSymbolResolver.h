/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>
#import "SDRElfParser.h"

NS_ASSUME_NONNULL_BEGIN

// 符号解析器：将 ELF 导出/导入符号映射为可调用函数指针。
// 已实现：导出函数查找、导入符号对 iOS 系统 libc 的映射。
// 预留：完整 ELF 转译层、系统调用全量映射扩展位。
@interface SDRSymbolResolver : NSObject

- (instancetype)initWithElf:(SDRElfParser *)elf;

// 解析一个导入符号到 iOS 系统动态库函数指针（如 libc 常用函数）。
- (nullable void *)resolveImportedSymbolNamed:(NSString *)name;

// 解析 ELF 自身导出的符号（返回相对加载基址的偏移，尚未真正加载时为 0）。
- (nullable SDRElfSymbol *)exportedSymbolNamed:(NSString *)name;

// 当前已解析的导入符号表。
@property (nonatomic, strong, readonly) NSDictionary<NSString *, NSValue *> *resolvedSymbols;

@end

NS_ASSUME_NONNULL_END