/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRSoLoader.h"
#import "SDRSymbolResolver.h"
#import <sys/mman.h>
#import <unistd.h>

@implementation SDRSoLoader

- (void *)functionPointerForSymbol:(NSString *)symbol error:(NSError **)error {
    if (!_elf || !symbol) return NULL;
    SDRElfSymbol *sym = [_elf definedSymbolNamed:symbol];
    if (!sym) {
        if (error) *error = [NSError errorWithDomain:@"SDRSoLoader" code:1
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"未找到导出符号: %@", symbol]}];
        return NULL;
    }
    return (void *)(_baseAddress + sym.value);
}

- (BOOL)loadSharedObjectData:(NSData *)soData error:(NSError **)error {
    SDRElfParser *elf = [[SDRElfParser alloc] initWithData:soData error:error];
    if (!elf) return NO;

    // 计算所有可加载段的总内存大小，并映射一块 RWX 匿名内存。
    size_t totalSize = 0;
    for (SDRElfSegment *seg in elf.segments) {
        if (seg.type != 1 /* PT_LOAD */) continue;
        size_t end = (size_t)(seg.vaddr + seg.memSize);
        if (end > totalSize) totalSize = end;
    }
    if (totalSize == 0) {
        if (error) *error = [NSError errorWithDomain:@"SDRSoLoader" code:2
            userInfo:@{NSLocalizedDescriptionKey: @"无可加载段"}];
        return NO;
    }

    uintptr_t base = (uintptr_t)mmap(NULL, totalSize, PROT_READ | PROT_WRITE | PROT_EXEC,
                                     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (base == (uintptr_t)MAP_FAILED) {
        if (error) *error = [NSError errorWithDomain:@"SDRSoLoader" code:3
            userInfo:@{NSLocalizedDescriptionKey: @"内存映射失败"}];
        return NO;
    }

    // 拷贝各加载段文件内容到对应虚拟地址。
    const uint8_t *src = soData.bytes;
    for (SDRElfSegment *seg in elf.segments) {
        if (seg.type != 1 /* PT_LOAD */) continue;
        if (seg.fileOffset + seg.fileSize > soData.length) continue;
        memcpy((void *)(base + seg.vaddr), src + seg.fileOffset, (size_t)seg.fileSize);
        // 清零 BSS 部分（memSize > fileSize 的差额）。
        if (seg.memSize > seg.fileSize) {
            memset((void *)(base + seg.vaddr + seg.fileSize), 0, (size_t)(seg.memSize - seg.fileSize));
        }
    }

    _elf = elf;
    _baseAddress = base;

    // 骨架阶段：不处理重定位，简单无依赖 SO（如纯计算函数 PIC）可直接调用。
    (void)[[SDRSymbolResolver alloc] initWithElf:elf];
    return YES;
}

- (void)unload {
    if (_baseAddress) {
        munmap((void *)_baseAddress, 0); // 未记录总大小；骨架阶段占位
        _baseAddress = 0;
    }
    _elf = nil;
}

@end