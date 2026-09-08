/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRSymbolResolver.h"
#import <dlfcn.h>

// 常用 libc 导入符号 → iOS 系统库路径的映射。
static NSArray<NSString *> *SDR_LibLookupPaths(void) {
    static NSArray *paths;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        paths = @[
            @"/usr/lib/libSystem.B.dylib",  // 聚合 libc、libm、pthread 等
            @"/usr/lib/libc++.1.dylib",
        ];
    });
    return paths;
}

@implementation SDRSymbolResolver {
    SDRElfParser *_elf;
    NSMutableDictionary<NSString *, NSValue *> *_resolved;
}

- (instancetype)initWithElf:(SDRElfParser *)elf {
    if (self = [super init]) {
        _elf = elf;
        _resolved = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSDictionary<NSString *, NSValue *> *)resolvedSymbols { return _resolved; }

- (void *)resolveImportedSymbolNamed:(NSString *)name {
    if (!name || name.length == 0) return NULL;
    NSValue *cached = _resolved[name];
    if (cached) return cached.pointerValue;

    // 逐库查找（仅按导出名，等价 libc 常用基础函数）。
    for (NSString *path in SDR_LibLookupPaths()) {
        void *handle = dlopen(path.UTF8String, RTLD_LAZY);
        if (!handle) continue;
        void *sym = dlsym(handle, name.UTF8String);
        // 不 dlclose 交回，避免符号失效。
        if (sym) {
            _resolved[name] = [NSValue valueWithPointer:sym];
            return sym;
        }
    }
    return NULL;
}

- (SDRElfSymbol *)exportedSymbolNamed:(NSString *)name {
    return [_elf definedSymbolNamed:name];
}

@end